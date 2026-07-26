package com.careconnect.dto.ai;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

/**
 * Response body for {@code POST /api/ai/ask} (Task 5.3).
 */
public record AiAskResponse(
        boolean success,
        UUID requestId,
        UUID auditId,
        UUID sessionId,
        Instant timestamp,
        DeliveryStatus deliveryStatus,
        int tier,
        boolean held,
        UUID heldItemId,
        AiAnswerBlock answer,
        List<AiCitation> citations,
        AiDisclaimer disclaimer,
        AiEscalation escalation,
        AiConfirmationHint confirmation,
        AiRetrievalMeta retrievalMeta,
        String message,
        String pollUrl,
        AiErrorBlock error
) {
}
