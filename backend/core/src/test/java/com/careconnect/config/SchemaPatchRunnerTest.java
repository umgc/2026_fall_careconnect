package com.careconnect.config;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import javax.sql.DataSource;
import java.sql.Connection;
import java.sql.DatabaseMetaData;
import java.sql.SQLException;
import java.sql.Statement;
import java.sql.ResultSet;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Test IDs TC-EHR-SCH-020..021 (the two {@code requireSafeIdentifier} tests) are permanent. Never renumber,
 * never reuse.
 */
class SchemaPatchRunnerTest {

    @Test
    @DisplayName("TC-EHR-SCH-020: plain identifiers pass the guard unchanged")
    void requireSafeIdentifier_acceptsPlainIdentifiers() {
        assertThat(SchemaPatchRunner.requireSafeIdentifier("ehr_raw_payload")).isEqualTo("ehr_raw_payload");
        assertThat(SchemaPatchRunner.requireSafeIdentifier("fk_ehr_crosswalk_patient"))
                .isEqualTo("fk_ehr_crosswalk_patient");
        assertThat(SchemaPatchRunner.requireSafeIdentifier("_t1")).isEqualTo("_t1");
    }

    @Test
    @DisplayName("TC-EHR-SCH-021: an identifier that could change the statement is rejected")
    void requireSafeIdentifier_rejectsAnythingThatCouldChangeTheStatement() {
        for (final String hostile : new String[]{
                "patient; DROP TABLE patient",
                "patient'::regclass) THEN DROP TABLE patient; --",
                "public.patient",
                "\"patient\"",
                "patient id",
                "1patient",
                ""}) {
            assertThatThrownBy(() -> SchemaPatchRunner.requireSafeIdentifier(hostile))
                    .as("identifier <%s>", hostile)
                    .isInstanceOf(IllegalArgumentException.class);
        }
        assertThatThrownBy(() -> SchemaPatchRunner.requireSafeIdentifier(null))
                .isInstanceOf(IllegalArgumentException.class);
    }

    @Test
    void normalizeIndexDefinition_acceptsPostgresCanonicalPredicateCasts() {
        final String requested = """
                CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_summary_replay_claim_fair
                ON summary_citation_replay_source
                (replay_after ASC NULLS FIRST, attempts ASC, patient_id,
                 source_kind, source_record_id)
                WHERE migration_status = 'ACTIVE' AND claim_token IS NULL
                """;
        final String catalogDefinition = """
                CREATE INDEX idx_summary_replay_claim_fair
                ON public.summary_citation_replay_source USING btree
                (replay_after NULLS FIRST, attempts, patient_id, source_kind, source_record_id)
                WHERE (((migration_status)::text = 'ACTIVE'::text) AND (claim_token IS NULL))
                """;

        assertThat(SchemaPatchRunner.normalizeIndexDefinition(
                catalogDefinition, "public"))
                .isEqualTo(SchemaPatchRunner.normalizeIndexDefinition(
                        requested, "public"));
    }

    @Test
    void applyCallSessionPatches_ensureUniqueIndexesForOnConflict() throws Exception {
        final java.nio.file.Path sourcePath = java.nio.file.Path.of(
                "src/main/java/com/careconnect/config/SchemaPatchRunner.java");
        final java.nio.file.Path resolved = java.nio.file.Files.exists(sourcePath)
                ? sourcePath
                : java.nio.file.Path.of(
                "backend/core/src/main/java/com/careconnect/config/SchemaPatchRunner.java");
        final String source = java.nio.file.Files.readString(resolved);
        assertThat(source).contains("idx_call_sessions_call_id_uidx");
        assertThat(source).contains("idx_call_participants_session_user_uidx");
    }

