package com.careconnect.client.ehr;

import com.fasterxml.jackson.databind.JsonNode;
import java.util.List;

/**
 * Shared contract every EHR source adapter implements, per
 * {@code EHR_Canonical_Schema_Draft.md}: "a new source means a new adapter, not a new schema."
 *
 * <p>Adapters return raw FHIR resources as parsed JSON, unmapped. Mapping into canonical entities
 * (for example {@link com.careconnect.model.ehr.EhrAppointmentRecord}) is shared logic that lives
 * one layer up, so it is written and tested once instead of once per source.
 *
 * <p>{@link #fetchResources} is resource-type-agnostic rather than one method per FHIR resource
 * (no {@code fetchAppointments}, {@code fetchCoverage}, ...): a source-specific adapter otherwise
 * has to implement a method for every resource type any canonical table ever needs, even ones it
 * doesn't report. This mirrors {@link com.careconnect.model.ehr.EhrRawPayload#getResourceType()},
 * which already tags one shared raw-payload table by resource type instead of having one table
 * per type.
 */
public interface EhrApiClient {

    /** The stable {@code ehr_source.code} this adapter integrates, for example {@code "ATHENAHEALTH"}. */
    String sourceCode();

    /**
     * Fetches this patient's FHIR resources of the given type from the source.
     *
     * <p>For {@code resourceType = "Patient"}, {@code externalPatientId} is the resource's own
     * id and the implementation must fetch it directly (FHIR {@code GET /Patient/{id}}), since
     * {@code Patient} has no {@code ?patient=} search — it isn't a resource that references a
     * patient, it is one. Every other resource type (for example {@code "Appointment"},
     * {@code "Coverage"}, {@code "ExplanationOfBenefit"}) is a patient-compartment resource
     * fetched by the standard {@code ?patient=<id>} search.
     *
     * @param resourceType the FHIR resource type to fetch
     * @param externalPatientId the source's own identifier for the patient (from
     *     {@link com.careconnect.model.ehr.EhrPatientCrosswalk}), not CareConnect's internal id
     * @return the raw resources of that type, in no particular order
     */
    List<JsonNode> fetchResources(String resourceType, String externalPatientId);
}
