package com.careconnect.config;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import javax.sql.DataSource;
import java.sql.Connection;
import java.sql.DatabaseMetaData;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * {@code SchemaPatchRunner.run()} end to end against a scripted JDBC double, one for PostgreSQL and one for H2
 * (Test Plan §3.11, TC-EHR-SCH-030…039). The double records every statement and answers the runner's catalog
 * queries (advisory lock, index status, foreign-key counts, schema verifications) the way a healthy database
 * would, unless a test sets one of its knobs to break a single answer.
 * <p>
 * This shows the order and the fail-open / fail-closed choices of the startup sequence; it does not show that the
 * SQL is valid PostgreSQL. {@code EhrCanonicalSchemaPostgresTest} and {@code EmergencyPassportSchemaPostgresTest}
 * do that against a real database.
 * <p>
 * Test IDs TC-EHR-SCH-030…039 are permanent. Never renumber, never reuse.
 */
class SchemaPatchRunnerStartupTest {

    private static final Pattern INDEX_NAME =
            Pattern.compile("(?i)CREATE\\s+(?:UNIQUE\\s+)?INDEX\\s+(?:CONCURRENTLY\\s+)?(?:IF NOT EXISTS\\s+)?(\\w+)");
    private static final Pattern STATUS_RELNAME = Pattern.compile("c\\.relname = '(\\w+)'");

    /** A scripted database: records what the runner sends and answers what it asks. */
    private static final class FakeDatabase {
        final List<String> events = new ArrayList<>();
        final Map<String, String> indexDefinitions = new HashMap<>();
        final SchemaPatchLedger ledger = mock(SchemaPatchLedger.class);
        boolean embeddingColumnPresent = true;
        boolean indexesBecomeValid = true;
        boolean unknownRecordingStatus = false;
        int foreignKeyCount = 1;
        int callTerminationColumns = 7;
        int retrievalColumnIssues = 0;

        SchemaPatchRunner runnerOn(final String databaseProductName) throws SQLException {
            final DataSource dataSource = mock(DataSource.class);
            final Connection connection = mock(Connection.class);
            final DatabaseMetaData metadata = mock(DatabaseMetaData.class);
            final Statement statement = mock(Statement.class);
            when(dataSource.getConnection()).thenReturn(connection);
            when(connection.getMetaData()).thenReturn(metadata);
            when(connection.createStatement()).thenReturn(statement);
            when(statement.getConnection()).thenReturn(connection);
            when(metadata.getDatabaseProductName()).thenReturn(databaseProductName);
            doAnswer(invocation -> {
                final String sql = invocation.getArgument(0);
                events.add(sql);
                final Matcher index = INDEX_NAME.matcher(sql);
                if (index.find()) {
                    indexDefinitions.put(index.group(1).toLowerCase(), sql);
                }
                return false;
            }).when(statement).execute(anyString());
            doAnswer(invocation -> {
                events.add(invocation.getArgument(0));
                return 1;
            }).when(statement).executeUpdate(anyString());
            doAnswer(invocation -> answer(invocation.getArgument(0))).when(statement).executeQuery(anyString());
            doAnswer(invocation -> events.add("LEDGER initialize")).when(ledger).initialize();
            doAnswer(invocation -> events.add("LEDGER apply " + ((SchemaPatchLedger.Patch) invocation.getArgument(0)).id()))
                    .when(ledger).apply(any());
            return new SchemaPatchRunner(dataSource, ledger);
        }

        private ResultSet answer(final String sql) {
            events.add(sql);
            if (sql.contains("pg_try_advisory_lock") || sql.contains("pg_advisory_unlock")) {
                return row(Map.of(1, true));
            }
            if (sql.contains("pg_get_indexdef(i.indexrelid),")) {
                final Matcher name = STATUS_RELNAME.matcher(sql);
                final String definition = name.find() ? indexDefinitions.get(name.group(1).toLowerCase()) : null;
                return definition == null ? empty() : row(Map.of(1, indexesBecomeValid, 2, definition, 3, "public"));
            }
            if (sql.startsWith("SELECT COUNT(*) FROM pg_constraint c")) {
                return row(Map.of(1, foreignKeyCount));
            }
            if (sql.contains("'termination_claim_id'")) {
                return row(Map.of("column_count", callTerminationColumns, "attempt_default_count", 1,
                        "check_count", 1, "index_count", 1));
            }
            if (sql.contains("uq_call_summary_generation_snapshot")) {
                return row(Map.of("column_count", 2, "index_count", 1));
            }
            if (sql.contains("format_type(a.atttypid, a.atttypmod) = 'vector(1536)'")) {
                return row(Map.of(1, embeddingColumnPresent));
            }
            if (sql.contains("AS column_issues")) {
                return row(Map.of("column_issues", retrievalColumnIssues, "constraint_issues", 0,
                        "index_issues", 0, "trigger_count", 1));
            }
            if (sql.contains("FROM call_recordings")) {
                return row(Map.of(1, unknownRecordingStatus));
            }
            return empty();
        }

