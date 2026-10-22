package com.careconnect.config;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.zip.CRC32;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.core.io.ClassPathResource;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Static contract for the pending-link crosswalk schema, and a guard that the canonical EHR
 * migration it amends stays as develop applied it (#287 review: editing an applied migration
 * breaks Flyway validate).
 *
 * <p>Test IDs TC-EHR-SCH-022..023 are permanent. Never renumber, never reuse. Both are the PR #296
 * author's; 023 was widened by the Testing Lead to compare Flyway's checksum.
 */
class EhrCrosswalkPendingLinkMigrationSqlTest {

    /**
     * The checksum Flyway 10.20.1 records in flyway_schema_history for V2609261500 as develop
     * carried it from #216 (2026-10-02) until #287 merged, and as this branch restores it.
     */
    private static final int V2609261500_FLYWAY_CHECKSUM = -1882677464;

    private static final String CANONICAL = "db/migration/V2609261500__create_ehr_canonical_schema.sql";

    private static String read(final String path) throws Exception {
        try (var input = new ClassPathResource(path).getInputStream()) {
            return new String(input.readAllBytes(), StandardCharsets.UTF_8);
        }
    }

    /** The statements only: a line comment, or a statement commented out, is not schema. */
    private static String statements(final String path) throws Exception {
        return read(path).replaceAll("(?m)--.*$", "");
    }

    /**
     * Flyway's checksum for a SQL migration: CRC32 over each line's UTF-8 bytes, without line
     * breaks or a leading BOM. A CRLF checkout gives the same value as an LF one.
     */
    private static int flywayChecksum(final String path) throws Exception {
        final CRC32 crc32 = new CRC32();
        try (var reader = new BufferedReader(new InputStreamReader(
                new ClassPathResource(path).getInputStream(), StandardCharsets.UTF_8))) {
            String line = reader.readLine();
            if (line != null && line.startsWith("﻿")) {
                line = line.substring(1);
            }
            for (; line != null; line = reader.readLine()) {
                crc32.update(line.getBytes(StandardCharsets.UTF_8));
            }
        }
        return (int) crc32.getValue();
    }

    @Test
    @DisplayName("TC-EHR-SCH-022: the pending-link migration relaxes external_patient_id and adds the token and link columns")
    void pendingLinkMigrationRelaxesExternalIdAndAddsTokenColumns() throws Exception {
        final String sql = statements("db/migration/V2610041200__ehr_crosswalk_pending_link.sql");

        assertThat(sql)
                .contains("ALTER COLUMN external_patient_id DROP NOT NULL")
                .contains("ADD COLUMN IF NOT EXISTS token ")
                .contains("ADD COLUMN IF NOT EXISTS refresh_token ")
                .contains("ADD COLUMN IF NOT EXISTS token_expires_at ")
                .contains("ADD COLUMN IF NOT EXISTS last_logged_in ")
                .contains("ADD COLUMN IF NOT EXISTS last_refreshed ")
                .contains("ADD COLUMN IF NOT EXISTS link_token ")
                .contains("ADD COLUMN IF NOT EXISTS link_token_expires_at ")
                .contains("DROP CONSTRAINT IF EXISTS uq_ehr_crosswalk_link_token")
                .contains("ADD CONSTRAINT uq_ehr_crosswalk_link_token UNIQUE (link_token)")
                .doesNotContain("DO $$");
    }

    @Test
    @DisplayName("TC-EHR-SCH-023: the canonical EHR migration keeps the text and Flyway checksum develop applied")
    void canonicalEhrMigrationIsUnchanged() throws Exception {
        final String sql = statements(CANONICAL);

        assertThat(sql)
                .contains("external_patient_id VARCHAR(255) NOT NULL")
                .doesNotContain("link_token")
                .doesNotContain("refresh_token");
        assertThat(flywayChecksum(CANONICAL))
                .as("Flyway checksum of %s; any edit, even to a comment, fails flyway validate", CANONICAL)
                .isEqualTo(V2609261500_FLYWAY_CHECKSUM);
    }
}
