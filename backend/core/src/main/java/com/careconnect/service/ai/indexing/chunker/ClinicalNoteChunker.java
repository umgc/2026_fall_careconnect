package com.careconnect.service.ai.indexing.chunker;

import com.careconnect.service.ai.indexing.IndexingChunkDraft;
import com.careconnect.service.ai.retrieval.RetrievalRecordType;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.stereotype.Component;

/**
 * Builds a single {@link RetrievalRecordType#CLINICAL_NOTE} chunk draft per patient
 * note (Task 4.1), combining the raw note text and its AI-generated summary.
 */
@Component
public class ClinicalNoteChunker {

    public List<IndexingChunkDraft> chunk(
            final String note,
            final String aiSummary,
            final String contentHash,
            final String consentScope) {
        final List<IndexingChunkDraft> drafts = new ArrayList<>(1);
        final String chunkText = buildChunkText(note, aiSummary);
        if (chunkText.isBlank()) {
            return drafts;
        }

        final Map<String, Object> metadata = new LinkedHashMap<>();
        metadata.put("section", "clinical_note");
        if (contentHash != null && !contentHash.isBlank()) {
            metadata.put("contentHash", contentHash);
        }

        drafts.add(new IndexingChunkDraft(
                RetrievalRecordType.CLINICAL_NOTE,
                chunkText,
                metadata,
                consentScope));
        return drafts;
    }

    String buildChunkText(final String note, final String aiSummary) {
        final StringBuilder sb = new StringBuilder();
        if (note != null && !note.isBlank()) {
            sb.append(note.trim());
        }
        if (aiSummary != null && !aiSummary.isBlank()) {
            if (!sb.isEmpty()) {
                sb.append('\n');
            }
            sb.append("Summary: ").append(aiSummary.trim());
        }
        return sb.toString().trim();
    }
}