    @Test
    void isIdempotentAlreadyApplied_doesNotSkipMissingTypeOnCreate() {
        assertThat(SchemaPatchRunner.isIdempotentAlreadyApplied(
                "ERROR: type \"vector\" does not exist",
                "CREATE EXTENSION IF NOT EXISTS vector"))
                .isFalse();
        assertThat(SchemaPatchRunner.isIdempotentAlreadyApplied(
                "ERROR: type \"vector\" does not exist",
                "CREATE TABLE IF NOT EXISTS retrieval_index_chunk (embedding vector(1536))"))
                .isFalse();
        assertThat(SchemaPatchRunner.isIdempotentAlreadyApplied(
                "ERROR: column \"embedding\" does not exist",
                "CREATE INDEX idx_retrieval_chunk_embedding ON retrieval_index_chunk (embedding)"))
                .isFalse();
    }

    @Test
    void isIdempotentAlreadyApplied_skipsOptionalDropOrRenameOfMissingObject() {
        assertThat(SchemaPatchRunner.isIdempotentAlreadyApplied(
                "ERROR: column \"stripe_customer_id\" does not exist",
                "ALTER TABLE users RENAME COLUMN stripe_customer_id TO payment_customer_id"))
                .isTrue();
        assertThat(SchemaPatchRunner.isIdempotentAlreadyApplied(
                "ERROR: constraint \"user_files_file_category_check\" does not exist",
                "ALTER TABLE user_files DROP CONSTRAINT user_files_file_category_check"))
                .isTrue();
        assertThat(SchemaPatchRunner.isIdempotentAlreadyApplied(
                "ERROR: relation \"foo\" already exists",
                "CREATE TABLE foo (id INT)"))
                .isTrue();
    }

    @Test
    void applyRetrieval_includesDedicatedEmbeddingColumnRepair() throws Exception {
        final java.nio.file.Path sourcePath = java.nio.file.Path.of(
                "src/main/java/com/careconnect/config/SchemaPatchRunner.java");
        final java.nio.file.Path resolved = java.nio.file.Files.exists(sourcePath)
                ? sourcePath
                : java.nio.file.Path.of(
                "backend/core/src/main/java/com/careconnect/config/SchemaPatchRunner.java");
        final String source = java.nio.file.Files.readString(resolved);
        final String applyRetrievalBody = source.substring(
                source.indexOf("private void applyRetrievalIndexChunkPatches()"),
                source.indexOf("private void applyUspsMailpiecePatches()"));
        assertThat(applyRetrievalBody).contains(
                "V2607071921a2 – ensure retrieval_index_chunk.embedding column");
        assertThat(applyRetrievalBody).contains(
                "ADD COLUMN IF NOT EXISTS embedding vector(1536) NULL");
        assertThat(source).contains("verifyRetrievalEmbeddingColumnPresent();");
        assertThat(source).contains("isIdempotentAlreadyApplied");
        assertThat(source).doesNotContain(
                "msg.contains(\"42P16\") || msg.contains(\"already\") || msg.contains(\"does not exist\")");
    }

    @Test
    void run_appliesConcurrentRetrievalIndexesBeforeRequiredSchemaVerify() throws Exception {
        // Contract: verifyRequiredRetrievalSchema expects GIN/ivfflat/source-identity indexes
        // that are only created in ensureRetrievalConcurrentIndexes after the migration unlock.
        // Guard the source ordering so greenfield PostgreSQL boots cannot regress.
        final java.nio.file.Path sourcePath = java.nio.file.Path.of(
                "src/main/java/com/careconnect/config/SchemaPatchRunner.java");
        final java.nio.file.Path resolved = java.nio.file.Files.exists(sourcePath)
                ? sourcePath
                : java.nio.file.Path.of(
                "backend/core/src/main/java/com/careconnect/config/SchemaPatchRunner.java");
        final String source = java.nio.file.Files.readString(resolved);
        final int unlockIndexes = source.indexOf("ensureRetrievalConcurrentIndexes();");
        final int embeddingVerify = source.indexOf(
                "verifyRetrievalEmbeddingColumnPresent();", unlockIndexes);
        final int postUnlockVerify = source.indexOf(
                "verifyRequiredRetrievalSchema();", unlockIndexes);
        final String applyRetrievalBody = source.substring(
                source.indexOf("private void applyRetrievalIndexChunkPatches()"),
                source.indexOf("private void applyUspsMailpiecePatches()"));
        assertThat(unlockIndexes).isGreaterThan(0);
        assertThat(embeddingVerify).isGreaterThan(unlockIndexes);
        assertThat(postUnlockVerify).isGreaterThan(embeddingVerify);
        assertThat(applyRetrievalBody).doesNotContain("verifyRequiredRetrievalSchema();");
        assertThat(applyRetrievalBody).doesNotContain("verifyRetrievalEmbeddingColumnPresent();");
    }

