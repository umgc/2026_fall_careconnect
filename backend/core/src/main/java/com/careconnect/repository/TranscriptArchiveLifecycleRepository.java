package com.careconnect.repository;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;
import org.springframework.dao.EmptyResultDataAccessException;
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
    final Integer existing =
        jdbcTemplate.query(
            """
            SELECT COUNT(*) FROM call_transcript_archive_lifecycle WHERE call_id = ?
            """,
            (resultSet) -> resultSet.next() ? resultSet.getInt(1) : 0,
            callId);
    if (existing != null && existing > 0) {
      return;
    }
    try {
      jdbcTemplate.update(
          """
          INSERT INTO call_transcript_archive_lifecycle
            (call_id, generation, purged, created_at, updated_at)
          VALUES (?, 0, FALSE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
          """,
          callId);
    } catch (org.springframework.dao.DataIntegrityViolationException ignored) {
      // Concurrent creator won the insert race.
    }
  }

  /** Returns the current durable lifecycle state. */
  public ArchiveLifecycle find(final String callId) {
    try {
      return jdbcTemplate.queryForObject(
          """
          SELECT generation, purged
          FROM call_transcript_archive_lifecycle
          WHERE call_id = ?
          """,
          (result, rowNumber) ->
              new ArchiveLifecycle(result.getLong("generation"), result.getBoolean("purged")),
          callId);
    } catch (EmptyResultDataAccessException exception) {
      ensureActive(callId);
      return new ArchiveLifecycle(0L, false);
    }
  }

  /** Permanently fences a call from archive finalization and advances its generation. */
  public void markPurged(final String callId) {
    ensureActive(callId);
    jdbcTemplate.update(
        """
        UPDATE call_transcript_archive_lifecycle
        SET generation = generation + 1, purged = TRUE, updated_at = CURRENT_TIMESTAMP
        WHERE call_id = ?
        """,
        callId);
  }

  /** Adds an idempotent, durable request to delete an object after database commit. */
  public void enqueueDeletion(final String storageKey) {
    final Integer existing =
        jdbcTemplate.query(
            """
            SELECT COUNT(*) FROM transcript_archive_deletion_outbox WHERE storage_key = ?
            """,
            (resultSet) -> resultSet.next() ? resultSet.getInt(1) : 0,
            storageKey);
    if (existing != null && existing > 0) {
      jdbcTemplate.update(
          """
          UPDATE transcript_archive_deletion_outbox
          SET next_attempt_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP
          WHERE storage_key = ?
          """,
          storageKey);
      return;
    }
    try {
      jdbcTemplate.update(
          """
          INSERT INTO transcript_archive_deletion_outbox
            (storage_key, attempts, next_attempt_at, created_at, updated_at)
          VALUES (?, 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
          """,
          storageKey);
    } catch (org.springframework.dao.DataIntegrityViolationException ignored) {
      jdbcTemplate.update(
          """
          UPDATE transcript_archive_deletion_outbox
          SET next_attempt_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP
          WHERE storage_key = ?
          """,
          storageKey);
    }
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
          WHERE next_attempt_at <= CURRENT_TIMESTAMP
            AND dead_lettered_at IS NULL
            AND (claimed_until IS NULL OR claimed_until <= CURRENT_TIMESTAMP)
          ORDER BY next_attempt_at, id
          FOR UPDATE SKIP LOCKED
          LIMIT ?
        )
        UPDATE transcript_archive_deletion_outbox item
        SET claimed_until = ?, claim_token = ?, updated_at = CURRENT_TIMESTAMP
        FROM candidates
        WHERE item.id = candidates.id
        RETURNING item.id, item.storage_key, item.attempts, item.claim_token
        """,
        (result, rowNumber) ->
            new DeletionClaim(
                result.getLong("id"),
                result.getString("storage_key"),
                result.getInt("attempts"),
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
            last_error = ?, updated_at = CURRENT_TIMESTAMP
        WHERE id = ? AND claim_token = ?
        """,
        retryAt,
        error,
        claim.id(),
        claim.claimToken());
  }

  /** Permanently parks a terminal failure or an item that exhausted its retry budget. */
  public int deadLetterDeletion(final DeletionClaim claim, final String error) {
    return jdbcTemplate.update(
        """
        UPDATE transcript_archive_deletion_outbox
        SET attempts = CASE WHEN attempts < 2147483647 THEN attempts + 1 ELSE attempts END,
            dead_lettered_at = CURRENT_TIMESTAMP, terminal_error = ?,
            claimed_until = NULL, claim_token = NULL, updated_at = CURRENT_TIMESTAMP
        WHERE id = ? AND claim_token = ?
        """,
        error,
        claim.id(),
        claim.claimToken());
  }

  /** Per-call generation and terminal purge state. */
  public record ArchiveLifecycle(long generation, boolean purged) {}

  /** Leased object-deletion work item. */
  public record DeletionClaim(long id, String storageKey, int attempts, UUID claimToken) {
    /** Compatibility constructor for existing callers and tests. */
    public DeletionClaim(final long id, final String storageKey, final UUID claimToken) {
      this(id, storageKey, 0, claimToken);
    }
  }
}
