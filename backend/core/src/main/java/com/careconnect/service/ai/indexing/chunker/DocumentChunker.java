package com.careconnect.service.ai.indexing.chunker;

import com.careconnect.service.ai.indexing.IndexingChunkDraft;
import com.careconnect.service.ai.retrieval.RetrievalRecordType;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.stereotype.Component;

/**
 * Builds {@link RetrievalRecordType#UPLOADED_DOCUMENT} chunk drafts from an uploaded
 * document's description and/or extracted plain text. Prefer extracted body text when present;
 * scanned images without OCR still fall back to description/caption only.
 *
 * <p>Long excerpts are split into overlapping character windows so embedding / FTS
 * payloads stay bounded (full-document single-chunk indexing blows up on large PDFs).
 */
@Component
public class DocumentChunker {

    /** Soft max characters per retrieval chunk (approx. mid-size embedding window). */
    static final int MAX_CHUNK_CHARS = 2500;

    /** Overlap between consecutive windows to preserve boundary context. */
    static final int OVERLAP_CHARS = 200;

    public List<IndexingChunkDraft> chunk(
            final String textExcerpt,
            final String fileCategory,
            final String contentHash,
            final String consentScope) {
        final List<IndexingChunkDraft> drafts = new ArrayList<>();
        final String chunkText = textExcerpt == null ? "" : textExcerpt.trim();
        if (chunkText.isBlank()) {
            return drafts;
        }

        final List<String> windows = splitIntoWindows(chunkText, MAX_CHUNK_CHARS, OVERLAP_CHARS);
        int chunkIndex = 0;
        for (final String window : windows) {
            if (window == null || window.isBlank()) {
                continue;
            }
            final Map<String, Object> metadata = new LinkedHashMap<>();
            metadata.put("section", "uploaded_document");
            metadata.put("chunkIndex", chunkIndex++);
            if (fileCategory != null && !fileCategory.isBlank()) {
                metadata.put("fileCategory", fileCategory);
            }
            if (contentHash != null && !contentHash.isBlank()) {
                metadata.put("contentHash", contentHash);
            }

            drafts.add(new IndexingChunkDraft(
                    RetrievalRecordType.UPLOADED_DOCUMENT,
                    window,
                    metadata,
                    consentScope));
        }
        return drafts;
    }

    /**
     * Splits {@code text} into windows of at most {@code maxChars}, preferring paragraph
     * and whitespace boundaries, with {@code overlapChars} carried into the next window.
     */
    static List<String> splitIntoWindows(
            final String text, final int maxChars, final int overlapChars) {
        if (text == null || text.isBlank()) {
            return List.of();
        }
        if (maxChars <= 0) {
            return List.of(text.trim());
        }
        final String normalized = text.trim();
        if (normalized.length() <= maxChars) {
            return List.of(normalized);
        }

        final int overlap = Math.max(0, Math.min(overlapChars, maxChars / 2));
        final List<String> windows = new ArrayList<>();
        int start = 0;
        while (start < normalized.length()) {
            int end = Math.min(start + maxChars, normalized.length());
            if (end < normalized.length()) {
                end = preferBreak(normalized, start, end);
            }
            if (end <= start) {
                end = Math.min(start + maxChars, normalized.length());
            }
            windows.add(normalized.substring(start, end).trim());
            if (end >= normalized.length()) {
                break;
            }
            final int nextStart = Math.max(0, end - overlap);
            if (nextStart <= start) {
                start = end;
            } else {
                start = nextStart;
            }
        }
        return windows.stream().filter(w -> w != null && !w.isBlank()).toList();
    }

    /** Prefer breaking on paragraph, then newline, then whitespace near {@code end}. */
    private static int preferBreak(final String text, final int start, final int end) {
        final int windowStart = Math.max(start, end - Math.min(400, (end - start) / 2));
        final int paragraph = text.lastIndexOf("\n\n", end - 1);
        if (paragraph >= windowStart) {
            return paragraph + 2;
        }
        final int newline = text.lastIndexOf('\n', end - 1);
        if (newline >= windowStart) {
            return newline + 1;
        }
        final int space = text.lastIndexOf(' ', end - 1);
        if (space >= windowStart) {
            return space + 1;
        }
        return end;
    }
}