    @Test
    void run_waitsTenMinutesForProductionSchemaMigrationLock() throws Exception {
        final java.nio.file.Path sourcePath = java.nio.file.Path.of(
                "src/main/java/com/careconnect/config/SchemaPatchRunner.java");
        final java.nio.file.Path resolved = java.nio.file.Files.exists(sourcePath)
                ? sourcePath
                : java.nio.file.Path.of(
                "backend/core/src/main/java/com/careconnect/config/SchemaPatchRunner.java");
        final String source = java.nio.file.Files.readString(resolved);
        assertThat(source).contains("TimeUnit.MINUTES.toNanos(10)");
        assertThat(source).doesNotContain("TimeUnit.SECONDS.toNanos(30)");
    }

    @Test
    void verifyCallTerminationSchema_toleratesPostgresPredicateCastsAndIsNonFatal()
            throws Exception {
        // Postgres stores predicates as status = 'TERMINATING'::text; exact-quote
        // POSITION checks false-negative and used to crash-loop startup.
        final java.nio.file.Path sourcePath = java.nio.file.Path.of(
                "src/main/java/com/careconnect/config/SchemaPatchRunner.java");
        final java.nio.file.Path resolved = java.nio.file.Files.exists(sourcePath)
                ? sourcePath
                : java.nio.file.Path.of(
                "backend/core/src/main/java/com/careconnect/config/SchemaPatchRunner.java");
        final String source = java.nio.file.Files.readString(resolved);
        final int methodStart = source.indexOf("private void verifyCallTerminationSchema()");
        final int methodEnd = source.indexOf(
                "private void verifyCallSummaryIdempotencySchema()", methodStart);
        final String method = methodEnd > methodStart
                ? source.substring(methodStart, methodEnd)
                : source.substring(methodStart);
        assertThat(method).doesNotContain("status = ''TERMINATING''");
        assertThat(method).contains("POSITION(");
        assertThat(method).contains("'TERMINATING'");
        assertThat(method).contains("continuing startup (non-fatal)");
        assertThat(method).contains("columns={}");
        assertThat(method).contains("default={}");
        assertThat(method).contains("check={}");
        assertThat(method).contains("index={}");
        assertThat(method).doesNotContain("throw new IllegalStateException");
    }

