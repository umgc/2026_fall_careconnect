package com.careconnect.dto.ai;

import com.careconnect.service.ai.retrieval.RetrievalRecordType;

import java.time.Instant;
import java.util.Map;
import java.util.UUID;

/**
 * Validated citation chip mapped from a retrieved {@code RankedChunk} (Task 5.5).
 *
 * <p>{@code confidence} is a source-provided value in the inclusive range {@code [0,1]}.
 * It is intentionally not the hybrid retrieval RRF score, which is a ranking signal rather
 * than a calibrated probability. {@code deepLink} is null when the record type does not have
 * enough validated metadata to construct a safe application route.
 */
public record AiCitation(
        String citationId,
        RetrievalRecordType recordType,
        String sourceRecordId,
        UUID chunkId,
        String title,
        String excerpt,
        Instant occurredAt,
        String deepLink,
        Double confidence,
        Map<String, Object> metadata
) {
    public AiCitation {
        metadata = metadata == null ? Map.of() : Map.copyOf(metadata);
    }
}