        int indexOf(final String fragment) {
            for (int i = 0; i < events.size(); i++) {
                if (events.get(i).contains(fragment)) {
                    return i;
                }
            }
            return -1;
        }

        boolean sent(final String fragment) {
            return indexOf(fragment) >= 0;
        }
    }

    /** One row whose columns are looked up by index or label. */
    private static ResultSet row(final Map<Object, Object> values) {
        return resultSet(values, true);
    }

    private static ResultSet empty() {
        return resultSet(Map.of(), false);
    }

    private static ResultSet resultSet(final Map<Object, Object> values, final boolean hasRow) {
        final boolean[] read = {false};
        return mock(ResultSet.class, invocation -> switch (invocation.getMethod().getName()) {
            case "next" -> {
                final boolean next = hasRow && !read[0];
                read[0] = true;
                yield next;
            }
            case "getBoolean" -> values.getOrDefault(invocation.getArgument(0), false);
            case "getInt" -> values.getOrDefault(invocation.getArgument(0), 0);
            case "getString" -> values.get(invocation.getArgument(0));
            default -> null;
        });
    }

    @Test
    @DisplayName("TC-EHR-SCH-030: on PostgreSQL, startup takes the advisory lock, applies every catalog patch "
            + "through the ledger, releases the lock, then builds the concurrent indexes and verifies")
    void postgresStartupRunsEveryPhaseInOrder() throws Exception {
        final FakeDatabase db = new FakeDatabase();

        db.runnerOn("PostgreSQL").run();

        final int lock = db.indexOf("pg_try_advisory_lock");
        final int initialize = db.indexOf("LEDGER initialize");
        final int unlock = db.indexOf("pg_advisory_unlock");
        final int concurrent = db.indexOf("CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_retrieval_summary_replay");
        final int embedding = db.indexOf("format_type(a.atttypid, a.atttypmod) = 'vector(1536)'");
        assertThat(lock).isGreaterThanOrEqualTo(0);
        assertThat(initialize).isGreaterThan(lock);
        assertThat(unlock).isGreaterThan(initialize);
        assertThat(concurrent).as("concurrent index builds run after the lock is released").isGreaterThan(unlock);
        assertThat(embedding).isGreaterThan(concurrent);
        for (final String id : SchemaPatchRunner.catalogPatchIdsAppliedByRunner()) {
            final int applied = db.indexOf("LEDGER apply " + id);
            assertThat(applied).as("catalog patch %s applied inside the lock", id).isBetween(initialize, unlock);
        }
    }

    @Test
    @DisplayName("TC-EHR-SCH-031: on PostgreSQL, the EHR, passport and demo-seed steps run after the "
            + "shared patches, in that order")
    void postgresStartupRunsTheSchemaStepsInOrder() throws Exception {
        final FakeDatabase db = new FakeDatabase();

        db.runnerOn("PostgreSQL").run();

        final int confirmation = db.indexOf("CREATE TABLE IF NOT EXISTS confirmation_items");
        final int ehrIdentity = db.indexOf("fk_ehr_source_identity_patient");
        final int ehrZone = db.indexOf("table_name = 'ehr_identity_field_provenance'");
        final int passport = db.indexOf("uq_emergency_passport_profile_patient");
        final int seed = db.indexOf("INSERT INTO scheduled_visits");
        assertThat(confirmation).isGreaterThanOrEqualTo(0);
        assertThat(ehrIdentity).isGreaterThan(confirmation);
        assertThat(ehrZone).isGreaterThan(ehrIdentity);
        assertThat(passport).isGreaterThan(ehrZone);
        assertThat(seed).isGreaterThan(passport);
    }

