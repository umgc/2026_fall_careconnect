package com.careconnect.dto.ai;

/**
 * Inference provider metadata for Ask AI retrieval meta.
 */
public record AiModelMeta(
        String provider,
        String modelId
) {
}
