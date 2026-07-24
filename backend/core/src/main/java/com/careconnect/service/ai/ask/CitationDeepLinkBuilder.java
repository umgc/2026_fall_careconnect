package com.careconnect.service.ai.ask;

import com.careconnect.service.ai.indexing.SummarySourceKey;
import com.careconnect.service.ai.retrieval.RankedChunk;
import com.careconnect.service.ai.retrieval.RetrievalRecordType;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.stereotype.Component;

/**
 * Builds citation destinations registered by the Flutter router.
 *
 * <p>Paths are source-specific app routes (not generic feature pages). Identifiers are
 * validated to path-safe segments so untrusted chunk metadata cannot inject traversal.
 */
@Component
final class CitationDeepLinkBuilder {

    private final ObjectMapper objectMapper;

    CitationDeepLinkBuilder(final ObjectMapper objectMapper) {
        this.objectMapper = objectMapper;
    }

    String build(final RankedChunk chunk) {
        if (chunk == null || chunk.recordType() == null) {
            return null;
        }
        final JsonNode metadata = parseMetadata(chunk.chunkMetadata());
        return switch (chunk.recordType()) {
            case CALL_SUMMARY -> callSummaryLink(metadata, null);
            case SUMMARY_ACTION_ITEM, SUMMARY_APPOINTMENT, SUMMARY_CARE_INSTRUCTION,
                    SUMMARY_CONDITION, SUMMARY_SOAP, SUMMARY_CLINICAL_OBSERVATION,
                    MEDICATION_TIMELINE_EVENT -> summaryChildLink(chunk, metadata);
            case TRANSCRIPT_SEGMENT -> transcriptLink(metadata);
            case VISIT_SUMMARY -> visitSummaryLink(metadata, chunk.sourceRecordId());
            case CLINICAL_NOTE -> clinicalNoteLink(chunk.patientId(), chunk.sourceRecordId());
            case UPLOADED_DOCUMENT -> documentLink(chunk.sourceRecordId());
            case USPS_MAIL -> mailLink(chunk.sourceRecordId());
            default -> null;
        };
    }

    private String summaryChildLink(final RankedChunk chunk, final JsonNode metadata) {
        final String kind = chunk.sourceKind() != null
                ? chunk.sourceKind()
                : SummarySourceKey.sourceKind(chunk.sourceRecordId());
        final String itemId = textOrNull(metadata, "itemId");
        if (SummarySourceKey.VISIT_KIND.equals(kind)) {
            return visitSummaryLink(metadata, chunk.sourceRecordId());
        }
        if (SummarySourceKey.CALL_KIND.equals(kind) || textOrNull(metadata, "callId") != null) {
            return callSummaryLink(metadata, itemId);
        }
        return null;
    }

    private String callSummaryLink(final JsonNode metadata, final String itemId) {
        final String callId = pathSegment(textOrNull(metadata, "callId"));
        if (callId == null) {
            return null;
        }
        final String base = "/calls/" + callId + "/summary";
        final String fragment = pathSegment(itemId);
        return fragment == null ? base : base + "#item-" + fragment;
    }

    private String transcriptLink(final JsonNode metadata) {
        final String callId = pathSegment(textOrNull(metadata, "callId"));
        if (callId == null) {
            return null;
        }
        final String startMs = textOrNull(metadata, "startMs");
        if (startMs != null && startMs.chars().allMatch(Character::isDigit)) {
            return "/calls/" + callId + "/summary?t=" + startMs;
        }
        return "/calls/" + callId + "/summary";
    }

    private String visitSummaryLink(final JsonNode metadata, final String sourceRecordId) {
        String visitId = pathSegment(textOrNull(metadata, "visitId"));
        if (visitId == null) {
            visitId = pathSegment(SummarySourceKey.parseVisitSummaryId(sourceRecordId)
                    .map(String::valueOf)
                    .orElse(null));
        }
        if (visitId == null) {
            return null;
        }
        return "/visits/" + visitId + "/summary";
    }

    private String clinicalNoteLink(final Long patientId, final String sourceRecordId) {
        final String noteId = pathSegment(sourceRecordId);
        if (noteId == null || !noteId.chars().allMatch(Character::isDigit)) {
            return null;
        }
        if (patientId == null || patientId <= 0) {
            return "/notetaker/detail/" + noteId;
        }
        return "/notetaker/detail/" + noteId + "?patientId=" + patientId;
    }

    private String documentLink(final String sourceRecordId) {
        final String fileId = pathSegment(sourceRecordId);
        if (fileId == null || !fileId.chars().allMatch(Character::isDigit)) {
            return null;
        }
        return "/file-management?fileId=" + fileId;
    }

    private String mailLink(final String sourceRecordId) {
        final String mailId = pathSegment(sourceRecordId);
        if (mailId == null || !mailId.chars().allMatch(Character::isDigit)) {
            return null;
        }
        return "/mail/" + mailId;
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

    private static String textOrNull(final JsonNode node, final String field) {
        if (node == null) {
            return null;
        }
        final JsonNode value = node.get(field);
        if (value == null || value.isNull()) {
            return null;
        }
        final String text = value.isTextual() || value.isNumber() ? value.asText() : null;
        return text == null || text.isBlank() ? null : text.trim();
    }

    /**
     * Rejects empty, traversal, and path-separator values so deep links stay single-segment.
     */
    static String pathSegment(final String raw) {
        if (raw == null) {
            return null;
        }
        final String trimmed = raw.trim();
        if (trimmed.isEmpty()
                || trimmed.contains("/")
                || trimmed.contains("\\")
                || trimmed.contains("..")
                || trimmed.contains("#")
                || trimmed.contains("?")
                || trimmed.contains(":")) {
            return null;
        }
        return trimmed;
    }
}
