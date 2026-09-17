package com.careconnect.medicare;

import com.fasterxml.jackson.databind.JsonNode;
import java.util.Locale;
import java.util.Set;
import org.springframework.stereotype.Component;

/**
 * Drops FHIR resources that a record should never surface: cancelled, draft, or
 * entered-in-error. Applied before anything leaves {@link MedicareSource}, so the rule lives in
 * one place instead of being re-expressed as an ad-hoc {@code status=active} filter per query.
 *
 * <p>Interim, and deliberately so. Team Delta already wrote the cross-source version
 * ({@code com.careconnect.service.ehr.EhrStatusGate} on {@code feat/d-Epic-Integration}) with
 * the same blocked-status set. This copy exists only because that branch has not merged; when
 * it does, delete this class and point {@link MockMedicareSource} at theirs. Keeping the
 * blocked set identical is what makes that a deletion rather than a reconciliation.
 */
@Component
public class MedicareStatusGate {

    private static final Set<String> BLOCKED =
            Set.of("cancelled", "canceled", "draft", "entered-in-error", "nullified");

    /** @return true when the resource may be returned to a caller. */
    public boolean isAllowed(final JsonNode resource) {
        if (resource == null || resource.isNull()) {
            return false;
        }
        final String status = statusOf(resource);
        if (status != null && BLOCKED.contains(status.toLowerCase(Locale.ROOT))) {
            return false;
        }
        // verificationStatus=entered-in-error invalidates a resource whose own status looks fine.
        final String verification = codeOf(resource.get("verificationStatus"));
        return verification == null || !"entered-in-error".equalsIgnoreCase(verification);
    }

    /**
     * Best-effort single status token.
     *
     * <p>FHIR puts the status in a different field depending on resource type: {@code status} on
     * Coverage and ExplanationOfBenefit, {@code docStatus} on DocumentReference, and a
     * {@code CodeableConcept} under {@code clinicalStatus} on Condition and AllergyIntolerance.
     */
    public String statusOf(final JsonNode resource) {
        if (resource == null || resource.isNull()) {
            return null;
        }
        final JsonNode status = resource.get("status");
        if (status != null && status.isTextual()) {
            return status.asText();
        }
        final JsonNode docStatus = resource.get("docStatus");
        if (docStatus != null && docStatus.isTextual()) {
            return docStatus.asText();
        }
        return codeOf(resource.get("clinicalStatus"));
    }

    /** First {@code coding[].code} of a CodeableConcept, or null when absent. */
    private String codeOf(final JsonNode codeableConcept) {
        if (codeableConcept == null || codeableConcept.isNull()) {
            return null;
        }
        final JsonNode coding = codeableConcept.get("coding");
        if (coding == null || !coding.isArray() || coding.isEmpty()) {
            return null;
        }
        final JsonNode code = coding.get(0).get("code");
        return code != null && code.isTextual() ? code.asText() : null;
    }
}
