package com.careconnect.service.ai.indexing;

import com.careconnect.service.ai.retrieval.RetrievalRecordType;

import java.util.Map;

/**
 * Intermediate chunk produced by a chunker before persistence (Task 4.1).
 *
 * @param recordType   canonical retrieval record type
 * @param chunkText    searchable text body
 * @param metadata     JSON-serializable metadata (contentHash, segmentId, etc.)
 * @param consentScope optional consent / caregiver visibility label
 */
public record IndexingChunkDraft(
        RetrievalRecordType recordType,
        String chunkText,
        Map<String, Object> metadata,
        String consentScope
) {
}
