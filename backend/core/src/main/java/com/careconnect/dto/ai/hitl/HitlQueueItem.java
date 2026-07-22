package com.careconnect.dto.ai.hitl;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

/**
 * Reviewer queue row.
 */
public record HitlQueueItem(
        UUID heldItemId,
        Long patientId,
        List<String> triggerCodes,
        String sourceSurface,
        Instant createdAt,
        Instant expiresAt
) {
}
