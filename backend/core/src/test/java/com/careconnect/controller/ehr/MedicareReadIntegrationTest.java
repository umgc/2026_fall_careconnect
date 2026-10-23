package com.careconnect.controller.ehr;

import ca.uhn.fhir.parser.IParser;
import ca.uhn.fhir.rest.server.exceptions.InternalErrorException;
import com.careconnect.exception.AppException;
import com.careconnect.exception.GlobalExceptionHandler;
import com.careconnect.model.CaregiverPatientLink;
import com.careconnect.model.ConsentGrant;
import com.careconnect.model.FamilyMemberLink;
import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.model.ehr.EhrAuditEvent;
import com.careconnect.model.ehr.EhrPatientCrosswalk;
import com.careconnect.model.ehr.EhrRawPayload;
import com.careconnect.model.ehr.EhrRetrievalOutcome;
import com.careconnect.model.ehr.EhrSource;
import com.careconnect.model.ehr.MedicareProperties;
import com.careconnect.model.ehr.MedicareStatusGate;
import com.careconnect.repository.CaregiverPatientLinkRepository;
import com.careconnect.repository.ConsentGrantRepository;
import com.careconnect.repository.FamilyMemberLinkRepository;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.UserRepository;
import com.careconnect.repository.ehr.EhrAuditEventRepository;
import com.careconnect.repository.ehr.EhrCoverageRecordRepository;
import com.careconnect.repository.ehr.EhrPatientCrosswalkRepository;
import com.careconnect.repository.ehr.EhrRawPayloadRepository;
import com.careconnect.repository.ehr.EhrSourceIdentityRepository;
import com.careconnect.repository.ehr.EhrSourceRepository;
import com.careconnect.repository.ehr.EhrVisitRecordRepository;
import com.careconnect.security.MedicareAccessPolicy;
import com.careconnect.security.Role;
import com.careconnect.service.ehr.EhrAuditLogger;
import com.careconnect.service.ehr.EhrService;
import com.careconnect.service.ehr.MedicareConnectionService;
import com.careconnect.service.ehr.MedicareRecordCache;
import com.careconnect.service.ehr.MedicareService;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.assertj.core.api.ThrowableAssert.ThrowingCallable;
import org.hl7.fhir.r4.model.Bundle;
import org.hl7.fhir.r4.model.Coverage;
import org.hl7.fhir.r4.model.ExplanationOfBenefit;
import org.hl7.fhir.r4.model.Resource;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.Arguments;
import org.junit.jupiter.params.provider.MethodSource;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.autoconfigure.ImportAutoConfiguration;
import org.springframework.boot.autoconfigure.jackson.JacksonAutoConfiguration;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.context.annotation.Import;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.core.context.SecurityContextImpl;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import java.io.IOException;
import java.io.InputStream;
import java.io.UncheckedIOException;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.List;

import static com.careconnect.service.ehr.EhrService.ctxR4;
import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;

/**
 * The Medicare reads end to end below the HTTP filter chain: the real {@link EhrController},
 * {@link MedicareRecordCache}, {@link EhrService}, {@link EhrAuditLogger} and status gate over real JPA
 * repositories on the H2 test database, with only Blue Button ({@link MedicareService}) and the token
 * store ({@link MedicareConnectionService}) stubbed. The resources are the synthetic Blue Button
 * bundles. This is the layer #252's read crashes went through untested: every unit test mocked the
 * repositories, and nothing called the controller twice.
 * <p>
 * H2 in default mode with jsonb as a TEXT domain: payload storage is checked as text here; the jsonb
 * round trip is TC-MCR-CACHE-033 on PostgreSQL. The bearer-token filter chain is checked by the boot
 * smoke test in the PR #272 execution record, not here.
 * <p>
 * Test IDs TC-MCR-CACHE-026…032 (Testing Lead, 2026-10-06, PR #272 review), TC-MCR-AUTHZ-038…040
 * (PR #310 author's, named by the Testing Lead, 2026-10-11), TC-MCR-AUTHZ-043…046 (Testing Lead,
 * 2026-10-11), TC-MCR-AUTHZ-047…068 (PR #326 author's, named by the Testing Lead, 2026-10-13) and
 * TC-MCR-AUTHZ-069…074 (Testing Lead, 2026-10-13) are permanent. Never
 * renumber, never reuse.
 */
@DataJpaTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@ActiveProfiles("test")
@ImportAutoConfiguration(JacksonAutoConfiguration.class)
@Import({EhrController.class, EhrService.class, MedicareRecordCache.class, EhrAuditLogger.class,
        MedicareProperties.class, MedicareStatusGate.class, MedicareAccessPolicy.class})
@TestPropertySource(properties = {"careconnect.medicare.mode=live", "careconnect.medicare.sandbox=true"})
class MedicareReadIntegrationTest {

    private static final IParser PARSER = ctxR4.newJsonParser();

    @MockitoBean
    MedicareService medicare;
    @MockitoBean
    MedicareConnectionService connections;

