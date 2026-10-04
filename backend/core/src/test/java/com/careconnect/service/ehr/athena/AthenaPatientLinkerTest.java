package com.careconnect.service.ehr.athena;

import com.careconnect.config.AthenaProperties;
import com.careconnect.model.Gender;
import com.careconnect.model.Patient;
import com.careconnect.model.ehr.EhrPatientCrosswalk;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.ehr.EhrPatientCrosswalkRepository;
import com.careconnect.service.ehr.EhrAuditService;
import com.careconnect.service.ehr.EhrSourceResolver;
import com.careconnect.testsupport.fixtures.AthenaPropertiesFixtures;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.dao.DataIntegrityViolationException;

import java.util.List;
import java.util.Map;
import java.util.Optional;

import static com.careconnect.testsupport.fixtures.AthenaFhirFixtures.ROMILDA_ID;
import static com.careconnect.testsupport.fixtures.AthenaFhirFixtures.patient;
import static com.careconnect.testsupport.fixtures.AthenaFhirFixtures.romilda;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyMap;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Unit tests for {@link AthenaPatientLinker}. A wrong link shows one person another person's chart,
 * so most cases here are ways a near-miss must NOT link: FHIR's prefix matching, a second chart with
 * the same demographics, a disagreeing birth date or gender, and a chart another patient already holds.
 */
class AthenaPatientLinkerTest {

    private static final long USER_ID = 7L;
    private static final long PATIENT_ID = 5L;
    private static final long SOURCE_ID = 9L;

    private AthenaFhirClient fhir;
    private PatientRepository patients;
    private EhrPatientCrosswalkRepository crosswalks;
    private EhrSourceResolver sources;
    private EhrAuditService audit;
    private AthenaPatientLinker linker;

    @BeforeEach
    void setUp() {
        fhir = mock(AthenaFhirClient.class);
        patients = mock(PatientRepository.class);
        crosswalks = mock(EhrPatientCrosswalkRepository.class);
        sources = mock(EhrSourceResolver.class);
        audit = mock(EhrAuditService.class);
        linker = linkerFor(AthenaPropertiesFixtures.PRACTICE_ID);
        when(fhir.practiceFor(anyString())).thenReturn(Optional.of(AthenaPropertiesFixtures.PRACTICE_ID));

        when(sources.idForCode(AthenaProperties.SOURCE_ATHENA)).thenReturn(SOURCE_ID);
        when(crosswalks.findByPatientIdAndSourceId(PATIENT_ID, SOURCE_ID)).thenReturn(Optional.empty());
        when(crosswalks.findBySourceIdAndExternalPatientId(eq(SOURCE_ID), anyString())).thenReturn(Optional.empty());
    }

    /** A linker that searches {@code practiceIds}, comma-separated as ATHENA_PRACTICE_ID is. */
    private AthenaPatientLinker linkerFor(final String practiceIds) {
        return new AthenaPatientLinker(AthenaPropertiesFixtures.builder().practiceIds(practiceIds).build(),
                fhir, patients, crosswalks, sources, audit);
    }

    /** Romilda's CareConnect profile, as seeded; it matches her sandbox chart exactly. */
    private void localPatient(final String first, final String last, final String dob, final Gender gender) {
        when(patients.findByUserId(USER_ID)).thenReturn(Optional.of(Patient.builder()
                .id(PATIENT_ID).firstName(first).lastName(last).dob(dob).gender(gender).build()));
    }

    private void athenaReturns(final JsonNode... candidates) {
        when(fhir.search(eq(USER_ID), anyString(), eq("Patient"), anyMap()))
                .thenReturn(new AthenaFhirClient.SearchResult(List.of(candidates), true));
    }

    @Test
    @DisplayName("an exact, unique match is linked and saved to the crosswalk")
    void exactUniqueMatchIsLinked() {
        // Arrange
        localPatient("Romilda", "Smith", "1976-02-28", Gender.FEMALE);
        athenaReturns(romilda());

        // Act
        final AthenaLinkResult result = linker.link(USER_ID);

        // Assert
        assertTrue(result.isLinked());
        assertEquals(ROMILDA_ID, result.athenaPatientId());
        final ArgumentCaptor<EhrPatientCrosswalk> saved = ArgumentCaptor.forClass(EhrPatientCrosswalk.class);
        verify(crosswalks).save(saved.capture());
        assertEquals(PATIENT_ID, saved.getValue().getPatientId());
        assertEquals(SOURCE_ID, saved.getValue().getSourceId());
        assertEquals(ROMILDA_ID, saved.getValue().getExternalPatientId());
        verify(audit).record(USER_ID, AthenaProperties.SOURCE_ATHENA, "ATHENA_LINK_LINKED", "Patient", null,
                EhrAuditService.OUTCOME_OK);
    }

