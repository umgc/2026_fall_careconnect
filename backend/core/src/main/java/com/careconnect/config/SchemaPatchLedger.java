package com.careconnect.config;

import lombok.extern.slf4j.Slf4j;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.datasource.init.ScriptUtils;

import javax.sql.DataSource;
import java.io.IOException;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.Statement;
import java.util.HexFormat;

/** Executes immutable SQL resources once and records their checksums. */
@Slf4j
final class SchemaPatchLedger {

    private static final String CREATE_HISTORY = """
            CREATE TABLE IF NOT EXISTS careconnect_schema_patch_history (
                patch_id VARCHAR(160) PRIMARY KEY,
                sha256_checksum VARCHAR(64) NOT NULL,
                applied_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
                execution_ms BIGINT NOT NULL,
                application_version VARCHAR(120) NOT NULL
            )
            """;

    private final DataSource dataSource;
    private final String applicationVersion;

    SchemaPatchLedger(final DataSource dataSource, final String applicationVersion) {
        this.dataSource = dataSource;
        this.applicationVersion = applicationVersion;
    }

    void initialize() {
        try (Connection connection = dataSource.getConnection();
             Statement statement = connection.createStatement()) {
            connection.setAutoCommit(true);
            statement.execute(CREATE_HISTORY);
        } catch (Exception exception) {
            throw new IllegalStateException("Could not initialize schema patch history", exception);
        }
    }

    void apply(final Patch patch) {
        final ClassPathResource resource = new ClassPathResource(patch.resourcePath());
        final String checksum = checksum(resource);
        try (Connection connection = dataSource.getConnection()) {
            connection.setAutoCommit(false);
            try {
                final String recordedChecksum = recordedChecksum(connection, patch.id());
                if (recordedChecksum != null) {
                    if (!recordedChecksum.equals(checksum)) {
                        throw new IllegalStateException(
                                "Schema patch checksum drift detected for " + patch.id());
                    }
                    connection.rollback();
                    log.debug("Schema patch already recorded: {}", patch.id());
                    return;
                }

                final long started = System.nanoTime();
                try (Statement statement = connection.createStatement()) {
                    SchemaPatchRunner.configureDdlTimeouts(statement);
                }
                ScriptUtils.executeSqlScript(connection, resource);
                final long executionMs = (System.nanoTime() - started) / 1_000_000L;
                record(connection, patch.id(), checksum, executionMs);
                connection.commit();
                log.info("Schema patch applied and recorded: {}", patch.id());
            } catch (Exception exception) {
                rollback(connection, exception);
                throw exception;
            }
        } catch (Exception exception) {
            if (exception instanceof IllegalStateException illegalStateException) {
                throw illegalStateException;
            }
            throw new IllegalStateException(
                    "Required schema patch could not be applied: " + patch.id(), exception);
        }
    }

    private static String recordedChecksum(
            final Connection connection,
            final String patchId) throws Exception {
        try (PreparedStatement statement = connection.prepareStatement(
                "SELECT sha256_checksum FROM careconnect_schema_patch_history "
                        + "WHERE patch_id = ?")) {
            statement.setString(1, patchId);
            try (ResultSet result = statement.executeQuery()) {
                return result.next() ? result.getString(1) : null;
            }
        }
    }

    private void record(
            final Connection connection,
            final String patchId,
            final String checksum,
            final long executionMs) throws Exception {
        try (PreparedStatement statement = connection.prepareStatement(
                "INSERT INTO careconnect_schema_patch_history "
                        + "(patch_id, sha256_checksum, execution_ms, application_version) "
                        + "VALUES (?, ?, ?, ?)")) {
            statement.setString(1, patchId);
            statement.setString(2, checksum);
            statement.setLong(3, executionMs);
            statement.setString(4, applicationVersion);
            statement.executeUpdate();
        }
    }

    private static String checksum(final ClassPathResource resource) {
        try {
            final byte[] bytes = resource.getInputStream().readAllBytes();
            return HexFormat.of().formatHex(
                    MessageDigest.getInstance("SHA-256").digest(bytes));
        } catch (IOException | NoSuchAlgorithmException exception) {
            throw new IllegalStateException(
                    "Could not checksum schema patch " + resource.getPath(), exception);
        }
    }

    private static void rollback(
            final Connection connection,
            final Exception original) {
        try {
            connection.rollback();
        } catch (Exception rollbackFailure) {
            original.addSuppressed(rollbackFailure);
        }
    }

    record Patch(String id, String resourcePath) {
        Patch {
            if (id == null || id.isBlank() || resourcePath == null || resourcePath.isBlank()) {
                throw new IllegalArgumentException("Schema patch id and resource are required");
            }
        }
    }
}
