package com.careconnect.service.ehr;

import com.careconnect.model.ehr.EhrConditionRecord;
import com.careconnect.model.ehr.EhrReferenceValue;
import com.fasterxml.jackson.databind.JsonNode;

/** Pure mapper from a FHIR R4 Condition into the shared source-neutral persistence shape. */
public final class EhrConditionMapper {

    private EhrConditionMapper() {}

    public static EhrConditionRecord map(
            final JsonNode resource,
            final Long patientId,
            final Long sourceId,
            final Long rawPayloadId,
            final String expectedExternalPatientId) {
        requireIds(patientId, sourceId);
        CanonicalFhirMappingSupport.requireResource(
                resource, "Condition", expectedExternalPatientId);

        final var onset = CanonicalFhirMappingSupport.choice(resource, "onset");
        final var abatement = CanonicalFhirMappingSupport.choice(resource, "abatement");
        final var recorded = CanonicalFhirMappingSupport.dateTime(
                "recordedDate", resource.get("recordedDate"));
        final EhrReferenceValue recorder = CanonicalFhirMappingSupport.reference(
                resource.path("recorder"));

        final String verification = CanonicalFhirMappingSupport.conceptCode(
                resource.path("verificationStatus"));
        return EhrConditionRecord.builder()
                .patientId(patientId)
                .sourceId(sourceId)
                .rawPayloadId(rawPayloadId)
                .externalConditionId(CanonicalFhirMappingSupport.requireText(resource, "id"))
                .sourceVersionId(CanonicalFhirMappingSupport.text(resource.path("meta"), "versionId"))
                .sourceUpdatedAt(CanonicalFhirMappingSupport.sourceUpdatedAt(resource))
                .clinicalStatus(CanonicalFhirMappingSupport.conceptCode(resource.path("clinicalStatus")))
                .verificationStatus(verification)
                .severity(CanonicalFhirMappingSupport.conceptLabel(resource.path("severity")))
                .categories(CanonicalFhirMappingSupport.concepts(resource.get("category")))
                .conditionCodes(CanonicalFhirMappingSupport.concepts(resource.get("code")))
                .conditionText(CanonicalFhirMappingSupport.text(resource.path("code"), "text"))
                .bodySites(CanonicalFhirMappingSupport.concepts(resource.get("bodySite")))
                .onsetType(onset == null ? null : onset.type())
                .onsetValue(onset == null ? null : onset.value())
                .onsetPrecision(onset == null ? null : onset.precision())
                .abatementType(abatement == null ? null : abatement.type())
                .abatementValue(abatement == null ? null : abatement.value())
                .abatementPrecision(abatement == null ? null : abatement.precision())
                .recordedDate(recorded == null ? null : recorded.value())
                .recordedDatePrecision(recorded == null ? null : recorded.precision())
                .encounterReference(CanonicalFhirMappingSupport.text(
                        resource.path("encounter"), "reference"))
                .recorderReference(recorder == null ? null : recorder.reference())
                .recorderDisplay(recorder == null ? null : recorder.display())
                .hiddenFromActiveList("entered-in-error".equals(verification))
                .build();
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
