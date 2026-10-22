package com.careconnect.config;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

import javax.sql.DataSource;
import java.sql.Connection;
import java.sql.DatabaseMetaData;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.atLeastOnce;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * The CC-12 Increment 1 patches V2610131200a…f that {@code SchemaPatchRunner} applies on PostgreSQL
 * (Test Plan §3.23, TC-EMG-041…043; §3.24, TC-EMG-064). The JDBC objects are mocks, so this pins the statements the
 * runner issues; {@code EmergencyPassportSchemaPostgresTest} shows what they do to a real database.
 * <p>
 * Test IDs TC-EMG-041…043 and 064 (Increment 2, the author's) are permanent. Never renumber, never reuse.
 */
class SchemaPatchRunnerEmergencyPassportTest {

    private static final String PROFILE = "emergency_passport_profile";
    private static final String VISIBILITY = "emergency_passport_field_visibility";
    private static final String TOKEN = "emergency_passport_token";

    private final DataSource dataSource = mock(DataSource.class);
    private final Connection connection = mock(Connection.class);
    private final DatabaseMetaData metadata = mock(DatabaseMetaData.class);
    private final Statement statement = mock(Statement.class);

    private SchemaPatchRunner runnerOn(final String databaseProductName) throws SQLException {
        when(dataSource.getConnection()).thenReturn(connection);
        when(connection.getMetaData()).thenReturn(metadata);
        when(connection.createStatement()).thenReturn(statement);
        when(statement.getConnection()).thenReturn(connection);
        when(metadata.getDatabaseProductName()).thenReturn(databaseProductName);
        return new SchemaPatchRunner(dataSource, mock(SchemaPatchLedger.class));
    }

    /** Every statement executed, without the per-connection lock and statement timeouts. */
    private List<String> patchStatements() throws SQLException {
        final ArgumentCaptor<String> sql = ArgumentCaptor.forClass(String.class);
        verify(statement, atLeastOnce()).execute(sql.capture());
        return sql.getAllValues().stream().filter(s -> !s.startsWith("SET ")).toList();
    }

    @Test
    @DisplayName("TC-EMG-041: on PostgreSQL the runner issues V2610131200a…f in order: unique indexes, "
            + "cascading foreign keys to patient, the is_public default and four TIMESTAMPTZ conversions")
    void postgresIssuesEveryPassportPatchInOrder() throws Exception {
        runnerOn("PostgreSQL").applyEmergencyPassportPatches();

        // Increment 1's nine come first; Increment 2's token patches follow (checked separately below).
        final List<String> sql = patchStatements().subList(0, 9);

        assertThat(sql.get(0)).isEqualTo("CREATE UNIQUE INDEX IF NOT EXISTS uq_emergency_passport_profile_patient "
                + "ON " + PROFILE + " (patient_id)");
        assertThat(sql.get(1)).isEqualTo("CREATE UNIQUE INDEX IF NOT EXISTS uq_emergency_passport_visibility_patient_field "
                + "ON " + VISIBILITY + " (patient_id, field_key)");

        assertForeignKey(sql.get(2), "fk_emergency_passport_profile_patient", PROFILE);
        assertForeignKey(sql.get(3), "fk_emergency_passport_visibility_patient", VISIBILITY);

        assertThat(sql.get(4)).isEqualTo("ALTER TABLE " + VISIBILITY + " ALTER COLUMN is_public SET DEFAULT FALSE");

        int i = 5;
        for (final String table : new String[]{PROFILE, VISIBILITY}) {
            for (final String column : new String[]{"created_at", "updated_at"}) {
                assertThat(sql.get(i++))
                        .as("TIMESTAMPTZ patch for %s.%s", table, column)
                        .contains("table_name = '" + table + "'")
                        .contains("column_name = '" + column + "'")
                        .contains("data_type = 'timestamp without time zone'")
                        .contains("ALTER TABLE " + table + " ALTER COLUMN " + column
                                + " TYPE TIMESTAMPTZ USING " + column + " AT TIME ZONE 'UTC'");
            }
        }
    }

    @Test
    @DisplayName("TC-EMG-064: on PostgreSQL the runner then issues V2610131300a…d for the token table: lookup and one-active "
            + "unique indexes, a cascading foreign key to patient and two TIMESTAMPTZ conversions")
    void postgresIssuesEveryTokenPatchAfterIncrementOne() throws Exception {
        runnerOn("PostgreSQL").applyEmergencyPassportPatches();

        final List<String> sql = patchStatements();
        assertThat(sql).hasSize(14);

        assertThat(sql.get(9)).isEqualTo("CREATE UNIQUE INDEX IF NOT EXISTS uq_emergency_passport_token_lookup "
                + "ON " + TOKEN + " (token_lookup)");
        assertThat(sql.get(10)).isEqualTo("CREATE UNIQUE INDEX IF NOT EXISTS uq_emergency_passport_token_one_active "
                + "ON " + TOKEN + " (patient_id) WHERE status = 'ACTIVE'");
        assertForeignKey(sql.get(11), "fk_emergency_passport_token_patient", TOKEN);

        int i = 12;
        for (final String column : new String[]{"created_at", "updated_at"}) {
            assertThat(sql.get(i++))
                    .as("TIMESTAMPTZ patch for %s.%s", TOKEN, column)
                    .contains("table_name = '" + TOKEN + "'")
                    .contains("column_name = '" + column + "'")
                    .contains("ALTER TABLE " + TOKEN + " ALTER COLUMN " + column
                            + " TYPE TIMESTAMPTZ USING " + column + " AT TIME ZONE 'UTC'");
        }
    }

    private static void assertForeignKey(final String sql, final String constraint, final String table) {
        assertThat(sql)
                .as("foreign key %s", constraint)
                .contains("c.conrelid = '" + table + "'::regclass")
                .contains("c.confrelid = 'patient'::regclass")
                // The guard only counts an existing key as present if it already cascades.
                .contains("c.confdeltype = 'c'")
                .contains("ALTER TABLE " + table + " ADD CONSTRAINT " + constraint
                        + " FOREIGN KEY (patient_id) REFERENCES patient (id) ON DELETE CASCADE;");
    }

    @Test
    @DisplayName("TC-EMG-042: on H2 the runner issues no passport patch")
    void h2IssuesNothing() throws Exception {
        runnerOn("H2").applyEmergencyPassportPatches();

        verify(statement, never()).execute(anyString());
    }

    @Test
    @DisplayName("TC-EMG-043: a passport patch that fails stops the boot and names the patch")
    void failingPatchStopsTheBoot() throws Exception {
        final SchemaPatchRunner runner = runnerOn("PostgreSQL");
        doAnswer(invocation -> {
            final String sql = invocation.getArgument(0);
            if (sql.contains("ADD CONSTRAINT fk_emergency_passport_profile_patient")) {
                throw new SQLException("insert or update on table violates foreign key constraint");
            }
            return false;
        }).when(statement).execute(anyString());

        assertThatThrownBy(runner::applyEmergencyPassportPatches)
                .isInstanceOf(IllegalStateException.class)
                .hasMessage("Required schema patch could not be applied: "
                        + "V2610131200c - FK emergency_passport_profile.patient_id -> patient.id")
                .hasRootCauseMessage("insert or update on table violates foreign key constraint");
    }
}
