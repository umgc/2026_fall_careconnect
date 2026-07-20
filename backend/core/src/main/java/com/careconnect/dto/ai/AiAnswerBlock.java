package com.careconnect.dto.ai;

/**
 * Grounded answer text for a delivered Ask AI response.
 */
public record AiAnswerBlock(
        String text,
        String locale
) {
}
