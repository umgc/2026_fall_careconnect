package com.careconnect.repository;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.annotation.Transactional;

/** Durable purge fencing and object-deletion outbox access for transcript archives. */
@Repository
public class TranscriptArchiveLifecycleRepository {

  private final JdbcTemplate jdbcTemplate;

  public TranscriptArchiveLifecycleRepository(final JdbcTemplate jdbcTemplate) {
    this.jdbcTemplate = jdbcTemplate;
  }

  /** Creates the initial active lifecycle row when this call has not been seen before. */
  public void ensureActive(final String callId) {
    jdbcTemplate.update(
        """
        INSERT INTO call_transcript_archive_lifecycle (call_id)
        VALUES (?)
        ON CONFLICT (call_id) DO NOTHING
        """,
        callId);
  }

  /** Returns the current durable lifecycle state. */
  public ArchiveLifecycle find(final String callId) {
    return jdbcTemplate.queryForObject(
        """
        SELECT generation, purged
        FROM call_transcript_archive_lifecycle
        WHERE call_id = ?
        """,
        (result, rowNumber) ->
            new ArchiveLifecycle(result.getLong("generation"), result.getBoolean("purged")),
        callId);
  }

  /** Permanently fences a call from archive finalization and advances its generation. */
  public void markPurged(final String callId) {
    ensureActive(callId);
    jdbcTemplate.update(
        """
        UPDATE call_transcript_archive_lifecycle
        SET generation = generation + 1, purged = TRUE, updated_at = now()
        WHERE call_id = ?
        """,
        callId);
  }

  /** Adds an idempotent, durable request to delete an object after database commit. */
  public void enqueueDeletion(final String storageKey) {
    jdbcTemplate.update(
        """
        INSERT INTO transcript_archive_deletion_outbox (storage_key)
        VALUES (?)
        ON CONFLICT (storage_key) DO UPDATE
        SET next_attempt_at = LEAST(
              transcript_archive_deletion_outbox.next_attempt_at, now()),
            updated_at = now()
        """,
        storageKey);
  }

  /** Claims a bounded batch using leases so multiple application nodes may safely process it. */
  @Transactional
  public List<DeletionClaim> claimDeletions(
      final int limit, final OffsetDateTime claimedUntil, final UUID claimToken) {
    return jdbcTemplate.query(
        """
        WITH candidates AS (
          SELECT id
          FROM transcript_archive_deletion_outbox
          WHERE next_attempt_at <= now()
            AND (claimed_until IS NULL OR claimed_until <= now())
          ORDER BY next_attempt_at, id
          FOR UPDATE SKIP LOCKED
          LIMIT ?
        )
        UPDATE transcript_archive_deletion_outbox item
        SET claimed_until = ?, claim_token = ?, updated_at = now()
        FROM candidates
        WHERE item.id = candidates.id
        RETURNING item.id, item.storage_key, item.claim_token
        """,
        (result, rowNumber) ->
            new DeletionClaim(
                result.getLong("id"),
                result.getString("storage_key"),
                result.getObject("claim_token", UUID.class)),
        limit,
        claimedUntil,
        claimToken);
  }

  /** Completes a deletion only when the caller still owns the lease. */
  public int completeDeletion(final DeletionClaim claim) {
    return jdbcTemplate.update(
        """
        DELETE FROM transcript_archive_deletion_outbox
        WHERE id = ? AND claim_token = ?
        """,
        claim.id(),
        claim.claimToken());
  }

  /** Releases a failed deletion with bounded retry metadata. */
  public int retryDeletion(
      final DeletionClaim claim, final OffsetDateTime retryAt, final String error) {
    return jdbcTemplate.update(
        """
        UPDATE transcript_archive_deletion_outbox
        SET attempts = CASE WHEN attempts < 2147483647 THEN attempts + 1 ELSE attempts END,
            next_attempt_at = ?, claimed_until = NULL, claim_token = NULL,
            last_error = ?, updated_at = now()
        WHERE id = ? AND claim_token = ?
        """,
        retryAt,
        error,
        claim.id(),
        claim.claimToken());
  }

  /** Per-call generation and terminal purge state. */
  public record ArchiveLifecycle(long generation, boolean purged) {}

  /** Leased object-deletion work item. */
  public record DeletionClaim(long id, String storageKey, UUID claimToken) {}
}
