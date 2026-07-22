package com.careconnect.dto.ai.hitl;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

/**
 * Reviewer detail view (includes draft and original query).
 */
public record HitlDetailResponse(
        UUID heldItemId,
        Long patientId,
        Long requesterUserId,
        String status,
        String deliveryStatus,
        List<String> triggerCodes,
        String queryText,
        String draftAnswer,
        String finalAnswer,
        String citationsJson,
        String validationFindingsJson,
        Instant createdAt,
        Instant expiresAt,
        Instant reviewedAt,
        Long reviewerUserId,
        String reviewNotes
) {
}
