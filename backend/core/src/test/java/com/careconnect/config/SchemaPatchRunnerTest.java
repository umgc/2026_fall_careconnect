package com.careconnect.config;

import org.junit.jupiter.api.Test;

import javax.sql.DataSource;
import java.sql.Connection;
import java.sql.DatabaseMetaData;
import java.sql.SQLException;
import java.sql.Statement;

import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class SchemaPatchRunnerTest {

    @Test
    void run_abortsWhenRequiredRetrievalPatchFails() throws Exception {
        final DataSource dataSource = mock(DataSource.class);
        final Connection connection = mock(Connection.class);
        final DatabaseMetaData metadata = mock(DatabaseMetaData.class);
        final Statement statement = mock(Statement.class);
        when(dataSource.getConnection()).thenReturn(connection);
        when(connection.createStatement()).thenReturn(statement);
        when(connection.getMetaData()).thenReturn(metadata);
        when(metadata.getDatabaseProductName()).thenReturn("PostgreSQL");
        doAnswer(invocation -> {
            final String sql = invocation.getArgument(0);
            if (sql.contains("CREATE EXTENSION IF NOT EXISTS vector")) {
                throw new SQLException("pgvector unavailable");
            }
            return false;
        }).when(statement).execute(anyString());

        assertThatThrownBy(() -> new SchemaPatchRunner(dataSource).run())
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("Required schema patch")
                .hasRootCauseMessage("pgvector unavailable");
    }
}
