package com.careconnect.model.indexing;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;

/**
 * Transactional outbox row for indexing events emitted by the summaries
 * workstream and consumed by the Ask AI upstream indexing pipeline.
 *
 * <p>Fon writes rows in the same {@code @Transactional} method that
 * persists a {@code CallSummary} or a transcript segment batch, so the
 * event and the source record commit or roll back together. Ravi's
 * poller (backlog 3.4) reads unprocessed rows in insertion order,
 * publishes each to SNS, and stamps {@link #processedAt} on success.
 * An {@code IndexWorker} (Task 4.1) currently consumes outbox rows in-process
 * and writes to the {@code retrieval_index_chunk} table (SNS/SQS remains a
 * future transport upgrade).
 *
 * <p>Known {@link #eventType} values, per the 2026-07-03 Transcript
 * Ingest and SUMMARY_CREATED Indexing Contract:
 * <ul>
 *   <li>{@code SUMMARY_CREATED} - emitted after a successful
 *       {@code call_summaries} insert (WBS 3.11.5, #190).</li>
 *   <li>{@code TRANSCRIPT_INDEXED} - emitted after a successful
 *       transcript segment batch save (WBS 3.11.1, #186).</li>
 * </ul>
 *
 * <p>The {@link #payloadJson} field carries the full event envelope
 * including {@code schemaVersion}, {@code eventId} (for consumer
 * idempotency), and the event-specific payload body. Consumers
 * deserialize with Jackson and use {@code eventId} for de-duplication.
 */
@Entity
@Table(
        name = "indexing_outbox",
        indexes = {
                @Index(
                        name = "idx_indexing_outbox_event_type",
                        columnList = "event_type"
                )
                // The partial index idx_indexing_outbox_unprocessed
                // (WHERE processed_at IS NULL) is created by the
                // Flyway migration; JPA @Index cannot express WHERE.
        }
)
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class IndexingOutboxRow {

    /** Auto-generated primary key. */
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /**
     * Event type discriminator. Known values:
     * {@code SUMMARY_CREATED}, {@code TRANSCRIPT_INDEXED}. Modeled as
     * String rather than enum so new event types can be introduced by
     * emitters without an enum migration on the consumer side.
     */
    @Column(name = "event_type", nullable = false, length = 64)
    private String eventType;

    /**
     * Full event envelope as JSON. Shape per Ravi's 2026-07-03
     * indexing contract:
     * <pre>
     * {
     *   "eventType": "SUMMARY_CREATED",
     *   "eventId": "uuid",
     *   "occurredAt": "2026-07-03T22:57:00Z",
     *   "schemaVersion": 1,
     *   "payload": { ... event-specific fields ... }
     * }
     * </pre>
     */
    @Column(name = "payload_json", nullable = false, columnDefinition = "TEXT")
    private String payloadJson;

    /** Timestamp when the row was written by the emitter. */
    @Column(name = "created_at", nullable = false)
    private LocalDateTime createdAt;

    /**
     * Set by the poller after the row is successfully published to SNS.
     * Null while the row is still pending; the partial index
     * {@code idx_indexing_outbox_unprocessed} keeps the poller's
     * working set small even after millions of processed rows.
     */
    @Column(name = "processed_at")
    private LocalDateTime processedAt;

    /**
     * Number of publish attempts the poller has made. Incremented on
     * each attempt; used for backoff and dead-letter routing.
     */
    @Column(name = "attempt_count", nullable = false)
    private Integer attemptCount;

    /**
     * Most recent publish error captured by the poller, if any. Poller
     * policy on whether to clear on success or leave as forensic
     * evidence is Ravi's call.
     */
    @Column(name = "last_error", columnDefinition = "TEXT")
    private String lastError;

    /**
     * Set when {@code IndexWorker} claims the row for processing. Other workers
     * skip rows with a fresh {@code claimed_at} until the lease expires so
     * {@code FOR UPDATE SKIP LOCKED} is not required across the whole ingest.
     */
    @Column(name = "claimed_at")
    private LocalDateTime claimedAt;

    /**
     * Populate defaults when the caller does not set them explicitly.
     * The Flyway defaults would kick in on insert too, but populating
     * here means the returned entity has the values without a reload.
     */
    @PrePersist
    private void onCreate() {
        if (createdAt == null) {
            createdAt = LocalDateTime.now();
        }
        if (attemptCount == null) {
            attemptCount = 0;
        }
    }
}