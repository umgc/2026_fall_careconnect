package com.careconnect.service.ai.indexing.chunker;

import com.careconnect.service.ai.indexing.IndexingChunkDraft;
import com.careconnect.service.ai.indexing.MedicationNameNormalizer;
import com.careconnect.service.ai.retrieval.RetrievalRecordType;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

/**
 * Chunks a call/visit {@code summary_json} into overview + typed item chunks (Task 4.1 / 3.5).
 *
 * <p>Produces at least one {@link RetrievalRecordType#CALL_SUMMARY} or
 * {@link RetrievalRecordType#VISIT_SUMMARY} overview chunk, plus per-item chunks for
 * action items, appointments, care instructions, conditions, SOAP, and clinical observations.
 */
@Component
public class SummaryChunker {

    private static final Logger log = LoggerFactory.getLogger(SummaryChunker.class);
    /** Increment when citation-routing metadata requires existing summary chunks to be rebuilt. */
    public static final int CITATION_METADATA_VERSION = 1;

    private final ObjectMapper objectMapper;

    public SummaryChunker(final ObjectMapper objectMapper) {
        this.objectMapper = objectMapper;
    }

    /**
     * @param episodeType          {@code call} or {@code visit}
     * @param summaryJson          raw summary JSON text
     * @param contentHash          SHA-256 hash from SUMMARY_CREATED (may be null)
     * @param caregiverVisibility  consent / visibility label
     * @param summarizationEngine  engine string for metadata
     * @return chunk drafts; empty when JSON is blank or unparseable with no usable text
     */
    public List<IndexingChunkDraft> chunk(
            final String episodeType,
            final String summaryJson,
            final String contentHash,
            final String caregiverVisibility,
            final String summarizationEngine) {
        return chunk(
                episodeType,
                summaryJson,
                contentHash,
                caregiverVisibility,
                summarizationEngine,
                null,
                null);
    }

    /**
     * Builds summary chunks with citation-routing metadata.
     *
     * @param episodeId callId or visitId used to construct validated citation deep links
     * @param occurredAt ISO-8601 summary timestamp used in citation display metadata
     */
    public List<IndexingChunkDraft> chunk(
            final String episodeType,
            final String summaryJson,
            final String contentHash,
            final String caregiverVisibility,
            final String summarizationEngine,
            final String episodeId,
            final String occurredAt) {
        final List<IndexingChunkDraft> drafts = new ArrayList<>();
        if (summaryJson == null || summaryJson.isBlank()) {
            return drafts;
        }

        final JsonNode root;
        try {
            root = objectMapper.readTree(summaryJson);
        } catch (final Exception ex) {
            log.warn("SummaryChunker: failed to parse summary_json: {}", ex.getMessage());
            return drafts;
        }

        final RetrievalRecordType overviewType = isVisit(episodeType)
                ? RetrievalRecordType.VISIT_SUMMARY
                : RetrievalRecordType.CALL_SUMMARY;

        int chunkIndex = 0;
        final String overviewText = buildOverviewText(root);
        if (!overviewText.isBlank()) {
            drafts.add(draft(
                    overviewType,
                    overviewText,
                    chunkIndex++,
                    contentHash,
                    caregiverVisibility,
                    summarizationEngine,
                    overviewMetadata(root)));
        }

        chunkIndex = appendArrayItems(
                drafts,
                root.path("actionItems"),
                RetrievalRecordType.SUMMARY_ACTION_ITEM,
                "text",
                chunkIndex,
                contentHash,
                caregiverVisibility,
                summarizationEngine);

        chunkIndex = appendAppointments(
                drafts,
                root.path("appointments"),
                chunkIndex,
                contentHash,
                caregiverVisibility,
                summarizationEngine);

        chunkIndex = appendArrayItems(
                drafts,
                root.path("careInstructions"),
                RetrievalRecordType.SUMMARY_CARE_INSTRUCTION,
                "text",
                chunkIndex,
                contentHash,
                caregiverVisibility,
                summarizationEngine);

        chunkIndex = appendMedicationTimelineEvents(
                drafts,
                root.path("careInstructions"),
                chunkIndex,
                contentHash,
                caregiverVisibility,
                summarizationEngine);

        chunkIndex = appendArrayItems(
                drafts,
                root.path("conditions"),
                RetrievalRecordType.SUMMARY_CONDITION,
                "text",
                chunkIndex,
                contentHash,
                caregiverVisibility,
                summarizationEngine);

        final String soapText = buildSoapText(root.path("soap"));
        if (!soapText.isBlank()) {
            drafts.add(draft(
                    RetrievalRecordType.SUMMARY_SOAP,
                    soapText,
                    chunkIndex++,
                    contentHash,
                    caregiverVisibility,
                    summarizationEngine,
                    Map.of("section", "soap")));
        }

        final String observationsText = buildClinicalObservationsText(root.path("clinicalObservations"));
        if (!observationsText.isBlank()) {
            drafts.add(draft(
                    RetrievalRecordType.SUMMARY_CLINICAL_OBSERVATION,
                    observationsText,
                    chunkIndex,
                    contentHash,
                    caregiverVisibility,
                    summarizationEngine,
                    Map.of("section", "clinicalObservations")));
        }

        return enrichCitationMetadata(drafts, episodeType, episodeId, occurredAt);
    }

