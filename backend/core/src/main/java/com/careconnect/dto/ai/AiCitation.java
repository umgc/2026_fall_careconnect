package com.careconnect.dto.ai;

import com.careconnect.service.ai.retrieval.RetrievalRecordType;

import java.util.UUID;

/**
 * Citation chip mapped from a retrieved {@code RankedChunk} (Task 5.3 / 5.5).
 */
public record AiCitation(
        String citationId,
        RetrievalRecordType recordType,
        String sourceRecordId,
        UUID chunkId,
        String title,
        String excerpt,
        String deepLink,
        Double confidence
) {
}