    @Test
    @DisplayName("the search sends family, given and an ISO birthdate, even for a MM/dd/yyyy profile")
    @SuppressWarnings("unchecked")
    void searchUsesIsoBirthdate() {
        // Arrange: the onboarding screen stores dates as MM/dd/yyyy.
        localPatient(" Romilda ", "Smith", "02/28/1976", Gender.FEMALE);
        athenaReturns(romilda());

        // Act
        linker.link(USER_ID);

        // Assert
        final ArgumentCaptor<Map<String, String>> params = ArgumentCaptor.forClass(Map.class);
        verify(fhir).search(eq(USER_ID), eq(AthenaPropertiesFixtures.PRACTICE_ID), eq("Patient"), params.capture());
        assertEquals(Map.of("family", "Smith", "given", "Romilda", "birthdate", "1976-02-28"), params.getValue());
    }

    @Test
    @DisplayName("an existing link is returned without searching athena again")
    void existingLinkSkipsTheSearch() {
        // Arrange
        localPatient("Romilda", "Smith", "1976-02-28", Gender.FEMALE);
        when(crosswalks.findByPatientIdAndSourceId(PATIENT_ID, SOURCE_ID)).thenReturn(Optional.of(
                EhrPatientCrosswalk.builder().patientId(PATIENT_ID).sourceId(SOURCE_ID)
                        .externalPatientId(ROMILDA_ID).build()));

        // Act
        final AthenaLinkResult result = linker.link(USER_ID);

        // Assert
        assertEquals(ROMILDA_ID, result.athenaPatientId());
        verify(fhir, never()).search(any(), any(), any(), any());
    }

    @Test
    @DisplayName("prefix matching is not trusted: Smitham does not match Smith")
    void prefixMatchIsNotAMatch() {
        // Arrange: athena's family=Smith search also returns Smitham.
        localPatient("Romilda", "Smith", "1976-02-28", Gender.FEMALE);
        athenaReturns(patient("a-1", "Smitham", "Romilda", "1976-02-28", "female"));

        // Act
        final AthenaLinkResult result = linker.link(USER_ID);

        // Assert
        assertEquals(AthenaLinkResult.State.NOT_MATCHED, result.state());
        verify(crosswalks, never()).save(any());
    }

    @Test
    @DisplayName("a middle name is not a first name: Testy Robert does not match a profile named Robert")
    void middleNameIsNotAFirstName() {
        // Arrange: athena's given=Robert search returns this chart, whose first name is Testy.
        localPatient("Robert", "Testpatient", "1955-05-05", Gender.MALE);
        final ObjectNode chart = patient("a-1", "Testpatient", "Testy", "1955-05-05", "male");
        ((ArrayNode) chart.path("name").path(0).path("given")).add("Robert");
        athenaReturns(chart);

        // Act / Assert
        assertEquals(AthenaLinkResult.State.NOT_MATCHED, linker.link(USER_ID).state());
        verify(crosswalks, never()).save(any());
    }

    @Test
    @DisplayName("two charts with identical demographics are AMBIGUOUS and nothing is linked")
    void twoExactMatchesAreAmbiguous() {
        // Arrange: the sandbox really holds two John Smiths born on the same day.
        localPatient("John", "Smith", "1980-01-01", Gender.MALE);
        athenaReturns(patient("a-1", "Smith", "John", "1980-01-01", "male"),
                patient("a-2", "Smith", "John", "1980-01-01", "male"));

        // Act
        final AthenaLinkResult result = linker.link(USER_ID);

        // Assert
        assertEquals(AthenaLinkResult.State.AMBIGUOUS_MATCH, result.state());
        assertNull(result.athenaPatientId());
        verify(crosswalks, never()).save(any());
    }

    @Test
    @DisplayName("a different birth date, or a partial one, does not match")
    void birthDateMustBeExact() {
        // Arrange
        localPatient("Romilda", "Smith", "1976-02-28", Gender.FEMALE);
        athenaReturns(patient("a-1", "Smith", "Romilda", "1976-02-29", "female"),
                patient("a-2", "Smith", "Romilda", "1976", "female"));

        // Act / Assert
        assertEquals(AthenaLinkResult.State.NOT_MATCHED, linker.link(USER_ID).state());
    }

    @Test
    @DisplayName("a stated gender that disagrees vetoes the match")
    void disagreeingGenderIsNotAMatch() {
        // Arrange
        localPatient("Romilda", "Smith", "1976-02-28", Gender.FEMALE);
        athenaReturns(patient("a-1", "Smith", "Romilda", "1976-02-28", "male"));

        // Act / Assert
        assertEquals(AthenaLinkResult.State.NOT_MATCHED, linker.link(USER_ID).state());
    }

