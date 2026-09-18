package com.careconnect.service.ai.ask;

import com.careconnect.dto.ai.AiCitation;
import com.careconnect.service.ai.indexing.SummarySourceKey;
import com.careconnect.service.ai.retrieval.RankedChunk;
import com.careconnect.service.ai.retrieval.RetrievalRecordType;
import org.springframework.stereotype.Component;

import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import java.util.regex.Pattern;

/**
 * Maps LLM citationRefs (C1..Cn) onto validated API citation chips (Task 5.5).
 *
 * <p>Only whitelisted chunk metadata is exposed. Deep links are record-type aware and
 * path-segment encoded. RRF scores are never reported as confidence because they are
 * rank-fusion signals, not calibrated probabilities.
 */
@Component
final class CitationAssembler {

    private static final int EXCERPT_CHARS = 240;
    private static final int SOURCE_ID_CHARS = 160;
    private static final Pattern CITATION_REF = Pattern.compile("^C[1-9][0-9]*$");

    private final CitationDeepLinkBuilder deepLinkBuilder;
    private final CitationMetadataMapper metadataMapper;

    CitationAssembler(
            final CitationDeepLinkBuilder deepLinkBuilder,
            final CitationMetadataMapper metadataMapper) {
        this.deepLinkBuilder = deepLinkBuilder;
        this.metadataMapper = metadataMapper;
    }

    private static String joinedEvidence(final List<String> windows) {
        if (windows == null || windows.isEmpty()) {
            return null;
        }
        return windows.stream()
                .filter(window -> window != null && !window.isBlank())
                .map(String::trim)
                .distinct()
                .reduce((left, right) -> left + " … " + right)
                .orElse(null);
    }

    private static String publicSourceId(
            final RankedChunk chunk,
            final String sourceKey) {
        if (sourceKey == null || chunk == null || chunk.recordType() == null) {
            return null;
        }
        if (RetrievalRecordType.summaryTypeNames().contains(chunk.recordType().name())
                && SummarySourceKey.sourceKind(sourceKey) != null) {
            return SummarySourceKey.parsePublicSummaryId(sourceKey)
                    .map(String::valueOf)
                    .orElse(null);
        }
        return sourceKey;
    }

    private static String citationSourceKind(
            final RankedChunk chunk,
            final String sourceKey) {
        if (chunk != null && chunk.sourceKind() != null && !chunk.sourceKind().isBlank()) {
            return chunk.sourceKind();
        }
        final String namespacedKind = SummarySourceKey.sourceKind(sourceKey);
        if (namespacedKind != null) {
            return namespacedKind;
        }
        if (chunk == null || chunk.recordType() == null) {
            return null;
        }
        return switch (chunk.recordType()) {
            case CALL_SUMMARY -> SummarySourceKey.CALL_KIND;
            case VISIT_SUMMARY -> SummarySourceKey.VISIT_KIND;
            default -> null;
        };
    }

    private static String validateIdentifier(final String value) {
        if (value == null
                || value.isBlank()
                || !value.equals(value.trim())
                || AskAiTextPolicy.containsBidiControl(value)) {
            return null;
        }
        if (value.codePointCount(0, value.length()) > SOURCE_ID_CHARS) {
            return null;
        }
        for (int offset = 0; offset < value.length(); ) {
            final int codePoint = value.codePointAt(offset);
            if (Character.isISOControl(codePoint) || Character.isWhitespace(codePoint)) {
                return null;
            }
            offset += Character.charCount(codePoint);
        }
        return value;
    }

    private static String normalizeAndTruncate(final String text, final int maxCodePoints) {
        if (text == null) {
            return "";
        }
        final String normalized = AskAiTextPolicy.normalize(text)
                .replaceAll("\\p{Cntrl}", " ")
                .replaceAll("\\s+", " ")
                .trim();
        final int codePoints = normalized.codePointCount(0, normalized.length());
        if (codePoints <= maxCodePoints) {
            return normalized;
        }
        final int end = normalized.offsetByCodePoints(0, maxCodePoints - 1);
        return normalized.substring(0, end).stripTrailing() + "…";
    }

    private static String normalizeVerifiedEvidence(final String text) {
        return AskAiTextPolicy.normalize(text)
                .replaceAll("\\p{Cntrl}", " ")
                .replaceAll("\\s+", " ")
                .trim();
    }