    /**
     * Scenario: integration tests run on H2, which never sees the Flyway/catalog DDL, so the
     * runner's H2 parity patch must create both condition detection tables, be safe to re-run on
     * every startup, and keep the one-run-per-(call, model) rule the worker's idempotent enqueue
     * relies on. Uses a real in-memory H2 database rather than mocks so the DDL itself is checked.
     */
    @Test
    void applyH2ConditionDetectionTables_createsTablesIdempotentlyWithUniqueCallModel()
            throws Exception {
        // Arrange
        final org.h2.jdbcx.JdbcDataSource h2 = new org.h2.jdbcx.JdbcDataSource();
        h2.setURL("jdbc:h2:mem:condition_detection_parity;DB_CLOSE_DELAY=-1");
        final SchemaPatchRunner runner = new SchemaPatchRunner(h2, mock(SchemaPatchLedger.class));

        // Act: twice, as every application start does
        org.springframework.test.util.ReflectionTestUtils.invokeMethod(
                runner, "applyH2ConditionDetectionTables");
        org.springframework.test.util.ReflectionTestUtils.invokeMethod(
                runner, "applyH2ConditionDetectionTables");

        // Assert
        try (Connection conn = h2.getConnection(); Statement stmt = conn.createStatement()) {
            final String insertRun = "INSERT INTO condition_detection_runs "
                    + "(call_id, patient_id, patient_user_id, model_id, input_kind, state, next_attempt_at) "
                    + "VALUES ('call-1', 1, 10, 'kintsugi-dam-3.1', 'AUDIO', 'READY', CURRENT_TIMESTAMP)";
            stmt.execute(insertRun);
            stmt.execute("INSERT INTO condition_flags (run_id, call_id, patient_id, model_id, "
                    + "condition_name, severity_level, severity_label) "
                    + "VALUES (1, 'call-1', 1, 'kintsugi-dam-3.1', 'DEPRESSION', 0, 'NONE')");
            assertThatThrownBy(() -> stmt.execute(insertRun))
                    .isInstanceOf(SQLException.class)
                    .hasMessageContaining("UQ_CONDITION_DETECTION_RUNS_CALL_MODEL");
        }
    }

    @Test
    void run_abortsWhenRequiredProductionPatchFails() throws Exception {
        final DataSource dataSource = mock(DataSource.class);
        final Connection connection = mock(Connection.class);
        final Connection statementConnection = mock(Connection.class);
        final DatabaseMetaData metadata = mock(DatabaseMetaData.class);
        final DatabaseMetaData statementMetadata = mock(DatabaseMetaData.class);
        final Statement statement = mock(Statement.class);
        final ResultSet resultSet = mock(ResultSet.class);
        when(dataSource.getConnection()).thenReturn(connection);
        when(connection.createStatement()).thenReturn(statement);
        when(connection.getMetaData()).thenReturn(metadata);
        when(statement.getConnection()).thenReturn(statementConnection);
        when(statementConnection.getMetaData()).thenReturn(statementMetadata);
        when(statementMetadata.getDatabaseProductName()).thenReturn("H2");
        when(statement.executeQuery(anyString())).thenReturn(resultSet);
        when(resultSet.next()).thenReturn(true);
        when(resultSet.getBoolean(1)).thenReturn(true);
        when(metadata.getDatabaseProductName()).thenReturn("PostgreSQL");
        doAnswer(invocation -> {
            final String sql = invocation.getArgument(0);
            if (sql.contains("CREATE TABLE IF NOT EXISTS call_sessions")) {
                throw new SQLException("required production DDL unavailable");
            }
            return false;
        }).when(statement).execute(anyString());

        final SchemaPatchLedger patchLedger = mock(SchemaPatchLedger.class);

        assertThatThrownBy(() -> new SchemaPatchRunner(dataSource, patchLedger).run())
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("Required schema patch")
                .hasRootCauseMessage("required production DDL unavailable");
    }

    @Test
    void applyEhrResourceJsonb_convertsInPlacePreservingPayloads() throws Exception {
        // The oid -> jsonb patch must read each large object back and keep the payload, not drop and
        // recreate the column (which would null every existing row until a full Epic re-sync). Guard
        // the SQL so a regression back to the destructive form is caught here.
        final java.nio.file.Path sourcePath = java.nio.file.Path.of(
                "src/main/java/com/careconnect/config/SchemaPatchRunner.java");
        final java.nio.file.Path resolved = java.nio.file.Files.exists(sourcePath)
                ? sourcePath
                : java.nio.file.Path.of(
                "backend/core/src/main/java/com/careconnect/config/SchemaPatchRunner.java");
        final String source = java.nio.file.Files.readString(resolved);
        final String method = source.substring(
                source.indexOf("private void applyEhrResourceJsonbPatch()"),
                source.indexOf("private void applyEhrResourcePatientIdPatch()"));

        // Still gated on the column still being oid, and still lands on jsonb.
        assertThat(method).contains("data_type = 'oid'");
        // Preserving conversion: read the LOB back and cast per row.
        assertThat(method).contains("convert_from(lo_get(r.lo), 'UTF8')::jsonb");
        // Per-row isolation so one unreadable object does not abort the whole table.
        assertThat(method).contains("EXCEPTION WHEN others THEN");
        // Swap the staged column in rather than recreating payload_json empty.
        assertThat(method).contains("ADD COLUMN IF NOT EXISTS payload_json_jsonb jsonb");
        assertThat(method).contains("RENAME COLUMN payload_json_jsonb TO payload_json");
        // Count notice in the boot log.
        assertThat(method).contains("row(s) preserved");
        // The old destructive recreate of the real column must be gone.
        assertThat(method).doesNotContain("ADD COLUMN payload_json jsonb");
    }