    private int appendArrayItems(
            final List<IndexingChunkDraft> drafts,
            final JsonNode array,
            final RetrievalRecordType recordType,
            final String textField,
            int chunkIndex,
            final String contentHash,
            final String caregiverVisibility,
            final String summarizationEngine) {
        if (array == null || !array.isArray()) {
            return chunkIndex;
        }
        for (final JsonNode item : array) {
            if (item == null || item.isNull()) {
                continue;
            }
            final String text = firstNonBlank(
                    textOrNull(item, textField),
                    textOrNull(item, "description"),
                    item.isValueNode() ? item.asText(null) : null);
            if (text == null || text.isBlank()) {
                continue;
            }
            final Map<String, Object> extra = new LinkedHashMap<>();
            extra.put("section", recordType.name().toLowerCase(Locale.ROOT));
            putIfPresent(extra, "itemId", textOrNull(item, "itemId"));
            putIfPresent(extra, "sourceTurnId", textOrNull(item, "sourceTurnId"));
            putIfPresent(extra, "type", textOrNull(item, "type"));
            putIfPresent(extra, "status", textOrNull(item, "status"));
            putConfidenceIfValid(extra, item.path("confidence"));
            drafts.add(draft(
                    recordType,
                    text.trim(),
                    chunkIndex++,
                    contentHash,
                    caregiverVisibility,
                    summarizationEngine,
                    extra));
        }
        return chunkIndex;
    }

    /**
     * FR-AI-11 / Task 4.5 — explode medication careInstructions into derived timeline events.
     */
    private int appendMedicationTimelineEvents(
            final List<IndexingChunkDraft> drafts,
            final JsonNode array,
            int chunkIndex,
            final String contentHash,
            final String caregiverVisibility,
            final String summarizationEngine) {
        if (array == null || !array.isArray()) {
            return chunkIndex;
        }
        for (final JsonNode item : array) {
            if (item == null || item.isNull()) {
                continue;
            }
            final String type = textOrNull(item, "type");
            if (type == null || !"medication".equalsIgnoreCase(type.trim())) {
                continue;
            }
            final String medicationName = firstNonBlank(
                    textOrNull(item, "medicationName"),
                    textOrNull(item, "name"),
                    textOrNull(item, "text"),
                    textOrNull(item, "description"));
            if (medicationName == null || medicationName.isBlank()) {
                continue;
            }
            final String status = firstNonBlank(textOrNull(item, "status"), "unknown");
            final String effectiveDate = firstNonBlank(
                    textOrNull(item, "effectiveDate"),
                    textOrNull(item, "date"));
            final String doseFrom = textOrNull(item, "doseFrom");
            final String doseTo = textOrNull(item, "doseTo");
            final String normalized = MedicationNameNormalizer.normalize(medicationName);
            final String chunkText = buildMedicationTimelineText(
                    medicationName, status, effectiveDate, doseFrom, doseTo);
            final Map<String, Object> extra = new LinkedHashMap<>();
            extra.put("section", "medication_timeline");
            putIfPresent(extra, "itemId", textOrNull(item, "itemId"));
            putIfPresent(extra, "sourceTurnId", textOrNull(item, "sourceTurnId"));
            putIfPresent(extra, "type", "medication");
            putIfPresent(extra, "eventType", status);
            putIfPresent(extra, "status", status);
            putIfPresent(extra, "medicationName", medicationName.trim());
            putIfPresent(extra, "medicationNameNormalized", normalized);
            putIfPresent(extra, "effectiveDate", effectiveDate);
            putIfPresent(extra, "doseFrom", doseFrom);
            putIfPresent(extra, "doseTo", doseTo);
            putIfPresent(extra, "caregiverVisibility", caregiverVisibility);
            putConfidenceIfValid(extra, item.path("confidence"));
            drafts.add(draft(
                    RetrievalRecordType.MEDICATION_TIMELINE_EVENT,
                    chunkText,
                    chunkIndex++,
                    contentHash,
                    caregiverVisibility,
                    summarizationEngine,
                    extra));
        }
        return chunkIndex;
    }

