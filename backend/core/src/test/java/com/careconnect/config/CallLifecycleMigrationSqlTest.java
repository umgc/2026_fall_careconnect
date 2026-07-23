package com.careconnect.config;

import java.nio.charset.StandardCharsets;
import org.junit.jupiter.api.Test;
import org.springframework.core.io.ClassPathResource;

import static org.assertj.core.api.Assertions.assertThat;

/** Static contract for the recoverable call-termination production schema. */
class CallLifecycleMigrationSqlTest {

    @Test
    void recoverableTerminationMigrationDefinesFencingLeaseAndRetrySchema()
            throws Exception {
        final var resource = new ClassPathResource(
                "db/migration/V2607190200__add_recoverable_call_termination.sql");
        final String sql;
        try (var input = resource.getInputStream()) {
            sql = new String(input.readAllBytes(), StandardCharsets.UTF_8);
        }

        assertThat(sql)
                .contains("termination_claim_id UUID")
                .contains("termination_claimed_by_user_id BIGINT")
                .contains("termination_lease_until TIMESTAMP")
                .contains("termination_attempt_count INTEGER NOT NULL DEFAULT 0")
                .contains("termination_next_retry_at TIMESTAMP")
                .contains("termination_notify_user_ids TEXT")
                .doesNotContain("DO $$")
                .contains("DROP CONSTRAINT IF EXISTS fk_call_sessions_termination_claimed_by")
                .contains("ADD CONSTRAINT fk_call_sessions_termination_claimed_by")
                .contains("FOREIGN KEY (termination_claimed_by_user_id) REFERENCES users(id)")
                .contains("DROP CONSTRAINT IF EXISTS ck_call_sessions_termination_attempt_count")
                .contains("CHECK (termination_attempt_count >= 0)")
                .contains("idx_call_sessions_termination_retry")
                .contains("WHERE status = 'TERMINATING'");
    }
}
