package com.careconnect.service.ai.indexing.chunker;

import com.careconnect.service.ai.indexing.IndexingChunkDraft;
import com.careconnect.service.ai.retrieval.RetrievalRecordType;
import org.springframework.stereotype.Component;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Builds a single {@link RetrievalRecordType#USPS_MAIL} chunk draft per mailpiece
 * (Task 3.14.5 / #122).
 */
@Component
public class MailpieceChunker {

    public List<IndexingChunkDraft> chunk(
            final String sender,
            final String summary,
            final String ocrText,
            final String contentHash,
            final String sourceKey,
            final LocalDate digestDate,
            final String consentScope) {
        final List<IndexingChunkDraft> drafts = new ArrayList<>(1);
        final String chunkText = buildChunkText(sender, summary, ocrText);
        if (chunkText.isBlank()) {
            return drafts;
        }

        final Map<String, Object> metadata = new LinkedHashMap<>();
        metadata.put("section", "mailpiece");
        if (sourceKey != null && !sourceKey.isBlank()) {
            metadata.put("sourceKey", sourceKey);
        }
        if (digestDate != null) {
            metadata.put("digestDate", digestDate.toString());
        }
        if (contentHash != null && !contentHash.isBlank()) {
            metadata.put("contentHash", contentHash);
        }
        if (sender != null && !sender.isBlank()) {
            metadata.put("sender", sender);
        }

        drafts.add(new IndexingChunkDraft(
                RetrievalRecordType.USPS_MAIL,
                chunkText,
                metadata,
                consentScope));
        return drafts;
    }

    String buildChunkText(final String sender, final String summary, final String ocrText) {
        final StringBuilder sb = new StringBuilder();
        if (sender != null && !sender.isBlank()) {
            sb.append("From: ").append(sender.trim());
        }
        if (summary != null && !summary.isBlank()) {
            if (!sb.isEmpty()) {
                sb.append('\n');
            }
            sb.append(summary.trim());
        }
        if (ocrText != null && !ocrText.isBlank()) {
            if (!sb.isEmpty()) {
                sb.append('\n');
            }
            sb.append(ocrText.trim());
        }
        return sb.toString().trim();
    }
}
