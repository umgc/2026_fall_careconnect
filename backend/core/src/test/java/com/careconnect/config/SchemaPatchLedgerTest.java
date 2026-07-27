package com.careconnect.config;

import org.h2.jdbcx.JdbcDataSource;
import org.junit.jupiter.api.Test;

import javax.sql.DataSource;
import java.sql.Connection;
import java.sql.ResultSet;
import java.sql.Statement;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class SchemaPatchLedgerTest {

    @Test
    void apply_recordsFirstRunAndSkipsMatchingSecondRun() throws Exception {
        final DataSource dataSource = dataSource("first_second");
        final SchemaPatchLedger ledger = new SchemaPatchLedger(dataSource, "test-version");
        final SchemaPatchLedger.Patch patch = new SchemaPatchLedger.Patch(
                "test-success", "schema-patches/ledger_success.sql");

        ledger.initialize();
        ledger.apply(patch);
        ledger.apply(patch);

        assertThat(count(dataSource, "SELECT COUNT(*) FROM ledger_probe")).isEqualTo(1);
        assertThat(count(dataSource,
                "SELECT COUNT(*) FROM careconnect_schema_patch_history "
                        + "WHERE patch_id = 'test-success' "
                        + "AND LENGTH(sha256_checksum) = 64 "
                        + "AND application_version = 'test-version' "
                        + "AND applied_at IS NOT NULL "
                        + "AND execution_ms >= 0"))
                .isEqualTo(1);
    }

    @Test
    void apply_failsClosedOnChecksumMismatch() throws Exception {
        final DataSource dataSource = dataSource("checksum");
        final SchemaPatchLedger ledger = new SchemaPatchLedger(dataSource, "test-version");
        final SchemaPatchLedger.Patch patch = new SchemaPatchLedger.Patch(
                "test-checksum", "schema-patches/ledger_success.sql");
        ledger.initialize();
        ledger.apply(patch);
        execute(dataSource, "UPDATE careconnect_schema_patch_history "
                + "SET sha256_checksum = REPEAT('0', 64) "
                + "WHERE patch_id = 'test-checksum'");

        assertThatThrownBy(() -> ledger.apply(patch))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("checksum drift")
                .hasMessageContaining("test-checksum");
    }

    @Test
    void apply_doesNotRecordFailedPatch() throws Exception {
        final DataSource dataSource = dataSource("failure");
        final SchemaPatchLedger ledger = new SchemaPatchLedger(dataSource, "test-version");
        ledger.initialize();

        assertThatThrownBy(() -> ledger.apply(new SchemaPatchLedger.Patch(
                "test-failure", "schema-patches/ledger_failure.sql")))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("test-failure");
        assertThat(count(dataSource,
                "SELECT COUNT(*) FROM careconnect_schema_patch_history "
                        + "WHERE patch_id = 'test-failure'"))
                .isZero();
    }

    @Test
    void apply_upgradesLaggingSchemaOnce() throws Exception {
        final DataSource dataSource = dataSource("lagging");
        execute(dataSource, "CREATE TABLE lagging_schema (id BIGINT PRIMARY KEY)");
        execute(dataSource, "INSERT INTO lagging_schema (id) VALUES (1)");
        final SchemaPatchLedger ledger = new SchemaPatchLedger(dataSource, "test-version");
        ledger.initialize();

        ledger.apply(new SchemaPatchLedger.Patch(
                "test-lagging", "schema-patches/ledger_lagging.sql"));

        assertThat(count(dataSource,
                "SELECT COUNT(*) FROM lagging_schema WHERE patient_id = 42"))
                .isEqualTo(1);
    }

    private static DataSource dataSource(final String name) {
        final JdbcDataSource dataSource = new JdbcDataSource();
        dataSource.setURL("jdbc:h2:mem:" + name + ";DB_CLOSE_DELAY=-1");
        return dataSource;
    }

    private static long count(final DataSource dataSource, final String sql) throws Exception {
        try (Connection connection = dataSource.getConnection();
             Statement statement = connection.createStatement();
             ResultSet result = statement.executeQuery(sql)) {
            result.next();
            return result.getLong(1);
        }
    }

    private static void execute(final DataSource dataSource, final String sql) throws Exception {
        try (Connection connection = dataSource.getConnection();
             Statement statement = connection.createStatement()) {
            statement.execute(sql);
        }
    }
}
