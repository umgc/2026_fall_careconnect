package com.careconnect.indexing;

import java.time.LocalDateTime;

/**
 * Body of the {@code SUMMARY_CREATED} event's {@code payload} field.
 * Emitted after a {@code CallSummary} row is persisted with
 * {@code status == SUCCESS} (WBS 3.11.5, #190).
 *
 * <p>Contract from Ravichandra Vasireddy's 2026-07-03 Transcript
 * Ingest and SUMMARY_CREATED Indexing Contract, section 3.3.
 * Emit is skipped for {@code NO_TRANSCRIPT} and {@code ERROR}
 * summaries per section 3.4 (Field: status).
 *
 * @param episodeType            {@code call} or {@code visit}; indexer
 *                               may filter on this at query time
 * @param sourceTable            {@code call_summaries} or
 *                               {@code visit_summaries}
 * @param summaryId              persisted summary PK; used as the
 *                               correlation key on retrieval_index_chunk
 * @param callId                 call identifier for call summaries;
 *                               null for visits
 * @param patientId              patient the summary is about; used for
 *                               row-level RBAC scope. Nullable for
 *                               historic rows that predate PR #244
 * @param status                 summary status; expected to be
 *                               {@code SUCCESS} at emit time
 * @param generatedAt            when the summary was persisted
 * @param transcriptSegmentCount segment count that fed the summary;
 *                               nullable, informational only
 * @param caregiverVisibility    {@code on_consent}, {@code auto}, or
 *                               {@code hidden}
 * @param summarizationEngine    engine string for audit / traceability
 * @param contentHash            SHA-256 of {@code summary_json} for
 *                               idempotent re-indexing
 */
public record SummaryCreatedPayload(
        String episodeType,
        String sourceTable,
        Long summaryId,
        String callId,
        Long patientId,
        String status,
        LocalDateTime generatedAt,
        Integer transcriptSegmentCount,
        String caregiverVisibility,
        String summarizationEngine,
        String contentHash
) {
}