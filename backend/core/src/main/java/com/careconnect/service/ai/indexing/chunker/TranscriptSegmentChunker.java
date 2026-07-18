package com.careconnect.service.ai.indexing.chunker;

import com.careconnect.model.CallTranscriptSegment;
import com.careconnect.service.ai.indexing.IndexingChunkDraft;
import com.careconnect.service.ai.retrieval.RetrievalRecordType;
import org.springframework.stereotype.Component;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Maps each persisted transcript segment to one {@link RetrievalRecordType#TRANSCRIPT_SEGMENT}
 * chunk (Task 4.1). One segment = one chunk, matching CallTranscriptService limits.
 */
@Component
public class TranscriptSegmentChunker {

    /**
     * Builds drafts for the given segments.
     *
     * @param callId  call identifier used in metadata
     * @param source  segment source label from the indexing event
     * @param segments ordered transcript segments
     * @return chunk drafts (empty segments skipped)
     */
    public List<IndexingChunkDraft> chunk(
            final String callId,
            final String source,
            final List<CallTranscriptSegment> segments) {
        final List<IndexingChunkDraft> drafts = new ArrayList<>();
        if (segments == null || segments.isEmpty()) {
            return drafts;
        }
        int chunkIndex = 0;
        for (final CallTranscriptSegment segment : segments) {
            if (segment == null || isBlank(segment.getText())) {
                continue;
            }
            final Map<String, Object> metadata = new LinkedHashMap<>();
            metadata.put("callId", callId);
            metadata.put("segmentId", segment.getId());
            metadata.put("chunkIndex", chunkIndex++);
            metadata.put("speakerLabel", segment.getSpeakerLabel());
            metadata.put("startMs", segment.getStartMs());
            metadata.put("endMs", segment.getEndMs());
            metadata.put("source", source != null ? source : segment.getSource());
            metadata.put("actorUserId", segment.getActorUserId());
            if (segment.getOccurredAt() != null) {
                metadata.put("occurredAt", segment.getOccurredAt().toString());
            }

            final String text = formatSegmentText(segment);
            drafts.add(new IndexingChunkDraft(
                    RetrievalRecordType.TRANSCRIPT_SEGMENT,
                    text,
                    metadata,
                    null));
        }
        return drafts;
    }

    private static String formatSegmentText(final CallTranscriptSegment segment) {
        final String speaker = segment.getSpeakerLabel();
        if (speaker == null || speaker.isBlank()) {
            return segment.getText().trim();
        }
        return speaker.trim() + ": " + segment.getText().trim();
    }

    private static boolean isBlank(final String value) {
        return value == null || value.isBlank();
    }
}
