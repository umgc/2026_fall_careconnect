package com.careconnect.service.ai.retrieval;

import java.util.List;

/**
 * Result of {@link HybridRetrievalService#search} (Task 5.1).
 *
 * @param chunks           final top-k ranked chunks with citation refs {@code C1..Cn}
 * @param query            sanitized query that was searched
 * @param vectorDegraded   {@code true} when vector arm was skipped (embed failure / disabled)
 * @param ftsHitCount      FTS arm hits before RRF (after visibility filter)
 * @param vectorHitCount   vector arm hits before RRF (after visibility filter)
 */
public record HybridRetrievalResult(
        List<RankedChunk> chunks,
        String query,
        boolean vectorDegraded,
        int ftsHitCount,
        int vectorHitCount
) {
    public static HybridRetrievalResult empty(final String query) {
        return new HybridRetrievalResult(List.of(), query == null ? "" : query, false, 0, 0);
    }

    public boolean isEmpty() {
        return chunks == null || chunks.isEmpty();
    }
}
