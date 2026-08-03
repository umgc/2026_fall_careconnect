package com.careconnect.dto.ai;

import java.util.List;

/**
 * Aggregated, deduplicated medication timeline surfaced on {@link AiAskResponse} when the
 * query planner classifies the request as a medication-timeline intent (Task 5).
 *
 * @param events chronologically sorted (by {@code effectiveDate}), deduplicated events
 */
public record MedicationTimelineDto(
        List<MedicationTimelineEventDto> events
) {
}