    CitationResult assemble(
            final List<String> citationRefs, final Map<String, RankedChunk> refMap) {
        return assemble(citationRefs, refMap, Map.of());
    }

    CitationResult assemble(
            final List<String> citationRefs,
            final Map<String, RankedChunk> refMap,
            final Map<String, String> evidenceByRef) {
        final Map<String, List<String>> windows = new java.util.LinkedHashMap<>();
        if (evidenceByRef != null) {
            evidenceByRef.forEach((ref, evidence) -> windows.put(
                    ref, evidence == null ? List.of() : List.of(evidence)));
        }
        return assembleWithEvidence(citationRefs, refMap, windows);
    }

    CitationResult assembleWithEvidence(
            final List<String> citationRefs,
            final Map<String, RankedChunk> refMap,
            final Map<String, List<String>> evidenceByRef) {
        if (refMap == null || refMap.isEmpty()) {
            return CitationResult.ungrounded();
        }

        final Set<String> requestedRefs = new LinkedHashSet<>();
        if (citationRefs != null) {
            for (final String ref : citationRefs) {
                if (ref != null && !ref.isBlank()) {
                    requestedRefs.add(ref.trim());
                }
            }
        }
        if (requestedRefs.isEmpty()) {
            return CitationResult.ungrounded();
        }

        final Set<String> invalidRefs = new LinkedHashSet<>();
        for (final String ref : requestedRefs) {
            if (!CITATION_REF.matcher(ref).matches() || !refMap.containsKey(ref)) {
                invalidRefs.add(ref);
            }
        }

        // Preserve retrieval relevance order, not arbitrary LLM citation order.
        final List<AiCitation> citations = new ArrayList<>(requestedRefs.size());
        final Set<UUID> seenChunks = new LinkedHashSet<>();
        for (final Map.Entry<String, RankedChunk> entry : refMap.entrySet()) {
            final String ref = entry.getKey();
            if (!requestedRefs.contains(ref)) {
                continue;
            }
            final RankedChunk chunk = entry.getValue();
            final Optional<AiCitation> citation =
                    toCitation(ref, chunk, joinedEvidence(
                            evidenceByRef == null ? null : evidenceByRef.get(ref)));
            if (citation.isEmpty()) {
                invalidRefs.add(ref);
                continue;
            }
            if (seenChunks.add(citation.get().chunkId())) {
                citations.add(citation.get());
            }
        }

        final boolean grounded = !citations.isEmpty() && invalidRefs.isEmpty();
        return new CitationResult(
                List.copyOf(citations),
                Set.copyOf(invalidRefs),
                grounded);
    }

    private Optional<AiCitation> toCitation(
            final String ref,
            final RankedChunk chunk,
            final String verifiedEvidence) {
        if (chunk == null
                || chunk.chunkId() == null
                || chunk.recordType() == null
                || !ref.equals(chunk.citationRef())) {
            return Optional.empty();
        }
        final String sourceKey = validateIdentifier(chunk.sourceRecordId());
        final String sourceKind = citationSourceKind(chunk, sourceKey);
        final String sourceId = publicSourceId(chunk, sourceKey);
        final String excerpt = verifiedEvidence == null
                ? normalizeAndTruncate(chunk.chunkText(), EXCERPT_CHARS)
                : normalizeVerifiedEvidence(verifiedEvidence);
        if (sourceId == null || excerpt.isBlank()) {
            return Optional.empty();
        }

        final CitationMetadataMapper.CitationMetadata metadata =
                metadataMapper.map(chunk.recordType(), chunk.chunkMetadata());
        final String deepLink = deepLinkBuilder.build(chunk);

        return Optional.of(new AiCitation(
                ref,
                chunk.recordType(),
                sourceKind,
                sourceId,
                chunk.chunkId(),
                metadata.title(),
                excerpt,
                metadata.occurredAt(),
                deepLink,
                metadata.confidence(),
                metadata.metadata()));
    }

    /**
     * @param citations   validated citations in retrieval relevance order
     * @param invalidRefs unknown or malformed refs, or refs whose chunk cannot form a citation
     * @param grounded    true only when at least one citation is valid and every requested ref validates
     */
    record CitationResult(List<AiCitation> citations, Set<String> invalidRefs, boolean grounded) {
        static CitationResult ungrounded() {
            return new CitationResult(List.of(), Set.of(), false);
        }
    }
}
