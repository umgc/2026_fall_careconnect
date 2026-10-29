package com.careconnect.config;

import java.nio.charset.StandardCharsets;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.core.io.ClassPathResource;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Static contract for the share-card columns on {@code messages}: nullable, so Hibernate
 * ddl-auto=update can add them in production, and safe to rerun.
 */
class MessageShareCardMigrationSqlTest {

    @Test
    @DisplayName("TC-MSG-SHR-014 the share-card migration adds share_kind and share_patient_id as nullable columns, safe to rerun")
    void addsNullableShareColumnsIdempotently() throws Exception {
        final var resource = new ClassPathResource("db/migration/V2610241200__add_share_card_to_messages.sql");
        final String sql;
        try (var input = resource.getInputStream()) {
            sql = new String(input.readAllBytes(), StandardCharsets.UTF_8);
        }

        assertThat(sql)
                .contains("ALTER TABLE messages")
                .contains("ADD COLUMN IF NOT EXISTS share_kind       VARCHAR(32)")
                .contains("ADD COLUMN IF NOT EXISTS share_patient_id BIGINT")
                .doesNotContain("NOT NULL");
    }
}
