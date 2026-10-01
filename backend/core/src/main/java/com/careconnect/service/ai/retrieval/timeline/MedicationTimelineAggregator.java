package com.careconnect.service.ai.retrieval.timeline;

import com.careconnect.dto.ai.MedicationTimelineDto;
import com.careconnect.service.ai.retrieval.RankedChunk;

import java.util.List;

/**
 * Aggregates {@link com.careconnect.service.ai.retrieval.RetrievalRecordType#MEDICATION_TIMELINE_EVENT}
 * chunks from a retrieval result into a deduplicated, chronologically sorted medication
 * timeline for {@code medication_timeline} intent Ask AI responses (Task 5).
 */
public interface MedicationTimelineAggregator {

    /**
     * Builds a medication timeline from the given ranked chunks.
     *
     * @param chunks final ranked chunks from a hybrid retrieval search
     * @return the aggregated timeline, or {@code null} when no timeline events are present
     */
    MedicationTimelineDto aggregate(List<RankedChunk> chunks);
}