    @Test
    @DisplayName("gender is no veto when either side leaves it unknown")
    void unknownGenderDoesNotVeto() {
        assertTrue(AthenaPatientLinker.genderAgrees(Gender.FEMALE, "unknown"));
        assertTrue(AthenaPatientLinker.genderAgrees(Gender.FEMALE, ""));
        assertTrue(AthenaPatientLinker.genderAgrees(null, "female"));
        assertTrue(AthenaPatientLinker.genderAgrees(Gender.PREFER_NOT_TO_SAY, "male"));
        assertTrue(AthenaPatientLinker.genderAgrees(Gender.OTHER, "other"));
        assertFalse(AthenaPatientLinker.genderAgrees(Gender.MALE, "female"));
    }

    @Test
    @DisplayName("a chart another patient already holds is a LINK_CONFLICT, not a second link")
    void chartHeldByAnotherPatientConflicts() {
        // Arrange
        localPatient("Romilda", "Smith", "1976-02-28", Gender.FEMALE);
        athenaReturns(romilda());
        when(crosswalks.findBySourceIdAndExternalPatientId(SOURCE_ID, ROMILDA_ID)).thenReturn(Optional.of(
                EhrPatientCrosswalk.builder().patientId(99L).sourceId(SOURCE_ID).externalPatientId(ROMILDA_ID).build()));

        // Act
        final AthenaLinkResult result = linker.link(USER_ID);

        // Assert
        assertEquals(AthenaLinkResult.State.LINK_CONFLICT, result.state());
        verify(crosswalks, never()).save(any());
    }

    @Test
    @DisplayName("losing a save race to this patient's own request still reports LINKED")
    void raceWonByTheSamePatientIsLinked() {
        // Arrange: the unique index rejects the insert, and the winning row is this patient's.
        localPatient("Romilda", "Smith", "1976-02-28", Gender.FEMALE);
        athenaReturns(romilda());
        when(crosswalks.save(any())).thenThrow(new DataIntegrityViolationException("uq_ehr_crosswalk_patient_source"));
        when(crosswalks.findByPatientIdAndSourceId(PATIENT_ID, SOURCE_ID))
                .thenReturn(Optional.empty())
                .thenReturn(Optional.of(EhrPatientCrosswalk.builder().patientId(PATIENT_ID).sourceId(SOURCE_ID)
                        .externalPatientId(ROMILDA_ID).build()));

        // Act / Assert
        assertTrue(linker.link(USER_ID).isLinked());
    }

    @Test
    @DisplayName("losing a save race to another patient is a LINK_CONFLICT")
    void raceWonByAnotherPatientConflicts() {
        // Arrange
        localPatient("Romilda", "Smith", "1976-02-28", Gender.FEMALE);
        athenaReturns(romilda());
        when(crosswalks.save(any())).thenThrow(new DataIntegrityViolationException("uq_ehr_crosswalk_source_external"));

        // Act / Assert
        assertEquals(AthenaLinkResult.State.LINK_CONFLICT, linker.link(USER_ID).state());
    }

    @Test
    @DisplayName("a profile without a readable birth date is INCOMPLETE and athena is not searched")
    void incompleteProfileIsNotSearched() {
        // Arrange
        localPatient("Romilda", "Smith", "not a date", Gender.FEMALE);

        // Act
        final AthenaLinkResult result = linker.link(USER_ID);

        // Assert
        assertEquals(AthenaLinkResult.State.INCOMPLETE_PROFILE, result.state());
        verify(fhir, never()).search(any(), any(), any(), any());
    }

    @Test
    @DisplayName("a user with no patient profile is NO_PATIENT_PROFILE")
    void noPatientProfile() {
        when(patients.findByUserId(USER_ID)).thenReturn(Optional.empty());
        assertEquals(AthenaLinkResult.State.NO_PATIENT_PROFILE, linker.link(USER_ID).state());
    }

    @Test
    @DisplayName("an unregistered athena source is SOURCE_UNAVAILABLE")
    void unregisteredSourceIsUnavailable() {
        // Arrange
        localPatient("Romilda", "Smith", "1976-02-28", Gender.FEMALE);
        when(sources.idForCode(AthenaProperties.SOURCE_ATHENA)).thenReturn(null);

        // Act / Assert
        assertEquals(AthenaLinkResult.State.SOURCE_UNAVAILABLE, linker.link(USER_ID).state());
    }

    @Test
    @DisplayName("a failed search is SOURCE_UNAVAILABLE and is audited as an error")
    void failedSearchIsUnavailable() {
        // Arrange
        localPatient("Romilda", "Smith", "1976-02-28", Gender.FEMALE);
        when(fhir.search(eq(USER_ID), anyString(), eq("Patient"), anyMap()))
                .thenThrow(new AthenaFhirException(AthenaFhirException.Kind.UNAVAILABLE, "down"));

        // Act
        final AthenaLinkResult result = linker.link(USER_ID);

        // Assert
        assertEquals(AthenaLinkResult.State.SOURCE_UNAVAILABLE, result.state());
        verify(audit).record(USER_ID, AthenaProperties.SOURCE_ATHENA, "ATHENA_LINK_SOURCE_UNAVAILABLE", "Patient",
                null, EhrAuditService.OUTCOME_ERROR);
    }

