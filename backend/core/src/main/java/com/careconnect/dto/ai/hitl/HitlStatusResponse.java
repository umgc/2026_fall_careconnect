package com.careconnect.dto.ai.hitl;

import com.careconnect.dto.ai.AiConfirmationHint;
import com.careconnect.dto.ai.AiDisclaimer;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

/**
 * Patient/caller-visible HITL poll response.
 */
public record HitlStatusResponse(
        UUID heldItemId,
        String status,
        String deliveryStatus,
        String message,
        String answer,
        List<Object> citations,
        Instant expiresAt,
        AiDisclaimer disclaimer,
        AiConfirmationHint confirmation
) {
}
