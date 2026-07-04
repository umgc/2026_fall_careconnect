package com.careconnect.indexing;

/**
 * Body of the {@code TRANSCRIPT_INDEXED} event's {@code payload}
 * field. Emitted after a batch of transcript segments is persisted
 * for a call (WBS 3.11.1, #186).
 *
 * <p>Contract from Ravichandra Vasireddy's 2026-07-03 Transcript
 * Ingest and SUMMARY_CREATED Indexing Contract, section 2.7.
 *
 * @param callId       call identifier the segments belong to
 * @param patientId    patient the call is associated with; nullable
 *                     until the call telemetry lookup lands or the
 *                     caller can supply it directly
 * @param segmentCount number of segments persisted in this batch
 * @param source       segment source label
 *                     ({@code POST_CALL_TRANSCRIBE},
 *                     {@code CLIENT_TRANSCRIPT}, or archive) used by
 *                     the indexer to pick chunker settings
 */
public record TranscriptIndexedPayload(
        String callId,
        Long patientId,
        int segmentCount,
        String source
) {
}