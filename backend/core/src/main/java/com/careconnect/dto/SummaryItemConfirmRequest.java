package com.careconnect.dto;

/**
 * Request body for {@code POST /api/v3/calls/{callId}/summary/items/{itemId}/confirm}
 * (Task 6.7 / FR-SUM-4).
 *
 * @param decision    one of {@code approve}, {@code approve-for-session}, or {@code decline}
 * @param destination optional downstream write destination (for example {@code calendar},
 *                    {@code reminders}, or {@code care_plan}); ignored for {@code decline}
 * @param notes       optional free-text notes captured with the decision
 */
public record SummaryItemConfirmRequest(
        String decision,
        String destination,
        String notes
) {
}