    @Test
    void ehrCanonicalPatches_executeTheirDdlOnPostgres() throws Exception {
        // Drive the three Step-6/Q1/Q3 patch methods on a PostgreSQL-reporting datasource so their
        // DDL actually runs (the non-PostgreSQL path just logs and returns). Each helper opens a
        // connection, creates a statement, and executes; all succeed here.
        final DataSource dataSource = mock(DataSource.class);
        final Connection connection = mock(Connection.class);
        final DatabaseMetaData metadata = mock(DatabaseMetaData.class);
        final Statement statement = mock(Statement.class);
        when(dataSource.getConnection()).thenReturn(connection);
        when(connection.getMetaData()).thenReturn(metadata);
        when(connection.createStatement()).thenReturn(statement);
        when(statement.getConnection()).thenReturn(connection);
        when(metadata.getDatabaseProductName()).thenReturn("PostgreSQL");
        when(statement.execute(anyString())).thenReturn(false);

        final SchemaPatchLedger patchLedger = mock(SchemaPatchLedger.class);
        final SchemaPatchRunner runner = new SchemaPatchRunner(dataSource, patchLedger);

        for (final String method : new String[]{
                "applyEhrResourceJsonbPatch",
                "applyEhrResourcePatientIdPatch",
                "applyEhrTypedProjectionUniqueIndexes"}) {
            final java.lang.reflect.Method m =
                    SchemaPatchRunner.class.getDeclaredMethod(method);
            m.setAccessible(true);
            m.invoke(runner); // throws (wrapped) if a required patch could not be applied
        }

        // Every patch statement reached the database (jsonb convert, patient_id add/backfill/index/FK,
        // and the three typed-projection unique indexes).
        verify(statement, org.mockito.Mockito.atLeast(8)).execute(anyString());
    }

    @Test
    void ehrCanonicalPatches_skipOnNonPostgres() throws Exception {
        // The guard path: a non-PostgreSQL datasource logs and returns without touching a statement.
        final DataSource dataSource = mock(DataSource.class);
        final Connection connection = mock(Connection.class);
        final DatabaseMetaData metadata = mock(DatabaseMetaData.class);
        when(dataSource.getConnection()).thenReturn(connection);
        when(connection.getMetaData()).thenReturn(metadata);
        when(metadata.getDatabaseProductName()).thenReturn("H2");

        final SchemaPatchLedger patchLedger = mock(SchemaPatchLedger.class);
        final SchemaPatchRunner runner = new SchemaPatchRunner(dataSource, patchLedger);

        for (final String method : new String[]{
                "applyEhrResourceJsonbPatch",
                "applyEhrResourcePatientIdPatch",
                "applyEhrTypedProjectionUniqueIndexes"}) {
            final java.lang.reflect.Method m =
                    SchemaPatchRunner.class.getDeclaredMethod(method);
            m.setAccessible(true);
            m.invoke(runner);
        }

        org.mockito.Mockito.verify(connection, org.mockito.Mockito.never()).createStatement();
    }
}
