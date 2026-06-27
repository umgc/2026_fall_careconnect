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
 * @param itemId            stable identifier for the item within the summary
 * @param text              action description shown to the user
 * @param actor             party expected to act (for example,
 *                          {@code care_recipient}, {@code caregiver})
 * @param dueHint           natural-language hint such as {@code "within 2 weeks"}
 * @param confidence        model confidence in the extracted item, 0.0&ndash;1.0
 * @param sourceTurnId      identifier of the supporting transcript turn
 * @param needsConfirmation user confirmation gate; cleared on explicit confirm
 */
public record SummaryActionItem(
        String itemId,
        String text,
        String actor,
        String dueHint,
        Double confidence,
        String sourceTurnId,
        Boolean needsConfirmation
) {
}
