package com.careconnect.indexing;

import com.fasterxml.jackson.annotation.JsonAlias;
import com.fasterxml.jackson.annotation.JsonProperty;

/**
 * Body of the {@code TRANSCRIPT_INDEXED} event's {@code payload}
 * field. Emitted after a batch of transcript segments is persisted
 * for a call (WBS 3.11.1, #186).
 *
 * <p>Contract from Ravichandra Vasireddy's 2026-07-03 Transcript
 * Ingest and SUMMARY_CREATED Indexing Contract, section 2.7.
 *
 * <p>Legacy outbox rows may still carry {@code segmentCount}/{@code source}; Jackson
 * aliases keep those payloads ingestible after the field rename.
 *
 * @param callId       call identifier the segments belong to
 * @param patientId    patient the call is associated with; nullable
 *                     until the call telemetry lookup lands or the
 *                     caller can supply it directly
 * @param totalSegmentCount number of segments in the complete authoritative snapshot
 * @param snapshotVersion deterministic version of that complete snapshot
 */
public record TranscriptIndexedPayload(
        String callId,
        Long patientId,
        @JsonProperty("totalSegmentCount")
        @JsonAlias("segmentCount")
        int totalSegmentCount,
        @JsonProperty("snapshotVersion")
        @JsonAlias("source")
        String snapshotVersion
) {
}