    @Test
    @DisplayName("TC-EHR-SCH-032: on H2, startup creates the H2 parity tables and never takes the advisory "
            + "lock, touches the ledger or sends a PostgreSQL-only patch")
    void h2StartupUsesTheParityTablesOnly() throws Exception {
        final FakeDatabase db = new FakeDatabase();

        db.runnerOn("H2").run();

        assertThat(db.sent("CREATE TABLE IF NOT EXISTS ai_held_item")).isTrue();
        assertThat(db.sent("CREATE TABLE IF NOT EXISTS consent_grants")).isTrue();
        assertThat(db.sent("CREATE TABLE IF NOT EXISTS ai_ask_conversation_share")).isTrue();
        assertThat(db.sent("pg_try_advisory_lock")).isFalse();
        assertThat(db.sent("CREATE EXTENSION IF NOT EXISTS vector")).isFalse();
        assertThat(db.sent("uq_emergency_passport_profile_patient")).isFalse();
        verify(db.ledger, never()).initialize();
        verify(db.ledger, never()).apply(any());
    }

    @Test
    @DisplayName("TC-EHR-SCH-033: an existing index whose definition has drifted is dropped and rebuilt")
    void driftedIndexIsRebuilt() throws Exception {
        final FakeDatabase db = new FakeDatabase();
        db.indexDefinitions.put("idx_retrieval_summary_replay",
                "CREATE INDEX idx_retrieval_summary_replay ON retrieval_index_chunk (patient_id)");

        db.runnerOn("PostgreSQL").run();

        final int drop = db.indexOf("DROP INDEX CONCURRENTLY IF EXISTS idx_retrieval_summary_replay");
        assertThat(drop).isGreaterThanOrEqualTo(0);
        assertThat(db.events.subList(drop, db.events.size()))
                .anyMatch(sql -> sql.startsWith("CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_retrieval_summary_replay"));
    }

    @Test
    @DisplayName("TC-EHR-SCH-034: an index that is still not valid after it is built stops startup")
    void invalidIndexStopsStartup() throws Exception {
        final FakeDatabase db = new FakeDatabase();
        db.indexesBecomeValid = false;

        assertThatThrownBy(() -> db.runnerOn("PostgreSQL").run())
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("could not be prepared");
        assertThat(db.sent("pg_advisory_unlock")).as("the lock is released on the way out").isTrue();
    }

    @Test
    @DisplayName("TC-EHR-SCH-035: a missing retrieval_index_chunk.embedding vector(1536) column stops startup")
    void missingEmbeddingColumnStopsStartup() throws Exception {
        final FakeDatabase db = new FakeDatabase();
        db.embeddingColumnPresent = false;

        assertThatThrownBy(() -> db.runnerOn("PostgreSQL").run())
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("embedding vector(1536) column is missing");
    }

    @Test
    @DisplayName("TC-EHR-SCH-036: call-termination and retrieval verification mismatches are logged, "
            + "not fatal, and startup finishes")
    void verificationMismatchesAreNotFatal() throws Exception {
        final FakeDatabase db = new FakeDatabase();
        db.callTerminationColumns = 6;
        db.retrievalColumnIssues = 1;

        db.runnerOn("PostgreSQL").run();

        assertThat(db.sent("INSERT INTO scheduled_visits")).as("startup reached its last step").isTrue();
    }

    @Test
    @DisplayName("TC-EHR-SCH-037: a missing required foreign key stops startup and still releases the lock")
    void missingForeignKeyStopsStartup() throws Exception {
        final FakeDatabase db = new FakeDatabase();
        db.foreignKeyCount = 0;

        assertThatThrownBy(() -> db.runnerOn("PostgreSQL").run())
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("foreign key count verification failed");
        assertThat(db.sent("pg_advisory_unlock")).isTrue();
    }

    @Test
    @DisplayName("TC-EHR-SCH-038: a call recording with an unknown legacy status stops startup before the "
            + "recording-state catalog patch")
    void unknownRecordingStatusStopsStartup() throws Exception {
        final FakeDatabase db = new FakeDatabase();
        db.unknownRecordingStatus = true;

        assertThatThrownBy(() -> db.runnerOn("PostgreSQL").run())
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("Unknown legacy recording status");
        assertThat(db.sent("LEDGER apply 2607191700-recording-state")).isFalse();
    }

    @Test
    @DisplayName("TC-EHR-SCH-039: when the database product cannot be read, startup stops")
    void unreadableDatabaseStopsStartup() throws Exception {
        final DataSource dataSource = mock(DataSource.class);
        final Connection connection = mock(Connection.class);
        final Statement statement = mock(Statement.class);
        when(dataSource.getConnection()).thenReturn(connection);
        when(connection.createStatement()).thenReturn(statement);
        when(statement.getConnection()).thenReturn(connection);
        when(connection.getMetaData()).thenThrow(new SQLException("connection reset"));

        assertThatThrownBy(() -> new SchemaPatchRunner(dataSource, mock(SchemaPatchLedger.class)).run())
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("Unable to identify database for schema patches");
    }
}
