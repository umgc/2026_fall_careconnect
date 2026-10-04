package com.careconnect.service.ehr.athena;

import com.careconnect.config.AthenaProperties;
import com.careconnect.ehr.StoredDateOfBirth;
import com.careconnect.model.Gender;
import com.careconnect.model.Patient;
import com.careconnect.model.ehr.EhrPatientCrosswalk;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.ehr.EhrPatientCrosswalkRepository;
import com.careconnect.service.ehr.EhrAuditService;
import com.careconnect.service.ehr.EhrSourceResolver;
import com.fasterxml.jackson.databind.JsonNode;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Optional;

/**
 * Links a CareConnect patient to their athenahealth chart in {@code ehr_patient_crosswalk}.
 *
 * <p>2-legged OAuth never authenticates the patient to athena, so CareConnect has to decide which
 * chart is theirs, and a wrong decision shows one person another person's record. A link is
 * therefore made only on an exact, unique match: family name, given name and birth date must all be
 * equal, gender must agree when both sides state one, and exactly one chart across every configured
 * practice may pass. Equality is
 * re-checked here because FHIR string search is prefix-based ({@code family=Smith} also returns
 * Smitham). Anything less links nothing.
 *
 * <p>Matching runs once. After that every sync reads the stored link and never searches again.
 */
@Slf4j
@Service
@RequiredArgsConstructor
@ConditionalOnProperty(name = "careconnect.athena.enabled", havingValue = "true")
public class AthenaPatientLinker {

    private static final String SOURCE = AthenaProperties.SOURCE_ATHENA;

    private final AthenaProperties cfg;
    private final AthenaFhirClient fhir;
    private final PatientRepository patients;
    private final EhrPatientCrosswalkRepository crosswalks;
    private final EhrSourceResolver sources;
    private final EhrAuditService audit;

    /**
     * Link the user's patient profile to their athena chart, or report why it cannot be linked.
     *
     * <p>The caller must have recorded the patient's consent first: the demographic search reads
     * across the whole practice, so it is itself an access that needs the patient's permission.
     */
    public AthenaLinkResult link(final Long userId) {
        final AthenaLinkResult result = resolve(userId);
        audit.record(userId, SOURCE, "ATHENA_LINK_" + result.state().name(), "Patient", null,
                result.isLinked() ? EhrAuditService.OUTCOME_OK
                        : result.state() == AthenaLinkResult.State.NOT_MATCHED
                        ? EhrAuditService.OUTCOME_EMPTY : EhrAuditService.OUTCOME_ERROR);
        return result;
    }

    private AthenaLinkResult resolve(final Long userId) {
        final Optional<Patient> local = patients.findByUserId(userId);
        if (local.isEmpty()) {
            return AthenaLinkResult.of(AthenaLinkResult.State.NO_PATIENT_PROFILE);
        }
        final Long sourceId = sources.idForCode(SOURCE);
        if (sourceId == null) {
            return AthenaLinkResult.of(AthenaLinkResult.State.SOURCE_UNAVAILABLE);
        }
        final Patient patient = local.get();
        final Optional<EhrPatientCrosswalk> existing =
                crosswalks.findByPatientIdAndSourceId(patient.getId(), sourceId);
        if (existing.isPresent()) {
            return AthenaLinkResult.linked(existing.get().getExternalPatientId());
        }

        final Optional<LocalDate> dob = StoredDateOfBirth.parse(patient.getDob());
        if (isBlank(patient.getFirstName()) || isBlank(patient.getLastName()) || dob.isEmpty()) {
            return AthenaLinkResult.of(AthenaLinkResult.State.INCOMPLETE_PROFILE);
        }

        // [family, given] is one of the parameter combinations athena accepts for a Patient search;
        // birthdate narrows it further on athena's side.
        final Map<String, String> query = Map.of(
                "family", patient.getLastName().trim(),
                "given", patient.getFirstName().trim(),
                "birthdate", dob.get().toString());
        // Nothing about a CareConnect profile says which practice holds the chart, so every practice
        // the app may read is searched, and exactly one chart across all of them may match.
        final List<JsonNode> exact = new ArrayList<>();
        for (final String practice : cfg.getPracticeIds()) {
            final AthenaFhirClient.SearchResult found;
            try {
                found = fhir.search(userId, practice, "Patient", query);
            } catch (AthenaFhirException ex) {
                // An unsearched practice could hold a second match, so a partial answer links nothing.
                log.warn("athena patient search failed in one practice for user {}: {}", userId, ex.getKind());
                return AthenaLinkResult.of(AthenaLinkResult.State.SOURCE_UNAVAILABLE);
            }
            if (!found.complete()) {
                // A match could be on a page that was never read.
                return AthenaLinkResult.of(AthenaLinkResult.State.AMBIGUOUS_MATCH);
            }
            found.resources().stream()
                    .filter(candidate -> matches(candidate, patient, dob.get()))
                    .forEach(exact::add);
        }
        if (exact.isEmpty()) {
            return AthenaLinkResult.of(AthenaLinkResult.State.NOT_MATCHED);
        }
        if (exact.size() > 1) {
            return AthenaLinkResult.of(AthenaLinkResult.State.AMBIGUOUS_MATCH);
        }
        final String athenaPatientId = exact.get(0).path("id").asText("");
        if (athenaPatientId.isBlank()) {
            return AthenaLinkResult.of(AthenaLinkResult.State.NOT_MATCHED);
        }
        if (fhir.practiceFor(athenaPatientId).isEmpty()) {
            // Sync reads a chart in its own practice; one outside the configured list could never sync.
            log.warn("athena matched a chart for user {} outside the configured practices", userId);
            return AthenaLinkResult.of(AthenaLinkResult.State.SOURCE_UNAVAILABLE);
        }
        return save(patient.getId(), sourceId, athenaPatientId);
    }

