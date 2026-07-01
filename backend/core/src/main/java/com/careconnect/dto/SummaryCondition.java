package com.careconnect.dto;

/**
 * Strongly-typed medical condition extracted by the call summary pipeline.
 *
 * <p>Added per Prof. Assadullah's 2026-06-27 directive that the system must
 * be cognizant of which conditions are currently affecting the patient
 * vs. which are resolved. His example: a patient was lethargic for six
 * months because of an infection but does not feel lethargic now; a query
 * about lethargy must reflect that state change.
 *
 * <p>This is distinct from the {@code clinicalObservations} block of the
 * summary, which captures free-text observations of the call itself.
 * {@code SummaryCondition} entries are structured, state-tracked entities
 * suitable for filtered retrieval (for example, "what conditions is the
 * patient currently experiencing?" can scope to {@code status = "active"}).
 *
 * <p>Allowed {@code status} values:
 * <ul>
 *   <li>{@code active} &mdash; condition currently affecting the patient</li>
 *   <li>{@code resolved} &mdash; condition was present in the past but no
 *       longer affects the patient (example: infection that has cleared)</li>
 *   <li>{@code suspected} &mdash; condition is being investigated or
 *       considered but not confirmed</li>
 *   <li>{@code unknown} &mdash; state could not be determined from the
 *       transcript</li>
 * </ul>
 *
 * <p>The {@code effectiveDate} carries the date this state took effect,
 * in ISO 8601 {@code yyyy-MM-dd} form. May be empty when the transcript
 * does not provide an explicit date.
 *
 * @param itemId            stable identifier for the item within the summary
 * @param name              short condition name (for example,
 *                          {@code "lethargy"}, {@code "hypertension"})
 * @param description       longer free-text description of the condition as
 *                          discussed in the call
 * @param status            lifecycle state: {@code active}, {@code resolved},
 *                          {@code suspected}, or {@code unknown}
 * @param effectiveDate     ISO 8601 date this state took effect, or empty
 * @param confidence        model confidence in the extracted item, 0.0&ndash;1.0
 * @param sourceTurnId      identifier of the supporting transcript turn
 * @param needsConfirmation user confirmation gate; cleared on explicit confirm
 */
public record SummaryCondition(
        String itemId,
        String name,
        String description,
        String status,
        String effectiveDate,
        Double confidence,
        String sourceTurnId,
        Boolean needsConfirmation
) {
}
