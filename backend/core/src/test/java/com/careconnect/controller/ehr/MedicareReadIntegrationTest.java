package com.careconnect.controller.ehr;

import ca.uhn.fhir.parser.IParser;
import ca.uhn.fhir.rest.server.exceptions.InternalErrorException;
import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.model.ehr.EhrAuditEvent;
import com.careconnect.model.ehr.EhrPatientCrosswalk;
import com.careconnect.model.ehr.EhrRawPayload;
import com.careconnect.model.ehr.EhrRetrievalOutcome;
import com.careconnect.model.ehr.EhrSource;
import com.careconnect.model.ehr.MedicareProperties;
import com.careconnect.model.ehr.MedicareStatusGate;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.UserRepository;
import com.careconnect.repository.ehr.EhrAuditEventRepository;
import com.careconnect.repository.ehr.EhrCoverageRecordRepository;
import com.careconnect.repository.ehr.EhrPatientCrosswalkRepository;
import com.careconnect.repository.ehr.EhrRawPayloadRepository;
import com.careconnect.repository.ehr.EhrSourceIdentityRepository;
import com.careconnect.repository.ehr.EhrSourceRepository;
import com.careconnect.repository.ehr.EhrVisitRecordRepository;
import com.careconnect.security.Role;
import com.careconnect.service.ehr.EhrAuditLogger;
import com.careconnect.service.ehr.EhrService;
import com.careconnect.service.ehr.MedicareConnectionService;
import com.careconnect.service.ehr.MedicareRecordCache;
import com.careconnect.service.ehr.MedicareService;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.hl7.fhir.r4.model.Bundle;
import org.hl7.fhir.r4.model.Coverage;
import org.hl7.fhir.r4.model.ExplanationOfBenefit;
import org.hl7.fhir.r4.model.Resource;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
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

import java.io.IOException;
import java.io.InputStream;
import java.io.UncheckedIOException;
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
 * Test IDs TC-MCR-CACHE-026…032 are permanent (Testing Lead, 2026-10-06, PR #272 review). Never
 * renumber, never reuse.
 */
@DataJpaTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@ActiveProfiles("test")
@ImportAutoConfiguration(JacksonAutoConfiguration.class)
@Import({EhrController.class, EhrService.class, MedicareRecordCache.class, EhrAuditLogger.class,
        MedicareProperties.class, MedicareStatusGate.class})
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

        final ResponseEntity<Object> first = controller.fetchCoverage("medicare");
        final ResponseEntity<Object> second = controller.fetchCoverage("medicare");

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

        final JsonNode patient = body(controller.fetchIdentity("medicare"));
        final JsonNode coverage = body(controller.fetchCoverage("medicare"));
        final JsonNode visitsBody = body(controller.fetchVisits("medicare"));

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
        assertThat(controller.fetchCoverage("medicare").getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);

        link(patient1, null); // started, never completed: no token
        assertThat(controller.fetchVisits("medicare").getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
        assertThat(controller.fetchIdentity("medicare").getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
        assertThat(controller.fetchCoverage("athenahealth").getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);

        SecurityContextHolder.clearContext();
        assertThat(controller.fetchCoverage("medicare").getStatusCode()).as("nobody signed in").isEqualTo(HttpStatus.NOT_FOUND);
        verify(medicare, never()).requestMedicareCoverageInfo(anyString());
        verifyNoInteractions(connections);
    }

    @Test
    @DisplayName("TC-MCR-CACHE-029: one patient's cached Medicare data is never served to another patient, linked or not")
    void anotherPatientsCacheIsNotServed() throws Exception {
        link(patient1, "enc");
        signIn(patient1);
        blueButtonServesFixtures();
        controller.fetchCoverage("medicare");

        signIn(patient2);
        assertThat(controller.fetchCoverage("medicare").getStatusCode()).as("patient2 unlinked").isEqualTo(HttpStatus.NOT_FOUND);

        link(patient2, "enc2");
        when(medicare.requestMedicareCoverageInfo(anyString())).thenReturn(List.of());
        final JsonNode own = body(controller.fetchCoverage("medicare"));
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

        assertThatThrownBy(() -> controller.fetchVisits("medicare")).isInstanceOf(InternalErrorException.class);

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
        assertThat(body(controller.fetchCoverage("medicare")).get("total").asInt()).isEqualTo(2);
        assertThat(body(controller.fetchVisits("medicare")).get("total").asInt()).isEqualTo(2);

        // What MedicareConnectionService.disconnect deletes (FR-MCR-11, Addendum A1-Q1); the audit log stays.
        rawPayloads.deleteAllForPatientAndSource(patient1.getId(), medicareId);
        identities.deleteAllForPatientAndSource(patient1.getId(), medicareId);
        coverages.deleteAllForPatientAndSource(patient1.getId(), medicareId);
        visits.deleteAllForPatientAndSource(patient1.getId(), medicareId);
        crosswalks.delete(first);
        crosswalks.flush();
        link(patient1, "enc-relinked");

        assertThat(body(controller.fetchCoverage("medicare")).get("total").asInt()).isEqualTo(2);
        assertThat(body(controller.fetchVisits("medicare")).get("total").asInt()).isEqualTo(2);
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
}
