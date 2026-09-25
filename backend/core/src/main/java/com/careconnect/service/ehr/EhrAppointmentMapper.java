package com.careconnect.service.ehr;

import com.careconnect.model.Patient;
import com.careconnect.model.ehr.EhrAppointmentRecord;
import com.careconnect.model.ehr.EhrRawPayload;
import com.careconnect.model.ehr.EhrSource;
import com.fasterxml.jackson.databind.JsonNode;
import java.time.LocalDateTime;
import java.time.OffsetDateTime;

/**
 * Maps one raw FHIR {@code Appointment} resource into an {@link EhrAppointmentRecord}.
 *
 * <p>Isolated from {@link EhrAppointmentSyncService} so the FHIR-shape knowledge is independently
 * unit-testable against sample resource JSON, without a database or HTTP call in the loop.
 */
final class EhrAppointmentMapper {

    private EhrAppointmentMapper() {
    }

    static EhrAppointmentRecord map(
            final JsonNode resource,
            final Patient patient,
            final EhrSource source,
            final EhrRawPayload rawPayload) {
        return EhrAppointmentRecord.builder()
                .patient(patient)
                .source(source)
                .rawPayload(rawPayload)
                .externalAppointmentId(requireText(resource, "id"))
                .status(text(resource, "status"))
                .startTime(dateTime(resource, "start"))
                .endTime(dateTime(resource, "end"))
                .providerName(participantDisplay(resource, "Practitioner"))
                .location(participantDisplay(resource, "Location"))
                .serviceType(firstCodeableConceptDisplay(resource.get("serviceType")))
                .reason(reason(resource))
                .sourceCreatedAt(dateTime(resource, "created"))
                .sourceUpdatedAt(metaLastUpdated(resource))
                .build();
    }

    private static String requireText(final JsonNode node, final String field) {
        final String value = text(node, field);
        if (value == null) {
            throw new IllegalArgumentException(
                    "FHIR Appointment resource missing required field: " + field);
        }
        return value;
    }

    private static String text(final JsonNode node, final String field) {
        if (node == null) {
            return null;
        }
        final JsonNode value = node.get(field);
        return value == null || value.isNull() ? null : value.asText();
    }

    private static LocalDateTime dateTime(final JsonNode node, final String field) {
        final String raw = text(node, field);
        return raw == null ? null : OffsetDateTime.parse(raw).toLocalDateTime();
    }

    private static LocalDateTime metaLastUpdated(final JsonNode resource) {
        return dateTime(resource.get("meta"), "lastUpdated");
    }

    private static String participantDisplay(final JsonNode resource, final String actorType) {
        final JsonNode participants = resource.get("participant");
        if (participants == null || !participants.isArray()) {
            return null;
        }
        for (final JsonNode participant : participants) {
            final JsonNode actor = participant.get("actor");
            final String reference = text(actor, "reference");
            if (reference != null && reference.startsWith(actorType + "/")) {
                return text(actor, "display");
            }
        }
        return null;
    }

    private static String reason(final JsonNode resource) {
        final JsonNode reasonCodes = resource.get("reasonCode");
        if (reasonCodes == null || !reasonCodes.isArray() || reasonCodes.isEmpty()) {
            return null;
        }
        final JsonNode first = reasonCodes.get(0);
        final String freeText = text(first, "text");
        return freeText != null ? freeText : firstCodeableConceptDisplay(first);
    }

    private static String firstCodeableConceptDisplay(final JsonNode codeableConceptOrArray) {
        if (codeableConceptOrArray == null) {
            return null;
        }
        final JsonNode codeableConcept = codeableConceptOrArray.isArray()
                ? (codeableConceptOrArray.isEmpty() ? null : codeableConceptOrArray.get(0))
                : codeableConceptOrArray;
        if (codeableConcept == null) {
            return null;
        }
        final JsonNode coding = codeableConcept.get("coding");
        if (coding == null || !coding.isArray() || coding.isEmpty()) {
            return null;
        }
        return text(coding.get(0), "display");
    }
}