    @Autowired
    EhrController controller;
    @Autowired
    ObjectMapper objectMapper;
    @Autowired
    UserRepository users;
    @Autowired
    PatientRepository patients;
    @Autowired
    EhrSourceRepository sources;
    @Autowired
    EhrPatientCrosswalkRepository crosswalks;
    @Autowired
    EhrRawPayloadRepository rawPayloads;
    @Autowired
    EhrSourceIdentityRepository identities;
    @Autowired
    EhrCoverageRecordRepository coverages;
    @Autowired
    EhrVisitRecordRepository visits;
    @Autowired
    EhrAuditEventRepository auditEvents;
    @Autowired
    CaregiverPatientLinkRepository caregiverLinks;
    @Autowired
    FamilyMemberLinkRepository familyLinks;
    @Autowired
    ConsentGrantRepository consentGrants;

    private Long medicareId;
    private Patient patient1;
    private Patient patient2;

    @BeforeEach
    void seed() {
        medicareId = sources.findByCode("MEDICARE")
                .orElseGet(() -> sources.save(EhrSource.builder().code("MEDICARE").displayName("Medicare").build()))
                .getId();
        when(medicare.getId()).thenReturn(medicareId);
        patient1 = patient("pr272-patient1@example.test");
        patient2 = patient("pr272-patient2@example.test");
    }

    @AfterEach
    void signOut() {
        SecurityContextHolder.clearContext();
    }

    private Patient patient(final String email) {
        final User user = users.save(User.builder().email(email).password("not-a-real-hash").role(Role.PATIENT).build());
        return patients.save(Patient.builder().firstName("Synthetic").lastName("Patient").user(user).build());
    }

    private EhrPatientCrosswalk link(final Patient p, final String token) {
        final EhrPatientCrosswalk c = new EhrPatientCrosswalk();
        c.setPatientId(p.getId());
        c.setSourceId(medicareId);
        c.setExternalPatientId("-20140000008325-" + p.getId());
        c.setToken(token);
        final EhrPatientCrosswalk saved = crosswalks.save(c);
        if (token != null) {
            when(connections.requireAccessToken(any())).thenReturn("synthetic-token-not-a-secret");
        }
        return saved;
    }

    /**
     * A fresh context, not {@code getContext().setAuthentication(...)}: an earlier test class in the
     * same JVM thread can leave a mocked {@code SecurityContext} installed (ConfigControllerTest does),
     * and writing into that mock would leave nobody signed in here.
     */
    private static void signIn(final Patient p) {
        SecurityContextHolder.setContext(new SecurityContextImpl(
                new UsernamePasswordAuthenticationToken(p.getUser().getEmail(), null, List.of())));
    }