    private AthenaLinkResult save(final Long patientId, final Long sourceId, final String athenaPatientId) {
        // This patient has no link yet, so a row already holding this chart belongs to someone else.
        if (crosswalks.findBySourceIdAndExternalPatientId(sourceId, athenaPatientId).isPresent()) {
            return AthenaLinkResult.of(AthenaLinkResult.State.LINK_CONFLICT);
        }
        try {
            crosswalks.save(EhrPatientCrosswalk.builder()
                    .patientId(patientId)
                    .sourceId(sourceId)
                    .externalPatientId(athenaPatientId)
                    .build());
            return AthenaLinkResult.linked(athenaPatientId);
        } catch (DataIntegrityViolationException ex) {
            // Lost a race. Either this patient's own concurrent request linked the same chart, which
            // is fine, or another patient claimed it first.
            return crosswalks.findByPatientIdAndSourceId(patientId, sourceId)
                    .filter(row -> athenaPatientId.equals(row.getExternalPatientId()))
                    .map(row -> AthenaLinkResult.linked(athenaPatientId))
                    .orElseGet(() -> AthenaLinkResult.of(AthenaLinkResult.State.LINK_CONFLICT));
        }
    }

    /**
     * Exact match on birth date, gender (when both are known) and one name entry whose family name and
     * FIRST given name both equal the profile's. Only the first given name counts: the rest are middle
     * names, and athena's search matches any of them (the sandbox holds "Testy Robert" charts that a
     * search for given=Robert returns).
     */
    static boolean matches(final JsonNode candidate, final Patient local, final LocalDate dob) {
        if (!dob.toString().equals(candidate.path("birthDate").asText(""))) {
            return false;
        }
        if (!genderAgrees(local.getGender(), candidate.path("gender").asText(""))) {
            return false;
        }
        final String family = local.getLastName().trim();
        final String given = local.getFirstName().trim();
        for (final JsonNode name : candidate.path("name")) {
            if (family.equalsIgnoreCase(name.path("family").asText("").trim())
                    && given.equalsIgnoreCase(name.path("given").path(0).asText("").trim())) {
                return true;
            }
        }
        return false;
    }

    /** Gender vetoes a match only when both sides state one; FHIR "unknown" states nothing. */
    static boolean genderAgrees(final Gender local, final String fhirGender) {
        final String expected = local == null ? null : switch (local) {
            case MALE -> "male";
            case FEMALE -> "female";
            case OTHER -> "other";
            case PREFER_NOT_TO_SAY -> null;
        };
        if (expected == null || fhirGender.isBlank() || "unknown".equalsIgnoreCase(fhirGender)) {
            return true;
        }
        return expected.equalsIgnoreCase(fhirGender);
    }

    private static boolean isBlank(final String value) {
        return value == null || value.isBlank();
    }
}
