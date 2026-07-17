package com.careconnect.service.ai.retrieval;

import java.util.UUID;

/**
 * One hybrid-ranked retrieval hit after FTS + vector Reciprocal Rank Fusion (Task 5.1).
 *
 * <p>{@link #citationRef()} is assigned as {@code C1..Cn} in final top-k order for
 * downstream citation assembly (Task 5.5 / Ask AI prompt).
 */
public record RankedChunk(
        UUID chunkId,
        Long patientId,
        RetrievalRecordType recordType,
        String sourceRecordId,
        String chunkText,
        String chunkMetadata,
        String consentScope,
        double rrfScore,
        Integer ftsRank,
        Integer vectorRank,
        String citationRef
) {
}
