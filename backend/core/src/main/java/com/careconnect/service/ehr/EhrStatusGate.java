package com.careconnect.service.ehr;

import com.fasterxml.jackson.databind.JsonNode;
import org.springframework.stereotype.Component;

import java.util.Set;

/**
 * Cross-source status gate (Findings R3): excludes {@code cancelled} / {@code draft} /
 * {@code entered-in-error} FHIR resources <b>before</b> mapping or indexing, replacing ad-hoc
 * per-query {@code status=active} filters with one enforced rule. Epic clinical resources carry
 * the status in {@code status}, {@code clinicalStatus}, {@code verificationStatus}, or
 * {@code docStatus} depending on type.
 */
@Component
public class EhrStatusGate {

    private static final Set<String> BLOCKED = Set.of(
            "cancelled", "canceled", "draft", "entered-in-error", "nullified");

    /** @return true when the resource may be mirrored/indexed. */
    public boolean isAllowed(final JsonNode resource) {
        if (resource == null) {
            return false;
        }
        final String status = statusOf(resource);
        if (status != null && BLOCKED.contains(status.toLowerCase())) {
            return false;
        }
        // verificationStatus=entered-in-error invalidates a Condition/AllergyIntolerance.
        final String verification = codeOf(resource.get("verificationStatus"));
        return verification == null || !"entered-in-error".equalsIgnoreCase(verification);
    }

    /** Best-effort single status token used both for gating and for storage. */
    public String statusOf(final JsonNode resource) {
        if (resource == null) {
            return null;
        }
        if (resource.hasNonNull("status") && resource.get("status").isTextual()) {
            return resource.get("status").asText();
        }
        final String docStatus = resource.hasNonNull("docStatus") && resource.get("docStatus").isTextual()
                ? resource.get("docStatus").asText() : null;
        if (docStatus != null) {
            return docStatus;
        }
        return codeOf(resource.get("clinicalStatus"));
    }

    /** CodeableConcept → first coding.code. */
    private static String codeOf(final JsonNode node) {
        if (node == null || node.isNull()) {
            return null;
        }
        if (node.isTextual()) {
            return node.asText();
        }
        final JsonNode coding = node.get("coding");
        if (coding != null && coding.isArray() && !coding.isEmpty()) {
            final JsonNode first = coding.get(0);
            if (first.hasNonNull("code")) {
                return first.get("code").asText();
            }
        }
        return null;
    }
}
