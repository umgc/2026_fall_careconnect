package com.careconnect.config;

import java.nio.charset.StandardCharsets;

import org.junit.jupiter.api.Test;
import org.springframework.core.io.ClassPathResource;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Static contract for the pending-link crosswalk schema, and a guard that the canonical EHR
 * migration it amends stays as develop applied it (#287 review: editing an applied migration
 * breaks Flyway validate).
 */
class EhrCrosswalkPendingLinkMigrationSqlTest {

    private static String read(final String path) throws Exception {
        try (var input = new ClassPathResource(path).getInputStream()) {
            return new String(input.readAllBytes(), StandardCharsets.UTF_8);
        }
    }

    @Test
    void pendingLinkMigrationRelaxesExternalIdAndAddsTokenColumns() throws Exception {
        final String sql = read("db/migration/V2610041200__ehr_crosswalk_pending_link.sql");

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
    void canonicalEhrMigrationIsUnchanged() throws Exception {
        final String sql = read("db/migration/V2609261500__create_ehr_canonical_schema.sql");

        assertThat(sql)
                .contains("external_patient_id VARCHAR(255) NOT NULL")
                .doesNotContain("link_token")
                .doesNotContain("refresh_token");
    }
}
