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
        return chunk(sender, summary, ocrText, contentHash, sourceKey, digestDate, consentScope,
                null, null, null, null);
    }

    public List<IndexingChunkDraft> chunk(
            final String sender,
            final String summary,
            final String ocrText,
            final String contentHash,
            final String sourceKey,
            final LocalDate digestDate,
            final String consentScope,
            final String importanceLevel,
            final String importanceCategory,
            final String classificationMethod,
            final String importanceReasoning) {
        final List<IndexingChunkDraft> drafts = new ArrayList<>(1);
        final String chunkText = buildChunkText(
                sender, summary, ocrText, importanceLevel, importanceCategory, importanceReasoning);
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
        if (importanceLevel != null && !importanceLevel.isBlank()) {
            metadata.put("importanceLevel", importanceLevel);
        }
        if (importanceCategory != null && !importanceCategory.isBlank()) {
            metadata.put("importanceCategory", importanceCategory);
        }
        if (classificationMethod != null && !classificationMethod.isBlank()) {
            metadata.put("classificationMethod", classificationMethod);
        }
        if (importanceReasoning != null && !importanceReasoning.isBlank()) {
            metadata.put("importanceReasoning", importanceReasoning);
        }
        final String importanceFingerprint = importanceFingerprint(
                importanceLevel, importanceCategory, classificationMethod, importanceReasoning);
        if (importanceFingerprint != null) {
            metadata.put("importanceFingerprint", importanceFingerprint);
        }

        drafts.add(new IndexingChunkDraft(
                RetrievalRecordType.USPS_MAIL,
                chunkText,
                metadata,
                consentScope));
        return drafts;
    }

    /**
     * Stable classification fingerprint stored in chunk metadata so ingest can
     * distinguish content-only hashes from classification backfills.
     */
    public static String importanceFingerprint(
            final String importanceLevel,
            final String importanceCategory,
            final String classificationMethod,
            final String importanceReasoning) {
        if ((importanceLevel == null || importanceLevel.isBlank())
                && (importanceCategory == null || importanceCategory.isBlank())
                && (classificationMethod == null || classificationMethod.isBlank())
                && (importanceReasoning == null || importanceReasoning.isBlank())) {
            return null;
        }
        return String.join(
                "|",
                nullToEmpty(importanceLevel),
                nullToEmpty(importanceCategory),
                nullToEmpty(classificationMethod),
                nullToEmpty(importanceReasoning));
    }

    private static String nullToEmpty(final String value) {
        return value == null ? "" : value.trim();
    }

    String buildChunkText(
            final String sender,
            final String summary,
            final String ocrText,
            final String importanceLevel,
            final String importanceCategory,
            final String importanceReasoning) {
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
        if (importanceLevel != null && !importanceLevel.isBlank()) {
            if (!sb.isEmpty()) {
                sb.append('\n');
            }
            sb.append("Importance: ").append(importanceLevel.trim());
            if (importanceCategory != null && !importanceCategory.isBlank()) {
                sb.append(" (").append(importanceCategory.trim()).append(')');
            }
        }
        if (importanceReasoning != null && !importanceReasoning.isBlank()) {
            if (!sb.isEmpty()) {
                sb.append('\n');
            }
            sb.append("Reasoning: ").append(importanceReasoning.trim());
        }
        return sb.toString().trim();
    }

    String buildChunkText(final String sender, final String summary, final String ocrText) {
        return buildChunkText(sender, summary, ocrText, null, null, null);
    }
}