    private static String buildMedicationTimelineText(
            final String medicationName,
            final String status,
            final String effectiveDate,
            final String doseFrom,
            final String doseTo) {
        final StringBuilder sb = new StringBuilder();
        sb.append("Medication ").append(status == null ? "event" : status.trim())
                .append(": ").append(medicationName.trim());
        if (effectiveDate != null && !effectiveDate.isBlank()) {
            sb.append(" effective ").append(effectiveDate.trim());
        }
        if (doseFrom != null && !doseFrom.isBlank()) {
            sb.append("; from ").append(doseFrom.trim());
        }
        if (doseTo != null && !doseTo.isBlank()) {
            sb.append(" to ").append(doseTo.trim());
        }
        return sb.toString();
    }

    private int appendAppointments(
            final List<IndexingChunkDraft> drafts,
            final JsonNode array,
            int chunkIndex,
            final String contentHash,
            final String caregiverVisibility,
            final String summarizationEngine) {
        if (array == null || !array.isArray()) {
            return chunkIndex;
        }
        for (final JsonNode item : array) {
            if (item == null || item.isNull()) {
                continue;
            }
            final String text = buildAppointmentText(item);
            if (text.isBlank()) {
                continue;
            }
            final Map<String, Object> extra = new LinkedHashMap<>();
            extra.put("section", "appointments");
            putIfPresent(extra, "itemId", textOrNull(item, "itemId"));
            putIfPresent(extra, "sourceTurnId", textOrNull(item, "sourceTurnId"));
            putConfidenceIfValid(extra, item.path("confidence"));
            drafts.add(draft(
                    RetrievalRecordType.SUMMARY_APPOINTMENT,
                    text,
                    chunkIndex++,
                    contentHash,
                    caregiverVisibility,
                    summarizationEngine,
                    extra));
        }
        return chunkIndex;
    }

    private IndexingChunkDraft draft(
            final RetrievalRecordType recordType,
            final String chunkText,
            final int chunkIndex,
            final String contentHash,
            final String caregiverVisibility,
            final String summarizationEngine,
            final Map<String, Object> extra) {
        final Map<String, Object> metadata = new LinkedHashMap<>();
        metadata.put("chunkIndex", chunkIndex);
        if (contentHash != null && !contentHash.isBlank()) {
            metadata.put("contentHash", contentHash);
        }
        if (summarizationEngine != null && !summarizationEngine.isBlank()) {
            metadata.put("summarizationEngine", summarizationEngine);
        }
        if (extra != null) {
            metadata.putAll(extra);
        }
        if (caregiverVisibility != null && !caregiverVisibility.isBlank()) {
            metadata.putIfAbsent("caregiverVisibility", caregiverVisibility);
        }
        return new IndexingChunkDraft(recordType, chunkText, metadata, caregiverVisibility);
    }

    private static Map<String, Object> overviewMetadata(final JsonNode root) {
        final Map<String, Object> metadata = new LinkedHashMap<>();
        metadata.put("section", "overview");
        putIfPresent(metadata, "title", textOrNull(root, "headline"));
        putConfidenceIfValid(metadata, root.path("summaryConfidence"), "summaryConfidence");
        return metadata;
    }

    private static List<IndexingChunkDraft> enrichCitationMetadata(
            final List<IndexingChunkDraft> drafts,
            final String episodeType,
            final String episodeId,
            final String occurredAt) {
        if (drafts.isEmpty()) {
            return drafts;
        }
        final boolean visit = isVisit(episodeType);
        final List<IndexingChunkDraft> enriched = new ArrayList<>(drafts.size());
        for (final IndexingChunkDraft draft : drafts) {
            final Map<String, Object> metadata = new LinkedHashMap<>(draft.metadata());
            metadata.put("citationMetadataVersion", CITATION_METADATA_VERSION);
            metadata.put("episodeType", visit ? "visit" : "call");
            putIfPresent(metadata, visit ? "visitId" : "callId", episodeId);
            putIfPresent(metadata, "occurredAt", occurredAt);
            enriched.add(new IndexingChunkDraft(
                    draft.recordType(),
                    draft.chunkText(),
                    metadata,
                    draft.consentScope()));
        }
        return enriched;
    }

    private static void putConfidenceIfValid(
            final Map<String, Object> map, final JsonNode confidence) {
        putConfidenceIfValid(map, confidence, "confidence");
    }

    private static void putConfidenceIfValid(
            final Map<String, Object> map, final JsonNode confidence, final String key) {
        if (confidence != null && confidence.isNumber()) {
            final double value = confidence.asDouble();
            if (Double.isFinite(value) && value >= 0.0d && value <= 1.0d) {
                map.put(key, value);
            }
        }
    }

