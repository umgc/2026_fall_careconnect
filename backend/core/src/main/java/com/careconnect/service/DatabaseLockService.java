package com.careconnect.service;

import javax.sql.DataSource;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

/**
 * Database-native coordination primitives with PostgreSQL-only advisory locks.
 */
@Service
public class DatabaseLockService {

    private final JdbcTemplate jdbcTemplate;
    private final boolean postgres;

    public DatabaseLockService(final DataSource dataSource, final JdbcTemplate jdbcTemplate) {
        this.jdbcTemplate = jdbcTemplate;
        try (var connection = dataSource.getConnection()) {
            this.postgres = connection.getMetaData()
                    .getDatabaseProductName()
                    .toLowerCase(java.util.Locale.ROOT)
                    .contains("postgresql");
        } catch (Exception exception) {
            throw new IllegalStateException("Unable to identify database for advisory locks", exception);
        }
    }

    /**
     * Serializes archive capture/deletion for one call on PostgreSQL; no-op elsewhere.
     */
    public void acquireCallArchiveLock(final String callId) {
        if (!postgres || callId == null || callId.isBlank()) {
            return;
        }
        jdbcTemplate.query(
                "SELECT pg_advisory_xact_lock(hashtextextended(?, 0))",
                (resultSet, rowNumber) -> 0,
                callId);
    }
}
