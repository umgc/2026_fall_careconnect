package com.careconnect.dto.ai;

/**
 * Tier / escalation metadata. Full Tier-2 HITL hold is Task 6.x; Task 5.3 delivers Tier 1.
 */
public record AiEscalation(
        int tier,
        String reason,
        boolean requiresClinicianReview
) {
}
