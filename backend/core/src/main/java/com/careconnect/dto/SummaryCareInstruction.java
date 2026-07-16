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
 * <p>The {@code status} field tracks the state of the instruction per
 * Prof. Assadullah's 2026-06-27 directive that the system must distinguish
 * between currently active medications and discontinued ones (his example:
 * aspirin prescribed last year, then discontinued, so a query about aspirin
 * must reflect the current off state). Allowed values:
 * <ul>
 *   <li>{@code active} &mdash; currently in effect (medication being taken,
 *       procedure scheduled, instruction in force)</li>
 *   <li>{@code started} &mdash; newly initiated in this call</li>
 *   <li>{@code discontinued} &mdash; previously active, now stopped</li>
 *   <li>{@code unknown} &mdash; state could not be determined from the
 *       transcript</li>
 * </ul>
 *
 * <p>The {@code effectiveDate} carries the date this state took effect,
 * in ISO 8601 {@code yyyy-MM-dd} form. For {@code started} or {@code active}
 * items this is when the medication or instruction began; for
 * {@code discontinued} items this is when it stopped. May be empty when
 * the transcript does not provide an explicit date.
 *
 * @param itemId            stable identifier for the item within the summary
 * @param type              one of {@code medication}, {@code procedure}, or
 *                          {@code instruction}
 * @param text              instruction text shown to the user
 * @param status            lifecycle state: {@code active}, {@code started},
 *                          {@code discontinued}, or {@code unknown}
 * @param effectiveDate     ISO 8601 date this state took effect, or empty
 * @param confidence        model confidence in the extracted item, 0.0&ndash;1.0
 * @param sourceTurnId      identifier of the supporting transcript turn
 * @param needsConfirmation user confirmation gate; cleared on explicit confirm
 */
public record SummaryCareInstruction(
        String itemId,
        String type,
        String text,
        String status,
        String effectiveDate,
        Double confidence,
        String sourceTurnId,
        Boolean needsConfirmation
) {
}
