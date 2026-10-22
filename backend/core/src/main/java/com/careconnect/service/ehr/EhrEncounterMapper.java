package com.careconnect.service.ehr;

import com.careconnect.model.ehr.EhrCodeValue;
import com.careconnect.model.ehr.EhrEncounterParticipantValue;
import com.careconnect.model.ehr.EhrEncounterRecord;
import com.careconnect.model.ehr.EhrReferenceValue;
import com.fasterxml.jackson.databind.JsonNode;
import java.util.ArrayList;
import java.util.List;

/** Pure mapper from a FHIR R4 Encounter into the shared source-neutral persistence shape. */
public final class EhrEncounterMapper {

    private EhrEncounterMapper() {}

    public static EhrEncounterRecord map(
            final JsonNode resource,
            final Long patientId,
            final Long sourceId,
            final Long rawPayloadId,
            final String expectedExternalPatientId) {
        requireIds(patientId, sourceId);
        CanonicalFhirMappingSupport.requireResource(
                resource, "Encounter", expectedExternalPatientId);

        final String status = CanonicalFhirMappingSupport.requireText(resource, "status");
        final JsonNode encounterClass = resource.path("class");
        if (!encounterClass.isObject()) {
            throw CanonicalFhirMappingSupport.invalid("class");
        }
        final var start = CanonicalFhirMappingSupport.dateTime(
                "period.start", resource.path("period").get("start"));
        final var end = CanonicalFhirMappingSupport.dateTime(
                "period.end", resource.path("period").get("end"));
        final EhrReferenceValue serviceProvider = CanonicalFhirMappingSupport.reference(
                resource.path("serviceProvider"));

        return EhrEncounterRecord.builder()
                .patientId(patientId)
                .sourceId(sourceId)
                .rawPayloadId(rawPayloadId)
                .externalEncounterId(CanonicalFhirMappingSupport.requireText(resource, "id"))
                .sourceVersionId(CanonicalFhirMappingSupport.text(resource.path("meta"), "versionId"))
                .sourceUpdatedAt(CanonicalFhirMappingSupport.sourceUpdatedAt(resource))
                .status(status)
                .classSystem(CanonicalFhirMappingSupport.text(encounterClass, "system"))
                .classCode(CanonicalFhirMappingSupport.text(encounterClass, "code"))
                .classDisplay(CanonicalFhirMappingSupport.text(encounterClass, "display"))
                .encounterTypes(CanonicalFhirMappingSupport.concepts(resource.get("type")))
                .periodStart(start == null ? null : start.value())
                .periodStartPrecision(start == null ? null : start.precision())
                .periodEnd(end == null ? null : end.value())
                .periodEndPrecision(end == null ? null : end.precision())
                .participants(participants(resource))
                .serviceProviderReference(serviceProvider == null ? null : serviceProvider.reference())
                .serviceProviderDisplay(serviceProvider == null ? null : serviceProvider.display())
                .locations(CanonicalFhirMappingSupport.references(resource, "location", "location"))
                .reasonCodes(CanonicalFhirMappingSupport.concepts(resource.get("reasonCode")))
                .diagnosisReferences(CanonicalFhirMappingSupport.references(
                        resource, "diagnosis", "condition"))
                .appointmentReferences(CanonicalFhirMappingSupport.references(
                        resource, "appointment", null))
                .build();
    }

    private static List<EhrEncounterParticipantValue> participants(final JsonNode resource) {
        final List<EhrEncounterParticipantValue> result = new ArrayList<>();
        for (final JsonNode participant : CanonicalFhirMappingSupport.array(resource, "participant")) {
            final List<EhrCodeValue> types = CanonicalFhirMappingSupport.concepts(participant.get("type"));
            final EhrReferenceValue individual = CanonicalFhirMappingSupport.reference(
                    participant.path("individual"));
            final var start = CanonicalFhirMappingSupport.dateTime(
                    "participant.period.start", participant.path("period").get("start"));
            final var end = CanonicalFhirMappingSupport.dateTime(
                    "participant.period.end", participant.path("period").get("end"));
            result.add(new EhrEncounterParticipantValue(
                    types,
                    individual == null ? null : individual.reference(),
                    individual == null ? null : individual.display(),
                    start == null ? null : start.value(),
                    end == null ? null : end.value()));
        }
        return List.copyOf(result);
    }

    private static void requireIds(final Long patientId, final Long sourceId) {
        if (patientId == null || patientId <= 0) {
            throw CanonicalFhirMappingSupport.invalid("patientId");
        }
        if (sourceId == null || sourceId <= 0) {
            throw CanonicalFhirMappingSupport.invalid("sourceId");
        }
    }
}
