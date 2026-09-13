package com.careconnect.service.ai.indexing.chunker;

import com.careconnect.config.EpicProperties;
import com.careconnect.model.ehr.EhrResource;
import com.careconnect.service.ai.indexing.IndexingChunkDraft;
import com.careconnect.service.ai.retrieval.RetrievalRecordType;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

/**
 * Flattens one mirrored Epic FHIR resource ({@link EhrResource}) into a single retrieval chunk
 * draft (Epic Phase 2). Mirrors {@code ClinicalNoteChunker}: readable {@code chunkText} plus
 * metadata the citation layer expects ({@code contentHash}, {@code fhirResourceType},
 * {@code fhirResourceId}, {@code sourceSystem}, {@code occurredAt}, {@code title}).
 *
 * <p>The resourceType→{@link RetrievalRecordType} mapping is centralized here so the ingest path
 * uses the same key for its replacement lock.
 */
@Component
@RequiredArgsConstructor
public class EpicResourceChunker {

    /** Max chars kept from a flattened resource (stays well under the embedding input cap). */
    private static final int MAX_CHUNK_CHARS = 4000;

    private final ObjectMapper objectMapper;

    /** Map a FHIR resourceType to its Epic retrieval record type, if indexable. */
    public static Optional<RetrievalRecordType> recordTypeFor(final String resourceType) {
        if (resourceType == null) {
            return Optional.empty();
        }
        return switch (resourceType) {
            case "Condition" -> Optional.of(RetrievalRecordType.EPIC_CONDITION);
            case "MedicationRequest", "MedicationStatement", "Medication" ->
                    Optional.of(RetrievalRecordType.EPIC_MEDICATION);
            case "AllergyIntolerance" -> Optional.of(RetrievalRecordType.EPIC_ALLERGY);
            case "Observation" -> Optional.of(RetrievalRecordType.EPIC_OBSERVATION);
            case "DiagnosticReport" -> Optional.of(RetrievalRecordType.EPIC_DIAGNOSTIC_REPORT);
            case "Immunization" -> Optional.of(RetrievalRecordType.EPIC_IMMUNIZATION);
            case "Procedure" -> Optional.of(RetrievalRecordType.EPIC_PROCEDURE);
            case "DocumentReference" -> Optional.of(RetrievalRecordType.EPIC_DOCUMENT);
            default -> Optional.empty();
        };
    }

    public List<IndexingChunkDraft> chunk(final EhrResource resource, final String consentScope) {
        final List<IndexingChunkDraft> drafts = new ArrayList<>(1);
        if (resource == null) {
            return drafts;
        }
        final Optional<RetrievalRecordType> recordType = recordTypeFor(resource.getResourceType());
        if (recordType.isEmpty()) {
            return drafts;
        }
        final String chunkText = buildChunkText(resource);
        if (chunkText.isBlank()) {
            return drafts;
        }

        final Map<String, Object> metadata = new LinkedHashMap<>();
        metadata.put("sourceSystem", EpicProperties.SOURCE_EPIC);
        metadata.put("fhirResourceType", resource.getResourceType());
        metadata.put("fhirResourceId", resource.getResourceFhirId());
        if (resource.getTitle() != null) {
            metadata.put("title", resource.getTitle());
        }
        if (resource.getOccurredAt() != null) {
            metadata.put("occurredAt", resource.getOccurredAt());
        }
        if (resource.getContentHash() != null) {
            metadata.put("contentHash", resource.getContentHash());
        }

        drafts.add(new IndexingChunkDraft(recordType.get(), chunkText, metadata, consentScope));
        return drafts;
    }

    /** Build readable text: the title line plus a compact flattening of salient FHIR fields. */
    String buildChunkText(final EhrResource resource) {
        final StringBuilder sb = new StringBuilder();
        if (resource.getTitle() != null && !resource.getTitle().isBlank()) {
            sb.append(resource.getTitle().trim());
        }
        final JsonNode node = parse(resource.getPayloadJson());
        if (node != null) {
            appendIfPresent(sb, "Status", firstText(node, "clinicalStatus", "status"));
            appendIfPresent(sb, "Code", codeText(node.get("code")));
            appendIfPresent(sb, "Category", codeText(node.get("category")));
            appendIfPresent(sb, "Medication", codeText(node.get("medicationCodeableConcept")));
            appendIfPresent(sb, "Substance", codeText(node.get("code")));
            appendIfPresent(sb, "Value", valueText(node));
            appendIfPresent(sb, "Date", firstText(node,
                    "effectiveDateTime", "onsetDateTime", "authoredOn", "recordedDate", "date"));
        }
        String text = sb.toString().trim();
        if (text.length() > MAX_CHUNK_CHARS) {
            text = text.substring(0, MAX_CHUNK_CHARS);
        }
        return text;
    }

    private JsonNode parse(final String json) {
        if (json == null || json.isBlank()) {
            return null;
        }
        try {
            final JsonNode node = objectMapper.readTree(json);
            return node != null && node.isObject() ? node : null;
        } catch (final Exception ignored) {
            return null;
        }
    }

    private static void appendIfPresent(final StringBuilder sb, final String label, final String value) {
        if (value != null && !value.isBlank()) {
            if (!sb.isEmpty()) {
                sb.append('\n');
            }
            sb.append(label).append(": ").append(value.trim());
        }
    }

    /** CodeableConcept → text or first coding.display. */
    private static String codeText(final JsonNode node) {
        if (node == null || node.isNull()) {
            return null;
        }
        final JsonNode target = node.isArray() && !node.isEmpty() ? node.get(0) : node;
        if (target.hasNonNull("text")) {
            return target.get("text").asText();
        }
        final JsonNode coding = target.get("coding");
        if (coding != null && coding.isArray() && !coding.isEmpty()) {
            final JsonNode first = coding.get(0);
            if (first.hasNonNull("display")) {
                return first.get("display").asText();
            }
            if (first.hasNonNull("code")) {
                return first.get("code").asText();
            }
        }
        return null;
    }

    private static String valueText(final JsonNode node) {
        final JsonNode vq = node.get("valueQuantity");
        if (vq != null && vq.hasNonNull("value")) {
            final String unit = vq.hasNonNull("unit") ? " " + vq.get("unit").asText() : "";
            return vq.get("value").asText() + unit;
        }
        if (node.hasNonNull("valueString")) {
            return node.get("valueString").asText();
        }
        return codeText(node.get("valueCodeableConcept"));
    }

    private static String firstText(final JsonNode node, final String... fields) {
        for (final String field : fields) {
            final JsonNode v = node.get(field);
            if (v != null && !v.isNull()) {
                if (v.isTextual()) {
                    return v.asText();
                }
                // clinicalStatus is a CodeableConcept in R4.
                final String coded = codeText(v);
                if (coded != null) {
                    return coded;
                }
            }
        }
        return null;
    }
}
