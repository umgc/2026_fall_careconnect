package com.careconnect.repository.indexing;

import com.careconnect.model.indexing.IndexingOutboxRow;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.List;

/**
 * Spring Data repository for the transactional outbox table
 * {@code indexing_outbox}.
 *
 * <p>Two consumer classes on this repository:
 * <ul>
 *   <li><b>Emitters</b> (Fon's summary and transcript persistence code)
 *       use {@link #save} in the same {@code @Transactional} method as
 *       the source record insert. No other repository method is needed
 *       by emitters.</li>
 *   <li><b>Poller</b> (Ravi's backlog 3.4) uses
 *       {@link #findUnprocessedForPolling} to fetch the oldest
 *       unprocessed rows in insertion order, {@link #save} to stamp
 *       {@code processedAt} after successful publish, and
 *       {@link #countUnprocessed} for monitoring / backlog metrics.</li>
 * </ul>
 *
 * <p>Both count/find methods rely on the partial index
 * {@code idx_indexing_outbox_unprocessed WHERE processed_at IS NULL}
 * so the working set stays small even at large row counts.
 */
@Repository
public interface IndexingOutboxRepository extends JpaRepository<IndexingOutboxRow, Long> {

    /**
     * Fetch a page of unprocessed outbox rows in insertion order
     * (oldest first). Intended for the poller (Ravi's backlog 3.4).
     * Wrap the call in a {@code @Transactional} boundary and stamp
     * {@code processedAt} on the returned rows after a successful SNS
     * publish.
     *
     * @param pageable batch size and optional sort override (default
     *                 order is {@code id ASC} which matches insertion
     *                 order for BIGSERIAL PKs)
     * @return unprocessed rows in insertion order, up to the page size
     */
    @Query("SELECT r FROM IndexingOutboxRow r "
            + "WHERE r.processedAt IS NULL "
            + "ORDER BY r.id ASC")
    List<IndexingOutboxRow> findUnprocessedForPolling(Pageable pageable);

    /**
     * Selects a batch of claimable outbox rows using {@code FOR UPDATE SKIP LOCKED}.
     * Callers must stamp {@code claimed_at} in the <em>same</em> short transaction
     * before commit so the lease survives after the lock is released (multi-ECS safe).
     * Rows with a non-expired {@code claimed_at} are skipped using
     * {@code make_interval(mins => :leaseMinutes)} so integer lease params bind safely
     * (avoids {@code integer || unknown}). {@code make_interval} requires PostgreSQL 9.6+;
     * CareConnect RDS targets PostgreSQL 15+ for pgvector. Soft-lease refreshes set
     * {@code claimed_at = now()} so reclaim waits a full lease window — not clearing
     * the column (which would reclaim every poll). Future {@code claimed_at} (no-burn parks)
     * remain unclaimable until that timestamp ages past the lease window.
     * Rows that have already reached {@code maxAttempts} are still selected so they
     * can be dead-lettered.
     *
     * @param limit         maximum rows to claim
     * @param leaseMinutes  rows claimed more recently than this many minutes ago are skipped
     * @return locked unprocessed rows in insertion order
     */
    @Query(value = """
            SELECT * FROM indexing_outbox
            WHERE processed_at IS NULL
              AND (claimed_at IS NULL
                   OR claimed_at < (NOW() - make_interval(mins => :leaseMinutes)))
            ORDER BY id ASC
            FOR UPDATE SKIP LOCKED
            LIMIT :limit
            """, nativeQuery = true)
    List<IndexingOutboxRow> claimUnprocessedForPolling(
            @Param("limit") int limit,
            @Param("leaseMinutes") int leaseMinutes);

    /**
     * Count of unprocessed rows. Cheap because it uses the partial
     * index. Useful for the poller's monitoring or backlog dashboards.
     */
    @Query("SELECT COUNT(r) FROM IndexingOutboxRow r "
            + "WHERE r.processedAt IS NULL")
    long countUnprocessed();

    /**
     * Count of unprocessed rows for a specific event type. Useful when
     * the operator wants to know whether the backlog is dominated by
     * SUMMARY_CREATED, TRANSCRIPT_INDEXED, or another emitter.
     */
    @Query("SELECT COUNT(r) FROM IndexingOutboxRow r "
            + "WHERE r.processedAt IS NULL AND r.eventType = :eventType")
    long countUnprocessedByEventType(@Param("eventType") String eventType);
}