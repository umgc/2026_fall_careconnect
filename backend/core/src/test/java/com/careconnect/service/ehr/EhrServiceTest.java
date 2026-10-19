package com.careconnect.service.ehr;

import ca.uhn.fhir.rest.client.apache.ApacheRestfulClientFactory;
import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.model.ehr.EhrCoverageRecord;
import com.careconnect.model.ehr.EhrPatientCrosswalk;
import com.careconnect.model.ehr.EhrVisitRecord;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.UserRepository;
import com.careconnect.repository.ehr.EhrCoverageRecordRepository;
import com.careconnect.repository.ehr.EhrPatientCrosswalkRepository;
import com.careconnect.repository.ehr.EhrVisitRecordRepository;
import com.fasterxml.jackson.databind.JsonNode;
import org.hl7.fhir.r4.model.Coverage;
import org.hl7.fhir.r4.model.ExplanationOfBenefit;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.core.context.SecurityContextImpl;

import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

/**
 * {@code EhrService}: finding the signed-in patient's linked Medicare row, the acting user for the audit
 * log, upserting coverage and visit rows, and the shared FHIR context's HTTP client setup (DEF-MCR-06).
 */
@ExtendWith(MockitoExtension.class)
class EhrServiceTest {

    private static final String EMAIL = "patient2@example.test";
    private static final long MEDICARE = 9L;

    @Mock
    UserRepository userRepository;
    @Mock
    PatientRepository patientRepository;
    @Mock
    EhrPatientCrosswalkRepository crosswalks;
    @Mock
    EhrCoverageRecordRepository coverages;
    @Mock
    EhrVisitRecordRepository visits;
    @InjectMocks
    EhrService service;

    private User user;

    @BeforeEach
    void setUp() {
        SecurityContextHolder.clearContext();
        user = User.builder().id(6L).email(EMAIL).build();
    }

    @AfterEach
    void signOut() {
        SecurityContextHolder.clearContext();
    }

    private static void signIn() {
        SecurityContextHolder.setContext(new SecurityContextImpl(
                new UsernamePasswordAuthenticationToken(EMAIL, null, List.of())));
    }

    private Patient patientRecord() {
        final Patient p = new Patient();
        p.setId(2L);
        p.setUser(user);
        return p;
    }

    private static EhrPatientCrosswalk crosswalk(final String token) {
        final EhrPatientCrosswalk c = new EhrPatientCrosswalk();
        c.setPatientId(2L);
        c.setSourceId(MEDICARE);
        c.setToken(token);
        return c;
    }

    @Test
    @DisplayName("the crosswalk is looked up by patient.id (2), not the user id (6), and returned when linked")
    void crosswalkByPatientId() {
        signIn();
        when(userRepository.findByEmail(EMAIL)).thenReturn(Optional.of(user));
        when(patientRepository.findByUserId(6L)).thenReturn(Optional.of(patientRecord()));
        final EhrPatientCrosswalk linked = crosswalk("encrypted-token");
        when(crosswalks.findByPatientIdAndSourceId(2L, MEDICARE)).thenReturn(Optional.of(linked));

        assertThat(service.getCrosswalk(MEDICARE)).contains(linked);
    }

    @Test
    @DisplayName("a link that is still pending (no token yet) is not returned")
    void pendingLinkIsNotReturned() {
        signIn();
        when(userRepository.findByEmail(EMAIL)).thenReturn(Optional.of(user));
        when(patientRepository.findByUserId(6L)).thenReturn(Optional.of(patientRecord()));
        when(crosswalks.findByPatientIdAndSourceId(2L, MEDICARE)).thenReturn(Optional.of(crosswalk(null)));

        assertThat(service.getCrosswalk(MEDICARE)).isEmpty();
    }

    @Test
    @DisplayName("a signed-in user with no patient record has no crosswalk")
    void noPatientRecord() {
        signIn();
        when(userRepository.findByEmail(EMAIL)).thenReturn(Optional.of(user));
        when(patientRepository.findByUserId(6L)).thenReturn(Optional.empty());

        assertThat(service.getCrosswalk(MEDICARE)).isEmpty();
        verifyNoInteractions(crosswalks);
    }

    @Test
    @DisplayName("with nobody signed in there is no crosswalk and no acting user, and nothing is looked up")
    void nobodySignedIn() {
        assertThat(service.getCrosswalk(MEDICARE)).isEmpty();
        assertThat(service.currentUserId()).isEmpty();
        verifyNoInteractions(userRepository, patientRepository, crosswalks);
    }

