package com.careconnect.dto.ai.hitl;

/**
 * Reviewer release body.
 */
public record HitlReleaseRequest(
        String editedAnswer,
        String notes
) {
}
