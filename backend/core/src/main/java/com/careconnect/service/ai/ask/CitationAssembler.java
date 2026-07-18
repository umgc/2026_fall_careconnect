package com.careconnect.service.ai.ask;

import com.careconnect.dto.ai.AiCitation;
import com.careconnect.service.ai.retrieval.RankedChunk;
import com.careconnect.service.ai.retrieval.RetrievalRecordType;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.stereotype.Component;

import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.LinkedHashMap;
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
    private static final int TITLE_CHARS = 120;
    private static final int METADATA_STRING_CHARS = 160;
    private static final Pattern CITATION_REF = Pattern.compile("^C[1-9][0-9]*$");

    private final ObjectMapper objectMapper;

    CitationAssembler(final ObjectMapper objectMapper) {
        this.objectMapper = objectMapper;
    }

    CitationResult assemble(
            final List<String> citationRefs, final Map<String, RankedChunk> refMap) {
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
            final Optional<AiCitation> citation = toCitation(ref, chunk);
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

    private Optional<AiCitation> toCitation(final String ref, final RankedChunk chunk) {
        if (chunk == null
                || chunk.chunkId() == null
                || chunk.recordType() == null
                || !ref.equals(chunk.citationRef())) {
            return Optional.empty();
        }
        final String sourceId = normalizeIdentifier(chunk.sourceRecordId());
        final String excerpt = normalizeAndTruncate(chunk.chunkText(), EXCERPT_CHARS);
        if (sourceId == null || excerpt.isBlank()) {
            return Optional.empty();
        }

        final JsonNode metadataNode = parseMetadata(chunk.chunkMetadata());
        final Instant occurredAt = extractOccurredAt(metadataNode);
        final Map<String, Object> metadata = whitelistedMetadata(chunk.recordType(), metadataNode);
        final String title = buildTitle(chunk.recordType(), metadataNode, occurredAt);
        final String deepLink = buildDeepLink(chunk, sourceId, metadataNode);
        final Double confidence = extractConfidence(metadataNode);

        return Optional.of(new AiCitation(
                ref,
                chunk.recordType(),
                sourceId,
                chunk.chunkId(),
                title,
                excerpt,
                occurredAt,
                deepLink,
                confidence,
                metadata));
    }

    private JsonNode parseMetadata(final String metadataJson) {
        if (metadataJson == null || metadataJson.isBlank()) {
            return objectMapper.createObjectNode();
        }
        try {
            final JsonNode node = objectMapper.readTree(metadataJson);
            return node != null && node.isObject() ? node : objectMapper.createObjectNode();
        } catch (final Exception ignored) {
            return objectMapper.createObjectNode();
        }
    }

    private static Map<String, Object> whitelistedMetadata(
            final RetrievalRecordType type, final JsonNode metadataNode) {
        final Map<String, Object> metadata = new LinkedHashMap<>();
        copyText(metadataNode, metadata, "section", "section");
        copyText(metadataNode, metadata, "itemId", "itemId");
        copyText(metadataNode, metadata, "sourceTurnId", "sourceTurnId");

        switch (type) {
            case TRANSCRIPT_SEGMENT -> {
                copyText(metadataNode, metadata, "callId", "callId");
                copyText(metadataNode, metadata, "segmentId", "segmentId");
                copyText(metadataNode, metadata, "speakerLabel", "speaker");
                copyNumber(metadataNode, metadata, "startMs", "startMs");
                copyNumber(metadataNode, metadata, "endMs", "endMs");
                copyText(metadataNode, metadata, "source", "source");
            }
            case CALL_SUMMARY, SUMMARY_ACTION_ITEM, SUMMARY_APPOINTMENT,
                    SUMMARY_CARE_INSTRUCTION, SUMMARY_CONDITION, SUMMARY_SOAP,
                    SUMMARY_CLINICAL_OBSERVATION -> {
                copyText(metadataNode, metadata, "callId", "callId");
                copyText(metadataNode, metadata, "episodeType", "episodeType");
            }
            case VISIT_SUMMARY -> {
                copyText(metadataNode, metadata, "visitId", "visitId");
                copyText(metadataNode, metadata, "episodeType", "episodeType");
            }
            case USPS_MAIL -> {
                copyText(metadataNode, metadata, "digestDate", "digestDate");
                copyText(metadataNode, metadata, "importanceLevel", "importanceLevel");
                copyText(metadataNode, metadata, "importanceCategory", "importanceCategory");
            }
            default -> {
                // No additional metadata is safe or required for this record type.
            }
        }
        return Map.copyOf(metadata);
    }

    private static void copyText(
            final JsonNode source,
            final Map<String, Object> target,
            final String sourceKey,
            final String targetKey) {
        final JsonNode value = source.path(sourceKey);
        if (!value.isTextual()) {
            return;
        }
        final String normalized = normalizeAndTruncate(value.asText(), METADATA_STRING_CHARS);
        if (!normalized.isBlank()) {
            target.put(targetKey, normalized);
        }
    }

    private static void copyNumber(
            final JsonNode source,
            final Map<String, Object> target,
            final String sourceKey,
            final String targetKey) {
        final JsonNode value = source.path(sourceKey);
        if (value.isIntegralNumber() && value.canConvertToLong() && value.asLong() >= 0) {
            target.put(targetKey, value.asLong());
        }
    }

    private static String buildTitle(
            final RetrievalRecordType type, final JsonNode metadata, final Instant occurredAt) {
        final String supplied = firstText(metadata, "title", "headline");
        if (supplied != null) {
            return normalizeAndTruncate(supplied, TITLE_CHARS);
        }
        final String label = switch (type) {
            case TRANSCRIPT_SEGMENT -> "Call transcript";
            case CALL_SUMMARY -> "Call summary";
            case VISIT_SUMMARY -> "Visit summary";
            case UPLOADED_DOCUMENT -> "Uploaded document";
            case CLINICAL_NOTE -> "Clinical note";
            case USPS_MAIL -> "USPS mail";
            case SUMMARY_ACTION_ITEM -> "Summary action item";
            case SUMMARY_APPOINTMENT -> "Summary appointment";
            case SUMMARY_CARE_INSTRUCTION -> "Care instruction";
            case SUMMARY_CONDITION -> "Summary condition";
            case SUMMARY_SOAP -> "SOAP summary";
            case SUMMARY_CLINICAL_OBSERVATION -> "Clinical observation";
            case MEDICATION -> "Medication";
            case TASK -> "Task";
            case EVV_RECORD -> "Visit record";
            case VITAL_SIGN -> "Vital sign";
        };
        return occurredAt == null ? label : label + " — " + occurredAt.toString().substring(0, 10);
    }

    private static String buildDeepLink(
            final RankedChunk chunk, final String sourceId, final JsonNode metadata) {
        final String encodedSourceId = encodePathSegment(sourceId);
        return switch (chunk.recordType()) {
            case TRANSCRIPT_SEGMENT -> {
                final String callId = firstNonBlank(firstText(metadata, "callId"), sourceId);
                final String base = "/calls/" + encodePathSegment(callId) + "/transcript";
                final JsonNode startMs = metadata.path("startMs");
                yield startMs.isIntegralNumber() && startMs.asLong() >= 0
                        ? base + "?t=" + startMs.asLong()
                        : base;
            }
            case CALL_SUMMARY -> {
                final String callId = firstText(metadata, "callId");
                yield callId == null ? null
                        : "/calls/" + encodePathSegment(callId) + "/summary";
            }
            case VISIT_SUMMARY -> {
                final String visitId = firstText(metadata, "visitId");
                yield visitId == null ? null
                        : "/visits/" + encodePathSegment(visitId) + "/summary";
            }
            case SUMMARY_ACTION_ITEM, SUMMARY_APPOINTMENT, SUMMARY_CARE_INSTRUCTION,
                    SUMMARY_CONDITION, SUMMARY_SOAP, SUMMARY_CLINICAL_OBSERVATION -> {
                final String callId = firstText(metadata, "callId");
                if (callId == null) {
                    yield null;
                }
                final String itemId = firstText(metadata, "itemId");
                final String base = "/calls/" + encodePathSegment(callId) + "/summary";
                yield itemId == null ? base : base + "#item-" + encodeFragment(itemId);
            }
            case UPLOADED_DOCUMENT -> "/files/" + encodedSourceId;
            case CLINICAL_NOTE -> chunk.patientId() == null || chunk.patientId() <= 0
                    ? null
                    : "/patients/" + chunk.patientId() + "/notes/" + encodedSourceId;
            case USPS_MAIL -> "/mail/" + encodedSourceId;
            case MEDICATION -> "/medication";
            case TASK -> "/tasks";
            case EVV_RECORD -> "/evv/visit-history";
            case VITAL_SIGN -> "/wearables";
        };
    }

    private static Double extractConfidence(final JsonNode metadata) {
        final JsonNode node = metadata.hasNonNull("confidence")
                ? metadata.get("confidence")
                : metadata.get("summaryConfidence");
        if (node == null || !node.isNumber()) {
            return null;
        }
        final double value = node.asDouble();
        return Double.isFinite(value) && value >= 0.0d && value <= 1.0d ? value : null;
    }

    private static Instant extractOccurredAt(final JsonNode metadata) {
        final String raw = firstText(metadata, "occurredAt", "generatedAt", "digestDate");
        if (raw == null) {
            return null;
        }
        try {
            return Instant.parse(raw);
        } catch (final Exception ignored) {
            try {
                return OffsetDateTime.parse(raw).toInstant();
            } catch (final Exception ignoredAgain) {
                try {
                    return LocalDate.parse(raw).atStartOfDay().toInstant(ZoneOffset.UTC);
                } catch (final Exception ignoredDate) {
                    return null;
                }
            }
        }
    }

    private static String firstText(final JsonNode node, final String... fieldNames) {
        for (final String fieldName : fieldNames) {
            final JsonNode value = node.path(fieldName);
            if (value.isTextual() && !value.asText().isBlank()) {
                return value.asText().trim();
            }
        }
        return null;
    }

    private static String normalizeIdentifier(final String value) {
        if (value == null) {
            return null;
        }
        final String normalized = normalizeAndTruncate(value, METADATA_STRING_CHARS);
        return normalized.isBlank() ? null : normalized;
    }

    private static String normalizeAndTruncate(final String text, final int maxCodePoints) {
        if (text == null) {
            return "";
        }
        final String normalized = text
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

    private static String firstNonBlank(final String first, final String fallback) {
        return first == null || first.isBlank() ? fallback : first;
    }

    private static String encodePathSegment(final String value) {
        return URLEncoder.encode(value, StandardCharsets.UTF_8).replace("+", "%20");
    }

    private static String encodeFragment(final String value) {
        return encodePathSegment(value);
    }

    /**
     * @param citations validated citations in retrieval relevance order
     * @param invalidRefs unknown or malformed refs, or refs whose chunk cannot form a citation
     * @param grounded true only when at least one citation is valid and every requested ref validates
     */
    record CitationResult(List<AiCitation> citations, Set<String> invalidRefs, boolean grounded) {
        static CitationResult ungrounded() {
            return new CitationResult(List.of(), Set.of(), false);
        }
    }
}
