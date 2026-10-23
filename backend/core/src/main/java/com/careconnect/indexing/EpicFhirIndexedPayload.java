package com.careconnect.indexing;

/**
 * Body of the {@code EPIC_FHIR_INDEXED} event (Epic Phase 2).
 *
 * <p>Emitted after an Epic FHIR resource is upserted into {@code ehr_resource}. The worker loads
 * the authoritative {@code ehr_resource} row by id (never trusting the payload for patient
 * ownership) and re-chunks it.
 *
 * @param ehrResourceId persisted {@code ehr_resource.id}; the authoritative record to index
 * @param patientId     patient scope key for RBAC / indexing (the connecting user id)
 * @param contentHash   SHA-256 of the normalized resource for idempotent re-index
 * @param consentScope  caregiver visibility label
 */
public record EpicFhirIndexedPayload(
        Long ehrResourceId,
        Long patientId,
        String contentHash,
        String consentScope
) {
}
