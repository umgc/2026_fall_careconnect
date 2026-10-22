package com.careconnect.service.ehr;

import com.careconnect.model.ehr.EhrCodeValue;
import com.careconnect.model.ehr.EhrReferenceValue;
import com.fasterxml.jackson.databind.JsonNode;
import java.time.DateTimeException;
import java.time.Instant;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.time.Year;
import java.time.YearMonth;
import java.util.ArrayList;
import java.util.List;

/** Shared, source-neutral FHIR parsing rules used by canonical record mappers. */
final class CanonicalFhirMappingSupport {

    private CanonicalFhirMappingSupport() {}

    record TemporalValue(String type, String value, String precision) {}

    static void requireResource(
            final JsonNode resource,
            final String expectedType,
            final String expectedExternalPatientId) {
        if (resource == null || !expectedType.equals(text(resource, "resourceType"))) {
            throw invalid("resourceType");
        }
        requireText(resource, "id");
        if (expectedExternalPatientId == null || expectedExternalPatientId.isBlank()) {
            throw invalid("expectedExternalPatientId");
        }
        final String expected = "Patient/" + expectedExternalPatientId;
        if (!expected.equals(text(resource.path("subject"), "reference"))) {
            throw invalid("subject.reference");
        }
    }

    static String requireText(final JsonNode node, final String field) {
        final String value = text(node, field);
        if (value == null || value.isBlank()) {
            throw invalid(field);
        }
        return value;
    }

    static String text(final JsonNode node, final String field) {
        if (node == null || !node.isObject()) {
            return null;
        }
        final JsonNode value = node.get(field);
        return value == null || value.isNull() || !value.isValueNode() ? null : value.asText();
    }

    static List<JsonNode> array(final JsonNode node, final String field) {
        if (node == null || !node.isObject()) {
            return List.of();
        }
        final JsonNode value = node.get(field);
        if (value == null || value.isNull()) {
            return List.of();
        }
        if (!value.isArray()) {
            throw invalid(field);
        }
        final List<JsonNode> values = new ArrayList<>();
        value.forEach(values::add);
        return List.copyOf(values);
    }

    static String conceptCode(final JsonNode concept) {
        final List<JsonNode> coding = array(concept, "coding");
        return coding.isEmpty() ? null : text(coding.get(0), "code");
    }

    static String conceptLabel(final JsonNode concept) {
        final String conceptText = text(concept, "text");
        if (conceptText != null) {
            return conceptText;
        }
        final List<JsonNode> coding = array(concept, "coding");
        if (coding.isEmpty()) {
            return null;
        }
        final String display = text(coding.get(0), "display");
        return display != null ? display : text(coding.get(0), "code");
    }

    static List<EhrCodeValue> concepts(final JsonNode conceptOrArray) {
        if (conceptOrArray == null || conceptOrArray.isNull()) {
            return List.of();
        }
        final List<JsonNode> concepts;
        if (conceptOrArray.isArray()) {
            concepts = new ArrayList<>();
            conceptOrArray.forEach(concepts::add);
        } else if (conceptOrArray.isObject()) {
            concepts = List.of(conceptOrArray);
        } else {
            throw invalid("CodeableConcept");
        }
        final List<EhrCodeValue> result = new ArrayList<>();
        for (final JsonNode concept : concepts) {
            final String conceptText = text(concept, "text");
            final List<JsonNode> codings = array(concept, "coding");
            if (codings.isEmpty() && conceptText != null) {
                result.add(new EhrCodeValue(null, null, null, conceptText));
            }
            for (final JsonNode coding : codings) {
                result.add(new EhrCodeValue(
                        text(coding, "system"),
                        text(coding, "code"),
                        text(coding, "display"),
                        conceptText));
            }
        }
        return List.copyOf(result);
    }

    static EhrReferenceValue reference(final JsonNode node) {
        if (node == null || !node.isObject()) {
            return null;
        }
        final String reference = text(node, "reference");
        final String display = text(node, "display");
        return reference == null && display == null ? null : new EhrReferenceValue(reference, display);
    }

    static List<EhrReferenceValue> references(
            final JsonNode containingNode, final String arrayField, final String nestedField) {
        final List<EhrReferenceValue> result = new ArrayList<>();
        for (final JsonNode item : array(containingNode, arrayField)) {
            final EhrReferenceValue value = reference(
                    nestedField == null ? item : item.path(nestedField));
            if (value != null) {
                result.add(value);
            }
        }
        return List.copyOf(result);
    }

    static Instant sourceUpdatedAt(final JsonNode resource) {
        final String value = text(resource.path("meta"), "lastUpdated");
        if (value == null) {
            return null;
        }
        try {
            return OffsetDateTime.parse(value).toInstant();
        } catch (DateTimeException error) {
            throw invalid("meta.lastUpdated");
        }
    }

    static TemporalValue dateTime(final String type, final JsonNode value) {
        if (value == null || value.isNull()) {
            return null;
        }
        if (!value.isTextual()) {
            throw invalid(type);
        }
        final String raw = value.textValue();
        try {
            if (raw.matches("\\d{4}")) {
                Year.parse(raw);
                return new TemporalValue(type, raw, "YEAR");
            }
            if (raw.matches("\\d{4}-\\d{2}")) {
                YearMonth.parse(raw);
                return new TemporalValue(type, raw, "MONTH");
            }
            if (raw.matches("\\d{4}-\\d{2}-\\d{2}")) {
                LocalDate.parse(raw);
                return new TemporalValue(type, raw, "DAY");
            }
            return new TemporalValue(type, OffsetDateTime.parse(raw).toInstant().toString(), "INSTANT");
        } catch (DateTimeException error) {
            throw invalid(type);
        }
    }

    static TemporalValue choice(final JsonNode resource, final String prefix) {
        for (final String suffix : List.of("DateTime", "String", "Age", "Period", "Range")) {
            final String field = prefix + suffix;
            final JsonNode value = resource.get(field);
            if (value == null || value.isNull()) {
                continue;
            }
            if ("DateTime".equals(suffix)) {
                return dateTime(field, value);
            }
            return new TemporalValue(suffix.toUpperCase(),
                    value.isTextual() ? value.textValue() : value.toString(), null);
        }
        return null;
    }

    static IllegalArgumentException invalid(final String field) {
        return new IllegalArgumentException("Invalid canonical FHIR field: " + field);
    }
}
