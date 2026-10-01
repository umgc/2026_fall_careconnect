package com.careconnect.dto.ai;

/**
 * One deduplicated medication timeline event surfaced for a {@code medication_timeline}
 * intent Ask AI response (Task 5).
 *
 * @param itemId                   source summary care-instruction item id, when known
 * @param medicationName           medication name as captured on the source item
 * @param medicationNameNormalized normalized medication name used for de-duplication
 * @param eventType                lifecycle status (e.g. {@code started}, {@code stopped},
 *                                 {@code changed})
 * @param effectiveDate            ISO 8601 date the event took effect, when known
 * @param doseFrom                 dose before the change, when applicable
 * @param doseTo                   dose after the change, when applicable
 * @param citationRef              {@code C1..Cn} citation reference for the source chunk
 */
public record MedicationTimelineEventDto(
        String itemId,
        String medicationName,
        String medicationNameNormalized,
        String eventType,
        String effectiveDate,
        String doseFrom,
        String doseTo,
        String citationRef
) {
}
