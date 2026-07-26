package com.careconnect.service.ai.retrieval;

import com.careconnect.service.ai.indexing.SummarySourceKey;

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
        String sourceKind,
        String sourceRecordId,
        String chunkText,
        String chunkMetadata,
        String consentScope,
        double rrfScore,
        Integer ftsRank,
        Integer vectorRank,
        String citationRef
) {
    public RankedChunk(
            final UUID chunkId,
            final Long patientId,
            final RetrievalRecordType recordType,
            final String sourceRecordId,
            final String chunkText,
            final String chunkMetadata,
            final String consentScope,
            final double rrfScore,
            final Integer ftsRank,
            final Integer vectorRank,
            final String citationRef) {
        this(
                chunkId,
                patientId,
                recordType,
                SummarySourceKey.sourceKind(sourceRecordId),
                sourceRecordId,
                chunkText,
                chunkMetadata,
                consentScope,
                rrfScore,
                ftsRank,
                vectorRank,
                citationRef);
    }
}
