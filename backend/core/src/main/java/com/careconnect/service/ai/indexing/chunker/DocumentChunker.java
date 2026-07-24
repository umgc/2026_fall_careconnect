package com.careconnect.service.ai.indexing.chunker;

import com.careconnect.service.ai.indexing.IndexingChunkDraft;
import com.careconnect.service.ai.retrieval.RetrievalRecordType;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.stereotype.Component;

/**
 * Builds a single {@link RetrievalRecordType#UPLOADED_DOCUMENT} chunk draft from an
 * uploaded document's short description/caption text (Task 4.1, description-only MVP;
 * full OCR-backed document text indexing is future work).
 */
@Component
public class DocumentChunker {

    public List<IndexingChunkDraft> chunk(
            final String textExcerpt,
            final String fileCategory,
            final String contentHash,
            final String consentScope) {
        final List<IndexingChunkDraft> drafts = new ArrayList<>(1);
        final String chunkText = textExcerpt == null ? "" : textExcerpt.trim();
        if (chunkText.isBlank()) {
            return drafts;
        }

        final Map<String, Object> metadata = new LinkedHashMap<>();
        metadata.put("section", "uploaded_document");
        if (fileCategory != null && !fileCategory.isBlank()) {
            metadata.put("fileCategory", fileCategory);
        }
        if (contentHash != null && !contentHash.isBlank()) {
            metadata.put("contentHash", contentHash);
        }

        drafts.add(new IndexingChunkDraft(
                RetrievalRecordType.UPLOADED_DOCUMENT,
                chunkText,
                metadata,
                consentScope));
        return drafts;
    }
}
