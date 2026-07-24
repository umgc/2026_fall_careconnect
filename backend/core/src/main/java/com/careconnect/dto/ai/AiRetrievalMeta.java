package com.careconnect.dto.ai;

/**
 * Retrieval / inference timing and counts for Ask AI responses.
 */
public record AiRetrievalMeta(
        int chunksRetrieved,
        int chunksUsed,
        long retrievalLatencyMs,
        Long inferenceLatencyMs,
        boolean vectorDegraded,
        AiModelMeta model
) {
}