    private static <R extends Resource> List<R> fixture(final String file, final Class<R> type) {
        try (InputStream in = MedicareReadIntegrationTest.class.getResourceAsStream("/fixtures/bluebutton-synthetic/" + file)) {
            final Bundle bundle = PARSER.parseResource(Bundle.class, in);
            final List<R> out = new ArrayList<>();
            bundle.getEntry().forEach(e -> out.add(type.cast(e.getResource())));
            return out;
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    private void blueButtonServesFixtures() {
        when(medicare.requestMedicarePatientInfo(anyString()))
                .thenAnswer(inv -> fixture("patient-bundle.json", org.hl7.fhir.r4.model.Patient.class).get(0));
        when(medicare.requestMedicareCoverageInfo(anyString())).thenAnswer(inv -> fixture("coverage-bundle.json", Coverage.class));
        when(medicare.requestMedicareEOBInfo(anyString()))
                .thenAnswer(inv -> fixture("eob-bundle.json", ExplanationOfBenefit.class));
    }

    /** The body as the app receives it, through Spring Boot's ObjectMapper. */
    private JsonNode body(final ResponseEntity<Object> response) throws Exception {
        return objectMapper.readTree(objectMapper.writeValueAsString(response.getBody()));
    }

    private List<EhrAuditEvent> audits(final Patient p, final String type) {
        return auditEvents.findAll().stream()
                .filter(e -> e.getPatientId().equals(p.getId()) && e.getResourceType().equals(type))
                .toList();
    }

    @Test
    @DisplayName("TC-MCR-CACHE-026: the second Coverage load is served from the cache with 200, not 500, and Blue Button is asked once")
    void secondCoverageLoadIsServedFromTheCache() throws Exception {
        link(patient1, "enc");
        signIn(patient1);
        blueButtonServesFixtures();

        final ResponseEntity<Object> first = controller.fetchCoverage("medicare", null);
        final ResponseEntity<Object> second = controller.fetchCoverage("medicare", null);

        assertThat(first.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(second.getStatusCode()).isEqualTo(HttpStatus.OK);
        verify(medicare, times(1)).requestMedicareCoverageInfo(anyString());
        final JsonNode a = body(first);
        final JsonNode b = body(second);
        // Same resources; the order is not specified (fetch order first, newest-row order from the cache).
        assertThat(b.get("resources")).containsExactlyInAnyOrderElementsOf(a.get("resources"));
        assertThat(b.get("fetchedAt").asText()).as("fetchedAt is the retrieval, not the second request")
                .isEqualTo(a.get("fetchedAt").asText());
        assertThat(a.get("source").asText()).isEqualTo("MEDICARE");
        assertThat(a.get("mode").asText()).isEqualTo("live");
        assertThat(a.get("synthetic").asBoolean()).as("CMS sandbox data is synthetic").isTrue();
        assertThat(rawPayloads.findByPatientIdAndSourceIdAndResourceTypeOrderByRetrievedAtDescIdDesc(
                patient1.getId(), medicareId, "Coverage")).hasSize(3);
        assertThat(coverages.findAll()).hasSize(3)
                .allSatisfy(c -> assertThat(c.getExternalCoverageId()).doesNotContain("/"));
        assertThat(audits(patient1, "Coverage")).singleElement()
                .satisfies(e -> {
                    assertThat(e.getOutcome()).isEqualTo(EhrRetrievalOutcome.SUCCESS);
                    assertThat(e.getRecordCount()).isEqualTo(3);
                    assertThat(e.getActorUserId()).isEqualTo(patient1.getUser().getId());
                });
    }

    @Test
    @DisplayName("TC-MCR-CACHE-027: Patient, Coverage and visits come back as FHIR in the envelope, and cancelled or entered-in-error resources are not served (DEF-MCR-19)")
    void readsReturnGatedFhir() throws Exception {
        link(patient1, "enc");
        signIn(patient1);
        blueButtonServesFixtures();

        final JsonNode patient = body(controller.fetchIdentity("medicare", null));
        final JsonNode coverage = body(controller.fetchCoverage("medicare", null));
        final JsonNode visitsBody = body(controller.fetchVisits("medicare", null));

        assertThat(patient.get("total").asInt()).isEqualTo(1);
        assertThat(patient.at("/resources/0/resourceType").asText()).isEqualTo("Patient");
        assertThat(patient.at("/resources/0/birthDate").asText()).isEqualTo("1940-06-01");
        assertThat(identities.findByPatientIdAndSourceId(patient1.getId(), medicareId)).get()
                .satisfies(i -> assertThat(i.getDateOfBirth()).hasToString("1940-06-01"));
        // part-d is cancelled; carrier--22639159999 is entered-in-error. Both are stored, neither served.
        assertThat(coverage.get("total").asInt()).isEqualTo(2);
        assertThat(coverage.get("resources")).extracting(r -> r.get("id").asText())
                .containsExactlyInAnyOrder("part-a--20140000008325", "part-b--20140000008325");
        assertThat(visitsBody.get("total").asInt()).isEqualTo(2);
        assertThat(visitsBody.get("resources")).extracting(r -> r.get("resourceType").asText())
                .containsOnly("ExplanationOfBenefit");
        assertThat(visitsBody.get("resources")).extracting(r -> r.get("id").asText())
                .doesNotContain("carrier--22639159999");
        assertThat(visits.findAll()).hasSize(3);
    }

    @Test
    @DisplayName("TC-MCR-CACHE-028: no link, a pending link or another source gives 404, and Blue Button is not asked")
    void unlinkedPendingOrUnknownSourceIs404() {
        signIn(patient1);
        assertThat(controller.fetchCoverage("medicare", null).getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);

        link(patient1, null); // started, never completed: no token
        assertThat(controller.fetchVisits("medicare", null).getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
        assertThat(controller.fetchIdentity("medicare", null).getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
        assertThat(controller.fetchCoverage("athenahealth", null).getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);

        SecurityContextHolder.clearContext();
        assertThat(controller.fetchCoverage("medicare", null).getStatusCode()).as("nobody signed in").isEqualTo(HttpStatus.NOT_FOUND);
        verify(medicare, never()).requestMedicareCoverageInfo(anyString());
        verifyNoInteractions(connections);
    }

    @Test
    @DisplayName("TC-MCR-CACHE-029: one patient's cached Medicare data is never served to another patient, linked or not")
    void anotherPatientsCacheIsNotServed() throws Exception {
        link(patient1, "enc");
        signIn(patient1);
        blueButtonServesFixtures();
        controller.fetchCoverage("medicare", null);

        signIn(patient2);
        assertThat(controller.fetchCoverage("medicare", null).getStatusCode()).as("patient2 unlinked").isEqualTo(HttpStatus.NOT_FOUND);

        link(patient2, "enc2");
        when(medicare.requestMedicareCoverageInfo(anyString())).thenReturn(List.of());
        final JsonNode own = body(controller.fetchCoverage("medicare", null));
        assertThat(own.get("total").asInt()).as("patient2 sees only their own (empty) coverage").isZero();
        assertThat(audits(patient2, "Coverage")).singleElement()
                .satisfies(e -> assertThat(e.getOutcome()).isEqualTo(EhrRetrievalOutcome.EMPTY));
    }

    @Test
    @DisplayName("TC-MCR-CACHE-030: a Blue Button failure is persisted as a FAILURE audit row with no token or content, rethrown, and stores nothing")
    void failureIsAuditedAndNothingStored() {
        link(patient1, "enc");
        signIn(patient1);
        when(medicare.requestMedicareEOBInfo(anyString())).thenThrow(new InternalErrorException("HTTP 500 synthetic"));

        assertThatThrownBy(() -> controller.fetchVisits("medicare", null)).isInstanceOf(InternalErrorException.class);

        assertThat(rawPayloads.findAll()).isEmpty();
        assertThat(audits(patient1, "ExplanationOfBenefit")).singleElement().satisfies(e -> {
            assertThat(e.getOutcome()).isEqualTo(EhrRetrievalOutcome.FAILURE);
            assertThat(e.getRecordCount()).isNull();
            assertThat(String.valueOf(e.getDetails())).doesNotContain("synthetic-token").doesNotContain("HTTP 500");
        });
    }

    @Test
    @DisplayName("TC-MCR-CACHE-031: after unlink and relink inside the day, the reads return the patient's data again, not an empty list (DEF-MCR-15)")
    void relinkInsideTheDayReturnsData() throws Exception {
        final EhrPatientCrosswalk first = link(patient1, "enc");
        signIn(patient1);
        blueButtonServesFixtures();
        assertThat(body(controller.fetchCoverage("medicare", null)).get("total").asInt()).isEqualTo(2);
        assertThat(body(controller.fetchVisits("medicare", null)).get("total").asInt()).isEqualTo(2);

        // What MedicareConnectionService.disconnect deletes (FR-MCR-11, Addendum A1-Q1); the audit log stays.
        rawPayloads.deleteAllForPatientAndSource(patient1.getId(), medicareId);
        identities.deleteAllForPatientAndSource(patient1.getId(), medicareId);
        coverages.deleteAllForPatientAndSource(patient1.getId(), medicareId);
        visits.deleteAllForPatientAndSource(patient1.getId(), medicareId);
        crosswalks.delete(first);
        crosswalks.flush();
        link(patient1, "enc-relinked");

        assertThat(body(controller.fetchCoverage("medicare", null)).get("total").asInt()).isEqualTo(2);
        assertThat(body(controller.fetchVisits("medicare", null)).get("total").asInt()).isEqualTo(2);
        verify(medicare, times(2)).requestMedicareCoverageInfo(anyString());
    }

    @Test
    @DisplayName("TC-MCR-CACHE-032: freshness reads the newest SUCCESS or EMPTY event of that patient and type, skipping a newer FAILURE; payloads list newest first, by id on a tie")
    void derivedQueriesOrderAsTheCacheAssumes() {
        final OffsetDateTime t = OffsetDateTime.parse("2026-10-01T12:00:00Z");
        final Long p = patient1.getId();
        auditEvents.save(event(p, "Coverage", EhrRetrievalOutcome.SUCCESS, t.minusDays(2)));
        auditEvents.save(event(p, "Coverage", EhrRetrievalOutcome.EMPTY, t.minusDays(1)));
        auditEvents.save(event(p, "Coverage", EhrRetrievalOutcome.FAILURE, t));
        auditEvents.save(event(p, "ExplanationOfBenefit", EhrRetrievalOutcome.SUCCESS, t.plusHours(1)));
        auditEvents.save(event(patient2.getId(), "Coverage", EhrRetrievalOutcome.SUCCESS, t.plusHours(2)));

        assertThat(auditEvents.findFirstByPatientIdAndSourceAndResourceTypeAndOutcomeInOrderByEventTimeDesc(
                p, "MEDICARE", "Coverage", List.of(EhrRetrievalOutcome.SUCCESS, EhrRetrievalOutcome.EMPTY)))
                .get().satisfies(e -> {
                    assertThat(e.getOutcome()).isEqualTo(EhrRetrievalOutcome.EMPTY);
                    assertThat(e.getEventTime().toInstant()).isEqualTo(t.minusDays(1).toInstant());
                });

        final EhrRawPayload older = rawPayloads.save(payload(p, "c-1", t.minusDays(1)));
        final EhrRawPayload tieLow = rawPayloads.save(payload(p, "c-2", t));
        final EhrRawPayload tieHigh = rawPayloads.save(payload(p, "c-1", t));
        assertThat(rawPayloads.findByPatientIdAndSourceIdAndResourceTypeOrderByRetrievedAtDescIdDesc(p, medicareId, "Coverage"))
                .extracting(EhrRawPayload::getId)
                .containsExactly(tieHigh.getId(), tieLow.getId(), older.getId());
    }

    private static EhrAuditEvent event(final Long patientId, final String type, final EhrRetrievalOutcome outcome,
                                       final OffsetDateTime at) {
        return EhrAuditEvent.builder().patientId(patientId).source("MEDICARE").resourceType(type)
                .outcome(outcome).eventTime(at).build();
    }

    private EhrRawPayload payload(final Long patientId, final String externalId, final OffsetDateTime at) {
        final EhrRawPayload row = new EhrRawPayload();
        row.setPatientId(patientId);
        row.setSourceId(medicareId);
        row.setResourceType("Coverage");
        row.setExternalResourceId(externalId);
        row.setPayload("{\"resourceType\":\"Coverage\",\"id\":\"" + externalId + "\"}");
        row.setPhotoStripped(false);
        row.setRetrievedAt(at);
        return row;
    }

    // Caregiver reads by patientId over the real link and consent queries, through MedicareAccessPolicy:
    // the patient, or an assigned caregiver holding the patient's MEDICARE_VIEW grant; everyone else gets
    // the policy's one 404 (FR-MCR-16, FR-MCR-17, BR-02, NFR-DEG-03).

    private User account(final String email, final Role role) {
        return users.save(User.builder().email(email).password("not-a-real-hash").role(role).build());
    }

    private User caregiver(final String email) {
        return account(email, Role.CAREGIVER);
    }

    private void caregiverLink(final User caregiver, final Patient p, final CaregiverPatientLink.LinkStatus status,
                               final LocalDateTime expiresAt) {
        final CaregiverPatientLink l = new CaregiverPatientLink(caregiver, p.getUser(), p.getUser(),
                CaregiverPatientLink.LinkType.PERMANENT);
        l.setStatus(status);
        l.setExpiresAt(expiresAt);
        caregiverLinks.save(l);
    }

    private void grant(final Patient p, final User grantee, final String scope, final Instant expiresAt,
                       final Instant revokedAt) {
        final Instant now = Instant.now();
        consentGrants.save(ConsentGrant.builder()
                .patientUserId(p.getUser().getId())
                .granteeUserId(grantee.getId())
                .granteeRole(grantee.getRole().name())
                .scope(scope)
                .status(ConsentGrant.STATUS_ACTIVE)
                .grantedAt(now.minusSeconds(86_400))
                .expiresAt(expiresAt)
                .revokedAt(revokedAt)
                .createdAt(now)
                .updatedAt(now)
                .build());
    }

    private void medicareView(final Patient p, final User grantee) {
        grant(p, grantee, MedicareAccessPolicy.SCOPE_MEDICARE_VIEW, null, null);
    }

    private static void signIn(final User u) {
        SecurityContextHolder.setContext(new SecurityContextImpl(
                new UsernamePasswordAuthenticationToken(u.getEmail(), null, List.of())));
    }

    /** The access policy's refusal: one 404 with one message, whatever the reason. */
    private static void assertRefused(final ThrowingCallable read, final String who) {
        assertThatThrownBy(read).as(who)
                .isInstanceOf(AppException.class)
                .satisfies(e -> assertThat(((AppException) e).getStatus()).isEqualTo(HttpStatus.NOT_FOUND));
    }

    @Test
    @DisplayName("TC-MCR-AUTHZ-038: a caregiver with an active link and the patient's MEDICARE_VIEW grant reads the patient's coverage, and the audit row names the caregiver")
    void linkedCaregiverReadsPatientCoverage() throws Exception {
        link(patient1, "enc");
        final User cg = caregiver("cg-active@example.test");
        caregiverLink(cg, patient1, CaregiverPatientLink.LinkStatus.ACTIVE, null);
        medicareView(patient1, cg);
        signIn(cg);
        blueButtonServesFixtures();

        final ResponseEntity<Object> response = controller.fetchCoverage("medicare", patient1.getId());

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(body(response).get("total").asInt()).isEqualTo(2);
        assertThat(audits(patient1, "Coverage")).singleElement()
                .satisfies(e -> assertThat(e.getActorUserId()).isEqualTo(cg.getId()));
    }

    @Test
    @DisplayName("TC-MCR-AUTHZ-039: an expired, revoked or missing caregiver link is the policy's 404 even with a MEDICARE_VIEW grant, and Blue Button is never asked")
    void inactiveCaregiverLinksAreRefused() {
        link(patient1, "enc");
        final User expired = caregiver("cg-expired@example.test");
        caregiverLink(expired, patient1, CaregiverPatientLink.LinkStatus.ACTIVE, LocalDateTime.now().minusDays(1));
        final User revoked = caregiver("cg-revoked@example.test");
        caregiverLink(revoked, patient1, CaregiverPatientLink.LinkStatus.REVOKED, null);
        final User stranger = caregiver("cg-none@example.test");
        caregiverLink(stranger, patient2, CaregiverPatientLink.LinkStatus.ACTIVE, null);

        for (final User u : List.of(expired, revoked, stranger)) {
            medicareView(patient1, u);
            signIn(u);
            assertRefused(() -> controller.fetchVisits("medicare", patient1.getId()), u.getEmail());
        }
        verifyNoInteractions(medicare);
    }

    @Test
    @DisplayName("TC-MCR-AUTHZ-040: a patient asking for another patient's id gets the policy's 404, while their own id reads")
    void patientCannotReadAnotherPatient() {
        link(patient1, "enc");
        link(patient2, "enc");
        signIn(patient2);
        blueButtonServesFixtures();

        assertRefused(() -> controller.fetchCoverage("medicare", patient1.getId()), "patient2 asking for patient1");
        assertThat(controller.fetchCoverage("medicare", patient2.getId()).getStatusCode()).isEqualTo(HttpStatus.OK);
    }

    @Test
    @DisplayName("TC-MCR-AUTHZ-043: a caregiver with an active link but no live MEDICARE_VIEW grant (none, revoked, expired, or another scope's) gets the 404, and Blue Button is never asked (DEF-MCR-25)")
    void linkWithoutMedicareConsentIsRefused() {
        link(patient1, "enc");
        final User none = caregiver("cg-no-grant@example.test");
        final User revoked = caregiver("cg-grant-revoked@example.test");
        final User expired = caregiver("cg-grant-expired@example.test");
        final User otherScope = caregiver("cg-ai-only@example.test");
        for (final User u : List.of(none, revoked, expired, otherScope)) {
            caregiverLink(u, patient1, CaregiverPatientLink.LinkStatus.ACTIVE, null);
        }
        grant(patient1, revoked, MedicareAccessPolicy.SCOPE_MEDICARE_VIEW, null, Instant.now().minusSeconds(60));
        grant(patient1, expired, MedicareAccessPolicy.SCOPE_MEDICARE_VIEW, Instant.now().minusSeconds(60), null);
        grant(patient1, otherScope, ConsentGrant.SCOPE_AI_RETRIEVAL, null, null);

        for (final User u : List.of(none, revoked, expired, otherScope)) {
            signIn(u);
            assertRefused(() -> controller.fetchCoverage("medicare", patient1.getId()), u.getEmail());
        }
        verifyNoInteractions(medicare);
    }

    @Test
    @DisplayName("TC-MCR-AUTHZ-044: a family member with an active link, even holding a MEDICARE_VIEW grant, gets the 404 (characterization pending OQ-11; DEF-MCR-26)")
    void linkedFamilyMemberIsRefused() {
        link(patient1, "enc");
        final User family = account("family-linked@example.test", Role.FAMILY_MEMBER);
        familyLinks.save(new FamilyMemberLink(family, patient1.getUser(), patient1.getUser(), "Daughter"));
        medicareView(patient1, family);
        signIn(family);
        blueButtonServesFixtures();

        assertRefused(() -> controller.fetchIdentity("medicare", patient1.getId()), "linked family member");
        verifyNoInteractions(medicare);
    }

    @Test
    @DisplayName("TC-MCR-AUTHZ-045: an administrator gets the 404 for a patient's Medicare data, and Blue Button is never asked")
    void administratorIsRefused() {
        link(patient1, "enc");
        signIn(account("admin@example.test", Role.ADMIN));

        assertRefused(() -> controller.fetchVisits("medicare", patient1.getId()), "administrator");
        verifyNoInteractions(medicare);
    }

    @Test
    @DisplayName("TC-MCR-AUTHZ-046: over HTTP every refusal, including a patient id that does not exist, is the same 404 and body with no Medicare field (DEF-MCR-27)")
    void refusalsAreIndistinguishableOverHttp() throws Exception {
        link(patient1, "enc");
        final MockMvc mvc = MockMvcBuilders.standaloneSetup(controller)
                .setControllerAdvice(new GlobalExceptionHandler())
                .build();
        final User stranger = caregiver("cg-stranger-http@example.test");
        final User admin = account("admin-http@example.test", Role.ADMIN);
        final String patient = patient1.getId().toString();

        final List<MvcResult> refusals = new ArrayList<>();
        signIn(stranger);
        refusals.add(mvc.perform(get("/v1/api/medicare/coverage").param("patientId", patient)).andReturn());
        signIn(patient2);
        refusals.add(mvc.perform(get("/v1/api/medicare/visits").param("patientId", patient)).andReturn());
        signIn(admin);
        refusals.add(mvc.perform(get("/v1/api/medicare/patient").param("patientId", patient)).andReturn());
        signIn(stranger);
        refusals.add(mvc.perform(get("/v1/api/medicare/coverage").param("patientId", "987654321")).andReturn());

        assertThat(refusals).allSatisfy(r -> assertThat(r.getResponse().getStatus()).isEqualTo(404));
        final String first = refusals.get(0).getResponse().getContentAsString();
        assertThat(refusals).extracting(r -> r.getResponse().getContentAsString()).containsOnly(first);
        assertThat(objectMapper.readTree(first).has("resources")).isFalse();
        verifyNoInteractions(medicare);
    }

    // #324 (WBS 6.3.9): every way a caregiver-side caller can lack access, on each Medicare read
    // endpoint over HTTP. One result per case and endpoint, so a test report can name each line. The
    // IDs are written out, not derived from the enum order, so they never move. They refine SRS
    // TC-24.2 and 24.3; TC-24.4 is FR-MCR-18's, so the 24.x series is not extended.

    enum Refusal {
        NO_LINK("a caregiver with consent but no link"),
        NO_CONSENT("a linked caregiver with no MEDICARE_VIEW consent"),
        REVOKED_CONSENT("a linked caregiver whose consent was revoked"),
        EXPIRED_CONSENT("a linked caregiver whose consent expired"),
        EXPIRED_LINK("a caregiver with consent whose link expired"),
        WRONG_PATIENT("another patient's linked, consented caregiver"),
        FAMILY_MEMBER("a linked family member with consent"),
        REVOKED_LINK("a caregiver with consent whose link was revoked"),
        OTHER_SCOPE_CONSENT("a linked caregiver whose only consent is for another scope");

        private final String who;

        Refusal(final String who) {
            this.who = who;
        }

        @Override
        public String toString() {
            return who;
        }
    }

    static List<Arguments> refusals() {
        return List.of(
                Arguments.of("TC-MCR-AUTHZ-047", Refusal.NO_LINK, "coverage"),
                Arguments.of("TC-MCR-AUTHZ-048", Refusal.NO_LINK, "visits"),
                Arguments.of("TC-MCR-AUTHZ-049", Refusal.NO_LINK, "patient"),
                Arguments.of("TC-MCR-AUTHZ-050", Refusal.NO_CONSENT, "coverage"),
                Arguments.of("TC-MCR-AUTHZ-051", Refusal.NO_CONSENT, "visits"),
                Arguments.of("TC-MCR-AUTHZ-052", Refusal.NO_CONSENT, "patient"),
                Arguments.of("TC-MCR-AUTHZ-053", Refusal.REVOKED_CONSENT, "coverage"),
                Arguments.of("TC-MCR-AUTHZ-054", Refusal.REVOKED_CONSENT, "visits"),
                Arguments.of("TC-MCR-AUTHZ-055", Refusal.REVOKED_CONSENT, "patient"),
                Arguments.of("TC-MCR-AUTHZ-056", Refusal.EXPIRED_CONSENT, "coverage"),
                Arguments.of("TC-MCR-AUTHZ-057", Refusal.EXPIRED_CONSENT, "visits"),
                Arguments.of("TC-MCR-AUTHZ-058", Refusal.EXPIRED_CONSENT, "patient"),
                Arguments.of("TC-MCR-AUTHZ-059", Refusal.EXPIRED_LINK, "coverage"),
                Arguments.of("TC-MCR-AUTHZ-060", Refusal.EXPIRED_LINK, "visits"),
                Arguments.of("TC-MCR-AUTHZ-061", Refusal.EXPIRED_LINK, "patient"),
                Arguments.of("TC-MCR-AUTHZ-062", Refusal.WRONG_PATIENT, "coverage"),
                Arguments.of("TC-MCR-AUTHZ-063", Refusal.WRONG_PATIENT, "visits"),
                Arguments.of("TC-MCR-AUTHZ-064", Refusal.WRONG_PATIENT, "patient"),
                Arguments.of("TC-MCR-AUTHZ-065", Refusal.FAMILY_MEMBER, "coverage"),
                Arguments.of("TC-MCR-AUTHZ-066", Refusal.FAMILY_MEMBER, "visits"),
                Arguments.of("TC-MCR-AUTHZ-067", Refusal.FAMILY_MEMBER, "patient"),
                Arguments.of("TC-MCR-AUTHZ-069", Refusal.REVOKED_LINK, "coverage"),
                Arguments.of("TC-MCR-AUTHZ-070", Refusal.REVOKED_LINK, "visits"),
                Arguments.of("TC-MCR-AUTHZ-071", Refusal.REVOKED_LINK, "patient"),
                Arguments.of("TC-MCR-AUTHZ-072", Refusal.OTHER_SCOPE_CONSENT, "coverage"),
                Arguments.of("TC-MCR-AUTHZ-073", Refusal.OTHER_SCOPE_CONSENT, "visits"),
                Arguments.of("TC-MCR-AUTHZ-074", Refusal.OTHER_SCOPE_CONSENT, "patient"));
    }

    /** A grant as the consent API leaves it after a revoke: status REVOKED and revokedAt set. */
    private void revokedMedicareView(final Patient p, final User grantee) {
        final Instant now = Instant.now();
        consentGrants.save(ConsentGrant.builder()
                .patientUserId(p.getUser().getId())
                .granteeUserId(grantee.getId())
                .granteeRole(grantee.getRole().name())
                .scope(MedicareAccessPolicy.SCOPE_MEDICARE_VIEW)
                .status(ConsentGrant.STATUS_REVOKED)
                .grantedAt(now.minusSeconds(86_400))
                .revokedAt(now.minusSeconds(60))
                .createdAt(now)
                .updatedAt(now)
                .build());
    }

    /** Sets up {@code r}'s caller against patient1 and returns them. */
    private User refusedCaller(final Refusal r) {
        final User u = r == Refusal.FAMILY_MEMBER
                ? account("v324-family@example.test", Role.FAMILY_MEMBER)
                : caregiver("v324-" + r.name().toLowerCase() + "@example.test");
        switch (r) {
            case NO_LINK -> medicareView(patient1, u);
            case NO_CONSENT -> caregiverLink(u, patient1, CaregiverPatientLink.LinkStatus.ACTIVE, null);
            case REVOKED_CONSENT -> {
                caregiverLink(u, patient1, CaregiverPatientLink.LinkStatus.ACTIVE, null);
                revokedMedicareView(patient1, u);
            }
            case EXPIRED_CONSENT -> {
                caregiverLink(u, patient1, CaregiverPatientLink.LinkStatus.ACTIVE, null);
                grant(patient1, u, MedicareAccessPolicy.SCOPE_MEDICARE_VIEW, Instant.now().minusSeconds(60), null);
            }
            case EXPIRED_LINK -> {
                caregiverLink(u, patient1, CaregiverPatientLink.LinkStatus.ACTIVE, LocalDateTime.now().minusDays(1));
                medicareView(patient1, u);
            }
            case WRONG_PATIENT -> {
                caregiverLink(u, patient2, CaregiverPatientLink.LinkStatus.ACTIVE, null);
                medicareView(patient2, u);
            }
            case FAMILY_MEMBER -> {
                familyLinks.save(new FamilyMemberLink(u, patient1.getUser(), patient1.getUser(), "Son"));
                medicareView(patient1, u);
            }
            case REVOKED_LINK -> {
                caregiverLink(u, patient1, CaregiverPatientLink.LinkStatus.REVOKED, null);
                medicareView(patient1, u);
            }
            case OTHER_SCOPE_CONSENT -> {
                caregiverLink(u, patient1, CaregiverPatientLink.LinkStatus.ACTIVE, null);
                grant(patient1, u, ConsentGrant.SCOPE_AI_RETRIEVAL, null, null);
            }
        }
        return u;
    }

    private MockMvc httpMvc() {
        return MockMvcBuilders.standaloneSetup(controller)
                .setControllerAdvice(new GlobalExceptionHandler())
                .build();
    }

    private long storedMedicareRows() {
        return rawPayloads.count() + coverages.count() + visits.count() + identities.count();
    }

    @ParameterizedTest(name = "{0}: {1} gets the 404 on /v1/api/medicare/{2}")
    @MethodSource("refusals")
    void caregiverVerificationRefusalOverHttp(final String id, final Refusal r, final String read)
            throws Exception {
        link(patient1, "enc");
        link(patient2, "enc");
        final MockMvc mvc = httpMvc();
        final long rowsBefore = storedMedicareRows();
        signIn(refusedCaller(r));

        final MvcResult refused = mvc.perform(get("/v1/api/medicare/" + read)
                .param("patientId", patient1.getId().toString())).andReturn();
        // The same answer as for a patient that does not exist, so the refusal discloses nothing.
        final MvcResult noSuchPatient = mvc.perform(get("/v1/api/medicare/" + read)
                .param("patientId", "987654321")).andReturn();

        assertThat(refused.getResponse().getStatus()).isEqualTo(404);
        final String body = refused.getResponse().getContentAsString();
        assertThat(body).isEqualTo(noSuchPatient.getResponse().getContentAsString());
        assertThat(objectMapper.readTree(body).has("resources")).isFalse();
        assertThat(storedMedicareRows()).as("Medicare rows stored").isEqualTo(rowsBefore);
        verifyNoInteractions(medicare);
    }

    @Test
    @DisplayName("TC-MCR-AUTHZ-068: a linked caregiver holding the patient's MEDICARE_VIEW consent reads coverage, visits and patient over HTTP, with resources in each body, Blue Button asked and rows stored, so the refusals come from the policy and not the setup")
    void caregiverVerificationControlOverHttp() throws Exception {
        link(patient1, "enc");
        final MockMvc mvc = httpMvc();
        final User allowed = caregiver("v324-allowed@example.test");
        caregiverLink(allowed, patient1, CaregiverPatientLink.LinkStatus.ACTIVE, null);
        medicareView(patient1, allowed);
        signIn(allowed);
        blueButtonServesFixtures();
        final long rowsBefore = storedMedicareRows();

        for (final String read : List.of("coverage", "visits", "patient")) {
            final MvcResult ok = mvc.perform(get("/v1/api/medicare/" + read)
                    .param("patientId", patient1.getId().toString())).andReturn();
            assertThat(ok.getResponse().getStatus()).as(read).isEqualTo(200);
            // The field the refusals must not carry is present on success, so that check is not vacuous.
            assertThat(objectMapper.readTree(ok.getResponse().getContentAsString()).get("resources"))
                    .as(read).isNotEmpty();
        }
        assertThat(storedMedicareRows()).as("Medicare rows stored").isGreaterThan(rowsBefore);
        verify(medicare).requestMedicareCoverageInfo(anyString());
        verify(medicare).requestMedicareEOBInfo(anyString());
        verify(medicare).requestMedicarePatientInfo(anyString());
    }
}
