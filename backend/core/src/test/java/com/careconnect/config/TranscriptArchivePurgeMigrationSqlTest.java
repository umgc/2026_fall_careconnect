package com.careconnect.config;

import static org.assertj.core.api.Assertions.assertThat;

import java.nio.charset.StandardCharsets;
import org.junit.jupiter.api.Test;
import org.springframework.core.io.ClassPathResource;

/** Static contract for durable transcript archive purge fencing and deletion work. */
class TranscriptArchivePurgeMigrationSqlTest {

  @Test
  void migrationDefinesPermanentFenceAndLeasedDeletionOutbox() throws Exception {
    final var resource =
        new ClassPathResource(
            "db/migration/V2607191300__harden_transcript_archive_purge.sql");
    final String sql;
    try (var input = resource.getInputStream()) {
      sql = new String(input.readAllBytes(), StandardCharsets.UTF_8);
    }

    assertThat(sql)
        .contains("call_transcript_archive_lifecycle")
        .contains("generation BIGINT NOT NULL DEFAULT 0")
        .contains("purged BOOLEAN NOT NULL DEFAULT FALSE")
        .contains("transcript_archive_deletion_outbox")
        .contains("CONSTRAINT uq_transcript_archive_deletion_key UNIQUE (storage_key)")
        .contains("claimed_until TIMESTAMPTZ")
        .contains("claim_token UUID")
        .contains("ck_transcript_archive_deletion_lease")
        .contains("idx_transcript_archive_deletion_claim");
  }
}
