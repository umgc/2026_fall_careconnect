package com.careconnect.integration.cerner;

import com.fasterxml.jackson.databind.JsonNode;

import java.time.Instant;
import java.time.OffsetDateTime;
import java.time.format.DateTimeParseException;
import java.util.ArrayList;
import java.util.List;

/**
 * Pure, offline mapper from a Cerner FHIR R4 AllergyIntolerance searchset Bundle
 * to provisional normalized records (M3 MAP scenarios). Output shape is provisional
 * until OpenAPI 1.0 is approved.
 */
public final class CernerAllergyMapper {

    public static final String SOURCE = "CERNER";

    public record Allergy(String source, String sourceRecordId, String substanceText, String substanceCode,
                          String clinicalStatus, String verificationStatus, String severity,
                          String recordedDate, List<String> reactions) {
    }

    private CernerAllergyMapper() {
    }

    /**
     * @param bundle              FHIR searchset Bundle
     * @param authorizedPatientId server-controlled patient logical id
     * @return mapped records; malformed entries are isolated (skipped), entered-in-error excluded
     * @throws IllegalArgumentException if the bundle is invalid or an entry belongs to another patient
     */
    public static List<Allergy> map(JsonNode bundle, String authorizedPatientId) {
        if (bundle == null || !"Bundle".equals(bundle.path("resourceType").asText())) {
            throw new IllegalArgumentException("Invalid Bundle");
        }
        final List<Allergy> result = new ArrayList<>();
        for (JsonNode entry : bundle.path("entry")) {
            final JsonNode r = entry.path("resource");
            if (!"AllergyIntolerance".equals(r.path("resourceType").asText())
                    || r.path("id").asText("").isBlank()) {
                continue;
            }
            final String patientRef = r.path("patient").path("reference").asText("");
            if (patientRef.isBlank()) {
                continue;
            }
            if (!patientRef.equals("Patient/" + authorizedPatientId)) {
                throw new IllegalArgumentException("Resource belongs to a different patient");
            }
            final String verification = code(r.path("verificationStatus"));
            if ("entered-in-error".equals(verification)) {
                continue;
            }
            final String recorded = normalizeDate(r.path("recordedDate").asText(null));
            if (r.hasNonNull("recordedDate") && recorded == null) {
                continue;
            }
            final JsonNode codeNode = r.path("code");
            final String text = codeNode.hasNonNull("text") ? codeNode.get("text").asText() : null;
            final JsonNode coding = codeNode.path("coding").path(0);
            final String code = coding.hasNonNull("code") ? coding.get("code").asText() : null;

            final List<String> reactions = new ArrayList<>();
            String severity = null;
            for (JsonNode reaction : r.path("reaction")) {
                for (JsonNode m : reaction.path("manifestation")) {
                    final String t = m.path("text").asText(m.path("coding").path(0).path("display").asText(null));
                    if (t != null) {
                        reactions.add(t);
                    }
                }
                if (severity == null) {
                    severity = normalizeSeverity(reaction.path("severity").asText(null));
                }
            }
            result.add(new Allergy(SOURCE, r.get("id").asText(), text, code, code(r.path("clinicalStatus")),
                    verification, severity, recorded, List.copyOf(reactions)));
        }
        return result;
    }

    private static String code(JsonNode codeableConcept) {
        final String c = codeableConcept.path("coding").path(0).path("code").asText(null);
        return c;
    }

    private static String normalizeSeverity(String s) {
        return switch (s == null ? "" : s) {
            case "mild", "moderate", "severe" -> s;
            default -> null;
        };
    }

    /** Offset date-times become UTC; partial dates are preserved; invalid values return null. */
    static String normalizeDate(String value) {
        if (value == null || value.isBlank()) {
            return null;
        }
        if (value.matches("\\d{4}(-\\d{2}(-\\d{2})?)?")) {
            return value;
        }
        try {
            return Instant.from(OffsetDateTime.parse(value)).toString();
        } catch (DateTimeParseException e) {
            return null;
        }
    }
}
