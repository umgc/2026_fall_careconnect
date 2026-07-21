package com.careconnect.service.ai.ask;

import com.careconnect.service.ai.retrieval.RetrievalRecordType;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.stereotype.Component;

import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.LinkedHashMap;
import java.util.Map;

/** Parses untrusted chunk metadata into the small, typed surface used by API citations. */
@Component
final class CitationMetadataMapper {

    private static final int TITLE_CHARS = 120;
    private static final int METADATA_STRING_CHARS = 160;

    private final ObjectMapper objectMapper;

    CitationMetadataMapper(final ObjectMapper objectMapper) {
        this.objectMapper = objectMapper;
    }

    CitationMetadata map(
            final RetrievalRecordType recordType,
            final String metadataJson) {
        final JsonNode source = parseMetadata(metadataJson);
        final Instant occurredAt = extractOccurredAt(source);
        return new CitationMetadata(
                buildTitle(recordType, source, occurredAt),
                occurredAt,
                extractConfidence(source),
                whitelistedMetadata(recordType, source));
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
            final RetrievalRecordType type, final JsonNode source) {
        final Map<String, Object> metadata = new LinkedHashMap<>();
        copyText(source, metadata, "section", "section");
        copyText(source, metadata, "itemId", "itemId");
        copyText(source, metadata, "sourceTurnId", "sourceTurnId");

        switch (type) {
            case TRANSCRIPT_SEGMENT -> {
                copyText(source, metadata, "callId", "callId");
                copyNumber(source, metadata, "segmentId", "segmentId");
                copyText(source, metadata, "speakerLabel", "speaker");
                copyNumber(source, metadata, "startMs", "startMs");
                copyNumber(source, metadata, "endMs", "endMs");
                copyText(source, metadata, "source", "source");
            }
            case CALL_SUMMARY, SUMMARY_ACTION_ITEM, SUMMARY_APPOINTMENT,
                    SUMMARY_CARE_INSTRUCTION, SUMMARY_CONDITION, SUMMARY_SOAP,
                    SUMMARY_CLINICAL_OBSERVATION -> {
                copyText(source, metadata, "callId", "callId");
                copyText(source, metadata, "episodeType", "episodeType");
            }
            case VISIT_SUMMARY -> {
                copyText(source, metadata, "visitId", "visitId");
                copyText(source, metadata, "episodeType", "episodeType");
            }
            case USPS_MAIL -> {
                copyText(source, metadata, "digestDate", "digestDate");
                copyText(source, metadata, "importanceLevel", "importanceLevel");
                copyText(source, metadata, "importanceCategory", "importanceCategory");
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
                    return LocalDateTime.parse(raw).toInstant(ZoneOffset.UTC);
                } catch (final Exception ignoredLocalDateTime) {
                    try {
                        return LocalDate.parse(raw).atStartOfDay().toInstant(ZoneOffset.UTC);
                    } catch (final Exception ignoredDate) {
                        return null;
                    }
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

    record CitationMetadata(
            String title,
            Instant occurredAt,
            Double confidence,
            Map<String, Object> metadata) {
    }
}
