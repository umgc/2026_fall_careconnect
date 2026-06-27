package com.careconnect.dto;

/**
 * Strongly-typed care instruction extracted by the call summary pipeline.
 *
 * <p>Care instructions are sub-classified into three kinds via the
 * {@code type} field:
 * <ul>
 *   <li>{@code medication} &mdash; medication change, addition, or removal;
 *       requires per-item confirmation and surfaces the medical disclaimer
 *       (REQ-SC-5).</li>
 *   <li>{@code procedure} &mdash; clinical procedure or test, such as a lab
 *       order or imaging study.</li>
 *   <li>{@code instruction} &mdash; general care instruction such as
 *       monitoring guidance or activity restrictions.</li>
 * </ul>
 *
 * @param itemId            stable identifier for the item within the summary
 * @param type              one of {@code medication}, {@code procedure}, or
 *                          {@code instruction}
 * @param text              instruction text shown to the user
 * @param confidence        model confidence in the extracted item, 0.0&ndash;1.0
 * @param sourceTurnId      identifier of the supporting transcript turn
 * @param needsConfirmation user confirmation gate; cleared on explicit confirm
 */
public record SummaryCareInstruction(
        String itemId,
        String type,
        String text,
        Double confidence,
        String sourceTurnId,
        Boolean needsConfirmation
) {
}