    @Test
    @DisplayName("the acting user is the signed-in user's id")
    void currentUserId() {
        signIn();
        when(userRepository.findByEmail(EMAIL)).thenReturn(Optional.of(user));

        assertThat(service.currentUserId()).contains(6L);
    }

    @Test
    @DisplayName("a coverage already stored for that patient, source and external id is updated, not duplicated")
    void coverageUpsertUpdatesExisting() {
        final EhrCoverageRecord existing = EhrCoverageRecord.builder()
                .patientId(2L).sourceId(MEDICARE).externalCoverageId("part-a").build();
        existing.setId(41L);
        when(coverages.findByPatientIdAndSourceIdAndExternalCoverageId(2L, MEDICARE, "part-a"))
                .thenReturn(Optional.of(existing));
        final EhrCoverageRecord incoming = EhrCoverageRecord.builder()
                .patientId(2L).sourceId(MEDICARE).externalCoverageId("part-a").build();

        service.updateCoverageRepository(incoming);

        final ArgumentCaptor<EhrCoverageRecord> saved = ArgumentCaptor.forClass(EhrCoverageRecord.class);
        verify(coverages).save(saved.capture());
        assertThat(saved.getValue().getId()).isEqualTo(41L);
    }

    @Test
    @DisplayName("a new coverage or visit is inserted as a new row")
    void upsertInsertsNew() {
        final EhrCoverageRecord coverage = EhrCoverageRecord.builder()
                .patientId(2L).sourceId(MEDICARE).externalCoverageId("part-b").build();
        final EhrVisitRecord visit = EhrVisitRecord.builder()
                .patientId(2L).sourceId(MEDICARE).externalVisitId("carrier-1").build();
        when(coverages.findByPatientIdAndSourceIdAndExternalCoverageId(2L, MEDICARE, "part-b"))
                .thenReturn(Optional.empty());
        when(visits.findByPatientIdAndSourceIdAndExternalVisitId(2L, MEDICARE, "carrier-1"))
                .thenReturn(Optional.empty());

        service.updateCoverageRepository(coverage);
        service.updateVisitRepository(visit);

        assertThat(coverage.getId()).isNull();
        assertThat(visit.getId()).isNull();
        verify(coverages).save(coverage);
        verify(visits).save(visit);
    }

    @Test
    @DisplayName("a visit already stored is updated in place")
    void visitUpsertUpdatesExisting() {
        final EhrVisitRecord existing = EhrVisitRecord.builder()
                .patientId(2L).sourceId(MEDICARE).externalVisitId("carrier-1").build();
        existing.setId(77L);
        when(visits.findByPatientIdAndSourceIdAndExternalVisitId(2L, MEDICARE, "carrier-1"))
                .thenReturn(Optional.of(existing));
        final EhrVisitRecord incoming = EhrVisitRecord.builder()
                .patientId(2L).sourceId(MEDICARE).externalVisitId("carrier-1").build();

        service.updateVisitRepository(incoming);

        assertThat(incoming.getId()).isEqualTo(77L);
    }

    @Test
    @DisplayName("FHIR JSON round-trips through the shared parser")
    void jsonRoundTrip() {
        final Coverage coverage = new Coverage();
        coverage.setId("part-a");
        coverage.setStatus(Coverage.CoverageStatus.ACTIVE);

        final Coverage back = service.jsonToCoverage(service.coverageToJSON(coverage));

        assertThat(back.getIdElement().getIdPart()).isEqualTo("part-a");
        assertThat(back.getStatus()).isEqualTo(Coverage.CoverageStatus.ACTIVE);
    }

    @Test
    @DisplayName("an ExplanationOfBenefit serializes to JSON and to a Jackson tree")
    void eobToJsonAndNode() throws Exception {
        final ExplanationOfBenefit eob = new ExplanationOfBenefit();
        eob.setId("claim-1");
        eob.setStatus(ExplanationOfBenefit.ExplanationOfBenefitStatus.ACTIVE);

        assertThat(service.jsonToEOB(service.eobToJson(eob)).getIdElement().getIdPart()).isEqualTo("claim-1");
        final JsonNode node = service.eobToNode(eob);
        assertThat(node.get("resourceType").asText()).isEqualTo("ExplanationOfBenefit");
        assertThat(node.get("status").asText()).isEqualTo("active");
    }

    @Test
    @DisplayName("the shared FHIR context uses the Apache client factory set up without automatic retries (DEF-MCR-06)")
    void sharedContextHasNoRetryFactory() {
        assertThat(EhrService.ctxR4.getRestfulClientFactory())
                .isInstanceOf(ApacheRestfulClientFactory.class)
                .isNotExactlyInstanceOf(ApacheRestfulClientFactory.class);
    }
}
