package com.careconnect.integration.cerner;

import com.careconnect.config.CernerProperties;
import com.careconnect.model.ehr.EhrAppointmentRecord;
import com.careconnect.model.ehr.EhrSourceIdentity;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.core.io.ClassPathResource;

import java.io.InputStream;
import java.time.Instant;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.time.YearMonth;
import java.time.format.DateTimeParseException;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

/**
 * Pure, offline mapper from a Cerner FHIR R4 AllergyIntolerance searchset Bundle
 * to provisional normalized records (M3 MAP scenarios). Output shape is provisional
 * until OpenAPI 1.0 is approved.
 */
public final class CernerAllergyMapper {

    /** Canonical {@code ehr_source.code} for Oracle Health/Cerner records. */
    public static final String SOURCE = CernerProperties.SOURCE_ORACLE_HEALTH;

    public record Allergy(String source, String sourceRecordId, String substanceText, String substanceCode,
                          String clinicalStatus, String verificationStatus, String severity,
                          String recordedDate, List<String> reactions) {
    }

    CernerAllergyMapper() {
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


    /**
     * Maps a Cerner FHIR R4 AllergyIntolerance searchset `Bundle` into normalized allergy records,
     * allowing optional fields to be missing.
     *
     * Optional fields (for example substance text/code, clinical status, severity, reactions)
     * may be absent and are mapped as `null` or empty list as appropriate.
     *
     * @param bundle FHIR searchset `Bundle`.
     * @param authorizedPatientId Authorized patient logical id used for strict ownership checks.
     * @return Mapped allergy records with optional fields tolerated when absent.
     * @throws IllegalArgumentException if the input is not a valid `Bundle` or if any resource
     *                                  references a different patient.
     */
    public static List<Allergy> mapPatientWithOptionalFieldsAbsent(JsonNode bundle, String authorizedPatientId) {
        if (bundle == null || !"Bundle".equals(bundle.path("resourceType").asText())) {
            throw new IllegalArgumentException("Invalid Bundle");
        }

        final List<Allergy> result = new ArrayList<>();
        for (JsonNode entry : bundle.path("entry")) {
            final JsonNode r = entry.path("resource");
            if (!"AllergyIntolerance".equals(r.path("resourceType").asText())) {
                continue;
            }

            final String id = r.path("id").asText("");
            if (id.isBlank()) {
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

            final String recordedRaw = r.path("recordedDate").asText(null);
            final String recorded = normalizeDate(recordedRaw);
            if (recordedRaw != null && recorded == null) {
                continue;
            }

            final JsonNode codeNode = r.path("code");
            final String substanceText = codeNode.hasNonNull("text") ? codeNode.get("text").asText() : null;
            final JsonNode coding = codeNode.path("coding").path(0);
            final String substanceCode = coding.hasNonNull("code") ? coding.get("code").asText() : null;

            final List<String> reactions = new ArrayList<>();
            String severity = null;
            for (JsonNode reaction : r.path("reaction")) {
                for (JsonNode manifestation : reaction.path("manifestation")) {
                    final String text = manifestation.path("text")
                            .asText(manifestation.path("coding").path(0).path("display").asText(null));
                    if (text != null && !text.isBlank()) {
                        reactions.add(text);
                    }
                }
                if (severity == null) {
                    severity = normalizeSeverity(reaction.path("severity").asText(null));
                }
            }

            result.add(new Allergy(
                    SOURCE,
                    id,
                    substanceText,                  // optional
                    substanceCode,                  // optional
                    code(r.path("clinicalStatus")), // optional
                    verification,                   // optional
                    severity,                       // optional
                    recorded,                       // optional
                    List.copyOf(reactions)          // optional/empty allowed
            ));
        }

        return result;
    }


    /**
     * Maps Cerner FHIR R4 `AllergyIntolerance` resources from a searchset `Bundle`
     * into normalized allergy records while handling additional patient-mapping edge cases.
     *
     * @param bundle FHIR searchset `Bundle`.
     * @param authorizedPatientId Authorized patient logical id used for strict ownership checks.
     * @return Normalized allergy records after edge\-case validation and filtering.
     * @throws IllegalArgumentException if input is not a valid `Bundle`, if authorized patient id
     *                                  is invalid, or if any resource references a different patient.
     */
    public static List<Allergy> mapAdditionalPatientMappingEdgeCases(JsonNode bundle, String authorizedPatientId) {
        if (bundle == null || !"Bundle".equals(bundle.path("resourceType").asText())) {
            throw new IllegalArgumentException("Invalid Bundle");
        }
        if (authorizedPatientId == null || authorizedPatientId.isBlank()) {
            throw new IllegalArgumentException("Invalid authorized patient id");
        }

        final List<Allergy> result = new ArrayList<>();
        final java.util.Set<String> seen = new java.util.HashSet<>();

        for (JsonNode entry : bundle.path("entry")) {
            final JsonNode r = entry.path("resource");
            if (!"AllergyIntolerance".equals(r.path("resourceType").asText())) {
                continue;
            }

            final String id = r.path("id").asText("");
            if (id.isBlank() || !seen.add(id)) {
                continue;
            }

            final String patientRef = r.path("patient").path("reference").asText("");
            if (patientRef.isBlank()) {
                continue;
            }

            final String normalizedRef = patientRef.startsWith("Patient/") ? patientRef : "Patient/" + patientRef;
            if (!normalizedRef.equals("Patient/" + authorizedPatientId)) {
                throw new IllegalArgumentException("Resource belongs to a different patient");
            }

            final String verification = code(r.path("verificationStatus"));
            if ("entered-in-error".equals(verification)) {
                continue;
            }

            final String recordedRaw = r.path("recordedDate").asText(null);
            final String recorded = normalizeDate(recordedRaw);
            if (recordedRaw != null && recorded == null) {
                continue;
            }

            final JsonNode codeNode = r.path("code");
            final String substanceText = codeNode.hasNonNull("text") ? codeNode.get("text").asText() : null;

            String substanceCode = null;
            for (JsonNode c : codeNode.path("coding")) {
                final String candidate = c.path("code").asText(null);
                if (candidate != null && !candidate.isBlank()) {
                    substanceCode = candidate;
                    break;
                }
            }

            final java.util.LinkedHashSet<String> reactionSet = new java.util.LinkedHashSet<>();
            String severity = null;
            for (JsonNode reaction : r.path("reaction")) {
                for (JsonNode manifestation : reaction.path("manifestation")) {
                    final String text = manifestation.path("text")
                            .asText(manifestation.path("coding").path(0).path("display").asText(null));
                    if (text != null && !text.isBlank()) {
                        reactionSet.add(text.trim());
                    }
                }
                if (severity == null) {
                    severity = normalizeSeverity(reaction.path("severity").asText(null));
                }
            }

            String clinicalStatus = null;
            for (JsonNode c : r.path("clinicalStatus").path("coding")) {
                final String candidate = c.path("code").asText(null);
                if (candidate != null && !candidate.isBlank()) {
                    clinicalStatus = candidate;
                    break;
                }
            }

            result.add(new Allergy(
                    SOURCE,
                    id,
                    substanceText,
                    substanceCode,
                    clinicalStatus,
                    verification,
                    severity,
                    recorded,
                    List.copyOf(reactionSet)
            ));
        }
        return result;
    }


    /**
     * Validates synchronized patient and appointment data against the expected fixture payload.
     *
     * Compares patient identity fields and a normalized, order\-independent view of appointments
     * in the requested time window.
     *
     * @param patientId internal patient identifier used to trigger synchronization
     * @param startInclusive inclusive lower bound of the appointment time range
     * @param endExclusive exclusive upper bound of the appointment time range
     * @param patientAppointmentService service used to synchronize patient and appointments
     * @param objectMapper Jackson mapper used to load and parse the expected fixture JSON
     * @return `true` when both patient and appointment outputs match the fixture; otherwise `false`
     */
    public boolean validatePatientAndAppointmentExpectedOutputFixtures(
            final long patientId,
            final Instant startInclusive,
            final Instant endExclusive,
            final CernerPatientAppointmentService patientAppointmentService,
            final ObjectMapper objectMapper) {

        final EhrSourceIdentity actualPatient = patientAppointmentService.synchronizePatient(patientId);
        final List<EhrAppointmentRecord> actualAppointments =
                patientAppointmentService.synchronizeAppointments(patientId, startInclusive, endExclusive);

        final JsonNode expectedRoot = readFixture(
                "fixtures/cerner/expected-patient-appointments.json", objectMapper);
        final JsonNode expectedPatient = expectedRoot.path("patient");
        final JsonNode expectedAppointments = expectedRoot.path("appointments");

        if (actualPatient == null || expectedPatient.isMissingNode()) {
            return false;
        }
        if (!patientMatches(actualPatient, expectedPatient)) {
            return false;
        }

        final List<Map<String, String>> actualNormalized = normalizeAppointments(actualAppointments);
        final List<Map<String, String>> expectedNormalized = normalizeExpectedAppointments(expectedAppointments);
        return actualNormalized.equals(expectedNormalized);
    }

    private JsonNode readFixture(final String classpathLocation, final ObjectMapper objectMapper) {
        try (InputStream in = new ClassPathResource(classpathLocation).getInputStream()) {
            return objectMapper.readTree(in);
        } catch (Exception e) {
            throw new IllegalStateException("Unable to load expected-output fixture: " + classpathLocation, e);
        }
    }

    private boolean patientMatches(final EhrSourceIdentity actual, final JsonNode expectedPatient) {
        final String actualExternalPatientId = safeString(readViaGetter(actual, "getExternalPatientId"));
        final String actualSource = safeString(readViaGetter(actual, "getSourceSystem"));

        final String expectedExternalPatientId = expectedPatient.path("externalPatientId").asText("");
        final String expectedSource = expectedPatient.path("source").asText("");

        return actualExternalPatientId.equals(expectedExternalPatientId)
                && actualSource.equals(expectedSource);
    }

    private List<Map<String, String>> normalizeAppointments(final List<EhrAppointmentRecord> appointments) {
        if (appointments == null) {
            return List.of();
        }

        return appointments.stream()
                .map(a -> Map.of(
                        "externalAppointmentId", safeString(readViaGetter(a, "getExternalAppointmentId")),
                        "status", safeString(readViaGetter(a, "getStatus")),
                        "start", safeString(readViaGetter(a, "getStartTime")),
                        "end", safeString(readViaGetter(a, "getEndTime"))
                ))
                .sorted(Comparator.comparing(m -> m.get("externalAppointmentId")))
                .collect(Collectors.toList());
    }

    private List<Map<String, String>> normalizeExpectedAppointments(final JsonNode expectedAppointments) {
        if (expectedAppointments == null || !expectedAppointments.isArray()) {
            return List.of();
        }

        return java.util.stream.StreamSupport.stream(expectedAppointments.spliterator(), false)
                .map(n -> Map.of(
                        "externalAppointmentId", n.path("externalAppointmentId").asText(""),
                        "status", n.path("status").asText(""),
                        "start", n.path("start").asText(""),
                        "end", n.path("end").asText("")
                ))
                .sorted(Comparator.comparing(m -> m.get("externalAppointmentId")))
                .collect(Collectors.toList());
    }

    private static Object readViaGetter(final Object target, final String getterName) {
        try {
            return target.getClass().getMethod(getterName).invoke(target);
        } catch (Exception e) {
            return null;
        }
    }

    private static String safeString(final Object value) {
        return value == null ? "" : String.valueOf(value);
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
        try {
            if (value.matches("\\d{4}(-\\d{2}(-\\d{2})?)?")) {
                if (value.length() == 7) {
                    YearMonth.parse(value);
                } else if (value.length() == 10) {
                    LocalDate.parse(value);
                }
                return value;
            }
            return Instant.from(OffsetDateTime.parse(value)).toString();
        } catch (DateTimeParseException e) {
            return null;
        }
    }
}