    private static String buildOverviewText(final JsonNode root) {
        final StringBuilder sb = new StringBuilder();
        appendLabeled(sb, "Headline", textOrNull(root, "headline"));
        appendLabeled(sb, "Overall assessment", textOrNull(root, "overallAssessment"));
        // SOAP fields are indexed separately as SUMMARY_SOAP to avoid duplicate context.

        final JsonNode concerns = root.path("keyConcerns");
        if (concerns.isArray() && !concerns.isEmpty()) {
            sb.append("Key concerns: ");
            boolean first = true;
            for (final JsonNode concern : concerns) {
                final String value = concern == null ? null : concern.asText(null);
                if (value == null || value.isBlank()) {
                    continue;
                }
                if (!first) {
                    sb.append("; ");
                }
                sb.append(value.trim());
                first = false;
            }
            sb.append('\n');
        }

        if (sb.isEmpty()) {
            // Prefer skip over dumping raw JSON (PHI / noise) into the index.
            // Item/SOAP chunks still cover structured content when present.
            return "";
        }
        return sb.toString().trim();
    }

    private static String buildSoapText(final JsonNode soap) {
        if (soap == null || soap.isMissingNode() || soap.isNull()) {
            return "";
        }
        final StringBuilder sb = new StringBuilder();
        appendLabeled(sb, "S", textOrNull(soap, "subjective"));
        appendLabeled(sb, "O", textOrNull(soap, "objective"));
        appendLabeled(sb, "A", textOrNull(soap, "assessment"));
        appendLabeled(sb, "P", textOrNull(soap, "plan"));
        appendLabeled(sb, "Risk", textOrNull(soap, "riskLevel"));
        return sb.toString().trim();
    }

    private static String buildClinicalObservationsText(final JsonNode observations) {
        if (observations == null || observations.isMissingNode() || observations.isNull()) {
            return "";
        }
        final StringBuilder sb = new StringBuilder();
        appendObservationList(sb, "Acute red flags", observations.path("acuteRedFlags"));
        appendObservationList(sb, "Symptoms", observations.path("symptomCharacterization"));
        appendObservationList(sb, "Functional status", observations.path("functionalStatus"));
        appendObservationList(sb, "Cognitive/behavioral", observations.path("cognitiveBehavioral"));
        appendObservationList(sb, "Medication-related", observations.path("medicationRelated"));
        appendObservationList(sb, "Caregiver signals", observations.path("caregiverSignals"));
        return sb.toString().trim();
    }

    private static String buildAppointmentText(final JsonNode item) {
        final StringBuilder sb = new StringBuilder();
        final String purpose = firstNonBlank(textOrNull(item, "purpose"), textOrNull(item, "text"));
        final String with = textOrNull(item, "with");
        final String date = textOrNull(item, "date");
        final String time = textOrNull(item, "time");
        if (purpose != null) {
            sb.append(purpose.trim());
        }
        if (with != null) {
            if (!sb.isEmpty()) {
                sb.append(" with ");
            }
            sb.append(with.trim());
        }
        if (date != null || time != null) {
            if (!sb.isEmpty()) {
                sb.append(" on ");
            }
            if (date != null) {
                sb.append(date.trim());
            }
            if (time != null) {
                if (date != null) {
                    sb.append(' ');
                }
                sb.append(time.trim());
            }
        }
        return sb.toString().trim();
    }

    private static void appendObservationList(
            final StringBuilder sb, final String label, final JsonNode array) {
        if (array == null || !array.isArray() || array.isEmpty()) {
            return;
        }
        sb.append(label).append(':');
        for (final JsonNode node : array) {
            if (node == null || node.isNull()) {
                continue;
            }
            final String text = node.isTextual()
                    ? node.asText()
                    : firstNonBlank(textOrNull(node, "text"), node.toString());
            if (text == null || text.isBlank()) {
                continue;
            }
            sb.append(' ').append(text.trim()).append(';');
        }
        sb.append('\n');
    }

    private static void appendLabeled(final StringBuilder sb, final String label, final String value) {
        if (value == null || value.isBlank()) {
            return;
        }
        sb.append(label).append(": ").append(value.trim()).append('\n');
    }

    private static String textOrNull(final JsonNode node, final String field) {
        if (node == null || node.isMissingNode() || node.isNull()) {
            return null;
        }
        final JsonNode child = node.path(field);
        if (child.isMissingNode() || child.isNull()) {
            return null;
        }
        final String text = child.asText(null);
        return text == null || text.isBlank() ? null : text;
    }

    private static String firstNonBlank(final String... values) {
        if (values == null) {
            return null;
        }
        for (final String value : values) {
            if (value != null && !value.isBlank()) {
                return value;
            }
        }
        return null;
    }

    private static void putIfPresent(
            final Map<String, Object> map, final String key, final String value) {
        if (value != null && !value.isBlank()) {
            map.put(key, value);
        }
    }

    private static boolean isVisit(final String episodeType) {
        return episodeType != null && episodeType.trim().equalsIgnoreCase("visit");
    }
}