    @Test
    @DisplayName("every configured practice is searched, and a unique match in one of them links")
    void searchesEveryConfiguredPractice() {
        // Arrange: Romilda's chart is in the first practice; the second has no match.
        linker = linkerFor("a-1.Practice-195900,a-1.Practice-80000");
        localPatient("Romilda", "Smith", "1976-02-28", Gender.FEMALE);
        when(fhir.search(eq(USER_ID), eq("a-1.Practice-195900"), eq("Patient"), anyMap()))
                .thenReturn(new AthenaFhirClient.SearchResult(List.of(romilda()), true));
        when(fhir.search(eq(USER_ID), eq("a-1.Practice-80000"), eq("Patient"), anyMap()))
                .thenReturn(new AthenaFhirClient.SearchResult(List.of(), true));

        // Act
        final AthenaLinkResult result = linker.link(USER_ID);

        // Assert
        assertEquals(ROMILDA_ID, result.athenaPatientId());
        verify(fhir).search(eq(USER_ID), eq("a-1.Practice-80000"), eq("Patient"), anyMap());
    }

    @Test
    @DisplayName("the same person matching in two practices is AMBIGUOUS, not a pick of the first")
    void matchesInTwoPracticesAreAmbiguous() {
        // Arrange
        linker = linkerFor("a-1.Practice-195900,a-1.Practice-80000");
        localPatient("Romilda", "Smith", "1976-02-28", Gender.FEMALE);
        when(fhir.search(eq(USER_ID), eq("a-1.Practice-195900"), eq("Patient"), anyMap()))
                .thenReturn(new AthenaFhirClient.SearchResult(List.of(romilda()), true));
        when(fhir.search(eq(USER_ID), eq("a-1.Practice-80000"), eq("Patient"), anyMap()))
                .thenReturn(new AthenaFhirClient.SearchResult(List.of(
                        patient("a-80000.E-7", "Smith", "Romilda", "1976-02-28", "female")), true));

        // Act / Assert
        assertEquals(AthenaLinkResult.State.AMBIGUOUS_MATCH, linker.link(USER_ID).state());
        verify(crosswalks, never()).save(any());
    }

    @Test
    @DisplayName("one practice failing links nothing, even when another found a unique match")
    void onePracticeFailingLinksNothing() {
        // Arrange: the unreachable practice could hold a second match.
        linker = linkerFor("a-1.Practice-195900,a-1.Practice-80000");
        localPatient("Romilda", "Smith", "1976-02-28", Gender.FEMALE);
        when(fhir.search(eq(USER_ID), eq("a-1.Practice-195900"), eq("Patient"), anyMap()))
                .thenReturn(new AthenaFhirClient.SearchResult(List.of(romilda()), true));
        when(fhir.search(eq(USER_ID), eq("a-1.Practice-80000"), eq("Patient"), anyMap()))
                .thenThrow(new AthenaFhirException(AthenaFhirException.Kind.SCOPE_DENIED, "403"));

        // Act / Assert
        assertEquals(AthenaLinkResult.State.SOURCE_UNAVAILABLE, linker.link(USER_ID).state());
        verify(crosswalks, never()).save(any());
    }

    @Test
    @DisplayName("an incomplete search is AMBIGUOUS, since a second match may be on an unread page")
    void incompleteSearchIsAmbiguous() {
        // Arrange
        localPatient("Romilda", "Smith", "1976-02-28", Gender.FEMALE);
        when(fhir.search(eq(USER_ID), anyString(), eq("Patient"), anyMap()))
                .thenReturn(new AthenaFhirClient.SearchResult(List.of(romilda()), false));

        // Act / Assert
        assertEquals(AthenaLinkResult.State.AMBIGUOUS_MATCH, linker.link(USER_ID).state());
        verify(crosswalks, never()).save(any());
    }

    @Test
    @DisplayName("a match whose chart is outside the configured practices is not linked")
    void matchOutsideConfiguredPracticesIsNotLinked() {
        // Arrange: sync could never read this chart, so linking it would strand the patient.
        localPatient("Romilda", "Smith", "1976-02-28", Gender.FEMALE);
        athenaReturns(romilda());
        when(fhir.practiceFor(ROMILDA_ID)).thenReturn(Optional.empty());

        // Act / Assert
        assertEquals(AthenaLinkResult.State.SOURCE_UNAVAILABLE, linker.link(USER_ID).state());
        verify(crosswalks, never()).save(any());
    }
}
