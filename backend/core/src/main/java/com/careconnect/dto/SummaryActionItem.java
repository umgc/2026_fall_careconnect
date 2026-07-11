package com.careconnect.dto;

/**
 * Strongly-typed extracted action item produced by the call summary pipeline.
 *
 * <p>Stored inside the {@code summary_json} payload of {@code call_summaries}
 * rather than in its own column. Every action item carries a stable
 * {@code itemId} (server-generated UUID) so downstream confirmation and
 * dismissal flows can reference it through the
 * {@code /api/v3/calls/{callId}/summary/items/{itemId}/confirm} endpoint.
 *
 * <p>The {@code needsConfirmation} flag is set to {@code true} for every
 * newly extracted item and is cleared only when a user explicitly confirms
 * the item; this is required by FR-SUM-4 and REQ-SC-5.
 *
 * <p>The {@code status} field carries lifecycle state per Prof. Assadullah's
 * 2026-06-27 directive that the system must be cognizant of which actions
 * are still pending vs. already completed when surfacing items in the STML
 * Daily Memory Brief or Ask AI retrieval. Allowed values:
 * <ul>
 *   <li>{@code pending} &mdash; the action has not yet been completed</li>
 *   <li>{@code completed} &mdash; the action has been completed</li>
 *   <li>{@code cancelled} &mdash; the action was cancelled or no longer applies</li>
 * </ul>
 *
 * @param itemId            stable identifier for the item within the summary
 * @param text              action description shown to the user
 * @param actor             party expected to act (for example,
 *                          {@code care_recipient}, {@code caregiver})
 * @param dueHint           natural-language hint such as {@code "within 2 weeks"}
 * @param status            lifecycle state: {@code pending}, {@code completed},
 *                          or {@code cancelled}
 * @param confidence        model confidence in the extracted item, 0.0&ndash;1.0
 * @param sourceTurnId      identifier of the supporting transcript turn
 * @param needsConfirmation user confirmation gate; cleared on explicit confirm
 */
public record SummaryActionItem(
        String itemId,
        String text,
        String actor,
        String dueHint,
        String status,
        Double confidence,
        String sourceTurnId,
        Boolean needsConfirmation
) {
}
