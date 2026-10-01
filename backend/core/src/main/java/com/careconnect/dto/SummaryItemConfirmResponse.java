package com.careconnect.dto;

import java.util.UUID;

/**
 * Response body for {@code POST /api/v3/calls/{callId}/summary/items/{itemId}/confirm}
 * (Task 6.7 / FR-SUM-4).
 *
 * @param itemId     identifier of the confirmed/declined item
 * @param decision   normalized decision that was recorded, or {@code null} when held
 * @param held       {@code true} when the item was routed to Tier-2 HITL review instead of
 *                   being recorded immediately
 * @param heldItemId identifier of the created HITL hold, when {@code held} is {@code true}
 * @param decisionId identifier of the persisted {@code CallSummaryItemDecision} audit row,
 *                   when {@code held} is {@code false}
 */
public record SummaryItemConfirmResponse(
        String itemId,
        String decision,
        boolean held,
        UUID heldItemId,
        Long decisionId
) {
}
