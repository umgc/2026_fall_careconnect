package com.careconnect.service.ai.ask;

import com.careconnect.dto.ai.AiCitation;
import com.careconnect.service.ai.retrieval.RankedChunk;

import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * Maps LLM citationRefs (C1..Cn) onto API citation chips (Task 5.3 / 5.5).
 */
final class CitationAssembler {

    private static final int EXCERPT_CHARS = 240;

    private CitationAssembler() {
    }

    static List<AiCitation> assemble(
            final List<String> citationRefs, final Map<String, RankedChunk> refMap) {
        if (refMap == null || refMap.isEmpty()) {
            return List.of();
        }

        final Set<String> orderedRefs = new LinkedHashSet<>();
        if (citationRefs != null) {
            for (final String ref : citationRefs) {
                if (ref != null && !ref.isBlank() && refMap.containsKey(ref.trim())) {
                    orderedRefs.add(ref.trim());
                }
            }
        }
        if (orderedRefs.isEmpty()) {
            orderedRefs.addAll(refMap.keySet());
        }

        final List<AiCitation> out = new ArrayList<>(orderedRefs.size());
        for (final String ref : orderedRefs) {
            final RankedChunk chunk = refMap.get(ref);
            if (chunk == null) {
                continue;
            }
            out.add(toCitation(chunk));
        }
        return List.copyOf(out);
    }

    static AiCitation toCitation(final RankedChunk chunk) {
        final String typeName = chunk.recordType() == null ? "RECORD" : chunk.recordType().name();
        final String sourceId = chunk.sourceRecordId() == null ? "" : chunk.sourceRecordId();
        final String title = typeName + (sourceId.isBlank() ? "" : " #" + sourceId);
        final String deepLink = "careconnect://record/" + typeName
                + (sourceId.isBlank() ? "" : "/" + sourceId);
        return new AiCitation(
                chunk.citationRef(),
                chunk.recordType(),
                chunk.sourceRecordId(),
                chunk.chunkId(),
                title,
                truncate(chunk.chunkText(), EXCERPT_CHARS),
                deepLink,
                chunk.rrfScore());
    }

    private static String truncate(final String text, final int maxChars) {
        if (text == null) {
            return "";
        }
        final String trimmed = text.trim();
        if (trimmed.length() <= maxChars) {
            return trimmed;
        }
        return trimmed.substring(0, maxChars) + "…";
    }
}
