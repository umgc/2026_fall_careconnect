package com.careconnect.config;

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
import static org.mockito.Mockito.when;

class SchemaPatchRunnerTest {

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

        assertThatThrownBy(() -> new SchemaPatchRunner(dataSource).run())
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("Required schema patch")
                .hasRootCauseMessage("required production DDL unavailable");
    }
}
