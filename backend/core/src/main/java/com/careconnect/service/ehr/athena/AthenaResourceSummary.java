package com.careconnect.service.ehr.athena;

import com.fasterxml.jackson.databind.JsonNode;

/**
 * Derives the flattened {@code title} and {@code occurredAt} stored beside each mirrored resource.
 *
 * <p>Follows the Epic sync's conventions ({@code "<Type>: <label>"}, ISO timestamp taken verbatim)
 * so records from both sources read the same way in one list. It also reads the
 * {@code occurrence}/{@code performed} fields that Immunization and Procedure carry their dates in.
 */
final class AthenaResourceSummary {

    /** Scalar date fields, most clinically meaningful first. */
    private static final String[] DATE_FIELDS = {
        "effectiveDateTime", "effectiveInstant", "occurrenceDateTime", "performedDateTime",
        "onsetDateTime", "authoredOn", "recordedDate", "issued", "date", "created", "startDate"
    };

    /** Period fields whose {@code start} stands in when no scalar date is present. */
    private static final String[] PERIOD_FIELDS = {
        "effectivePeriod", "performedPeriod", "onsetPeriod", "period"
    };

    private AthenaResourceSummary() {
    }

    static String title(final String resourceType, final JsonNode resource) {
        final String label = firstNonNull(
                conceptText(resource.get("medicationCodeableConcept")),
                conceptText(resource.get("vaccineCode")),
                conceptText(resource.get("code")),
                plainText(resource.get("title")),
                plainText(resource.get("name")),
                conceptText(resource.get("description")),
                conceptText(resource.get("relationship")),
                conceptText(resource.get("type")),
                conceptText(resource.get("class")));
        return label == null ? resourceType : resourceType + ": " + label;
    }

    static String occurredAt(final JsonNode resource) {
        for (final String field : DATE_FIELDS) {
            final JsonNode value = resource.get(field);
            if (value != null && value.isTextual() && !value.asText().isBlank()) {
                return value.asText();
            }
        }
        for (final String field : PERIOD_FIELDS) {
            final JsonNode start = resource.path(field).path("start");
            if (start.isTextual() && !start.asText().isBlank()) {
                return start.asText();
            }
        }
        return null;
    }

    /** A plain string element such as CarePlan.title or CareTeam.name. */
    private static String plainText(final JsonNode node) {
        return node != null && node.isTextual() && !node.asText().isBlank() ? node.asText() : null;
    }

    /** CodeableConcept (or an array of them, or a bare Coding) to its text or first display. */
    private static String conceptText(final JsonNode node) {
        if (node == null || node.isNull()) {
            return null;
        }
        final JsonNode target = node.isArray() ? node.path(0) : node;
        if (target.path("text").isTextual() && !target.path("text").asText().isBlank()) {
            return target.path("text").asText();
        }
        final JsonNode display = target.path("coding").path(0).path("display");
        if (display.isTextual() && !display.asText().isBlank()) {
            return display.asText();
        }
        if (target.path("display").isTextual() && !target.path("display").asText().isBlank()) {
            return target.path("display").asText();
        }
        return null;
    }

    @SafeVarargs
    private static <T> T firstNonNull(final T... values) {
        for (final T value : values) {
            if (value != null) {
                return value;
            }
        }
        return null;
    }
}
