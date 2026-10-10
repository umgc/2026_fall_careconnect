package com.careconnect.controller.ehr;

import com.careconnect.model.ehr.EhrPatientCrosswalk;
import com.careconnect.model.ehr.MedicareEnvelope;
import com.careconnect.model.ehr.MedicareProperties;
import com.careconnect.model.ehr.MedicareSource;
import com.careconnect.model.ehr.MedicareStatusGate;
import com.careconnect.service.ehr.EhrService;
import com.careconnect.service.ehr.MedicareRecordCache;
import com.careconnect.service.ehr.MedicareRecordCache.CachedRead;
import com.careconnect.service.ehr.MedicareService;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.test.util.ReflectionTestUtils;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

/**
 * The Medicare reads in live mode, the default: a linked patient gets FHIR from the cache in an
 * envelope, with the status gate applied, and anything else is a 404. Mock mode is
 * {@code EhrControllerMockModeTest}; the real cache and JPA layer underneath are
 * {@code MedicareReadIntegrationTest}. A {@code patientId} read is a caregiver or family member reading their
 * patient's data (FR-MCR-16, FR-MCR-17).
 */
@ExtendWith(MockitoExtension.class)
class EhrControllerTest {

    private static final long MEDICARE = 9L;
    private static final long ACTOR = 6L;
    private static final OffsetDateTime FETCHED = OffsetDateTime.parse("2026-10-07T09:00:00Z");
    private static final ObjectMapper JSON = new ObjectMapper();

    @Mock
    MedicareService medicareService;
    @Mock
    EhrService ehrService;
    @Mock
    MedicareRecordCache cache;
    @Mock
    ObjectProvider<MedicareSource> sources;

    private final MedicareProperties properties = new MedicareProperties();
    private EhrController controller;
    private EhrPatientCrosswalk crosswalk;

    @BeforeEach
    void setUp() {
        controller = new EhrController();
        ReflectionTestUtils.setField(controller, "medicareService", medicareService);
        ReflectionTestUtils.setField(controller, "ehrService", ehrService);
        ReflectionTestUtils.setField(controller, "cache", cache);
        ReflectionTestUtils.setField(controller, "properties", properties);
        ReflectionTestUtils.setField(controller, "statusGate", new MedicareStatusGate());
        ReflectionTestUtils.setField(controller, "sources", sources);
        ReflectionTestUtils.setField(properties, "mode", MedicareProperties.MODE_LIVE);
        ReflectionTestUtils.setField(properties, "sandbox", true);
        crosswalk = new EhrPatientCrosswalk();
        crosswalk.setPatientId(2L);
        crosswalk.setSourceId(MEDICARE);
    }

    private void linked() {
        when(medicareService.getId()).thenReturn(MEDICARE);
        when(ehrService.getCrosswalk(MEDICARE)).thenReturn(Optional.of(crosswalk));
        when(ehrService.currentUserId()).thenReturn(Optional.of(ACTOR));
    }

    private void notLinked() {
        when(medicareService.getId()).thenReturn(MEDICARE);
        when(ehrService.getCrosswalk(MEDICARE)).thenReturn(Optional.empty());
    }

    private static JsonNode resource(final String json) throws Exception {
        return JSON.readTree(json);
    }

    private static MedicareEnvelope envelope(final ResponseEntity<Object> response) {
        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        return (MedicareEnvelope) response.getBody();
    }

    @Test
    @DisplayName("a linked patient gets their Patient resource from the cache, labelled live and synthetic (sandbox), with the cache's fetchedAt")
    void linkedPatientRead() throws Exception {
        linked();
        final JsonNode patient = resource("{\"resourceType\":\"Patient\",\"id\":\"bene-1\"}");
        when(cache.patient(crosswalk, ACTOR)).thenReturn(new CachedRead(List.of(patient), FETCHED));

        final MedicareEnvelope body = envelope(controller.fetchIdentity("medicare", null));

        assertThat(body.mode()).isEqualTo(MedicareProperties.MODE_LIVE);
        assertThat(body.synthetic()).isTrue();
        assertThat(body.total()).isEqualTo(1);
        assertThat(body.resources()).containsExactly(patient);
        assertThat(body.fetchedAt()).isEqualTo(FETCHED);
    }

    @Test
    @DisplayName("a linked patient with nothing cached or returned gets an empty single-resource envelope, not an error")
    void linkedPatientWithNoResource() {
        linked();
        when(cache.patient(crosswalk, ACTOR)).thenReturn(new CachedRead(List.of(), FETCHED));

        final MedicareEnvelope body = envelope(controller.fetchIdentity("medicare", null));

        assertThat(body.total()).isZero();
        assertThat(body.resources()).isEmpty();
    }

    @Test
    @DisplayName("coverage goes through the status gate: a cancelled coverage is not served")
    void coverageIsGated() throws Exception {
        linked();
        final JsonNode active = resource("{\"resourceType\":\"Coverage\",\"id\":\"part-a\",\"status\":\"active\"}");
        final JsonNode cancelled = resource("{\"resourceType\":\"Coverage\",\"id\":\"part-d\",\"status\":\"cancelled\"}");
        when(cache.coverage(crosswalk, ACTOR)).thenReturn(new CachedRead(List.of(active, cancelled), FETCHED));

        final MedicareEnvelope body = envelope(controller.fetchCoverage("medicare", null));

        assertThat(body.resources()).containsExactly(active);
        assertThat(body.total()).isEqualTo(1);
        assertThat(body.fetchedAt()).isEqualTo(FETCHED);
    }

    @Test
    @DisplayName("visits go through the status gate: an entered-in-error claim is not served")
    void visitsAreGated() throws Exception {
        linked();
        final JsonNode claim = resource("{\"resourceType\":\"ExplanationOfBenefit\",\"id\":\"c1\",\"status\":\"active\"}");
        final JsonNode voided = resource("{\"resourceType\":\"ExplanationOfBenefit\",\"id\":\"c2\",\"status\":\"entered-in-error\"}");
        when(cache.visits(crosswalk, ACTOR)).thenReturn(new CachedRead(List.of(claim, voided), FETCHED));

        assertThat(envelope(controller.fetchVisits("medicare", null)).resources()).containsExactly(claim);
    }

    @Test
    @DisplayName("no completed link is a 404 on every read, and the cache is never asked")
    void notLinkedIs404() {
        notLinked();

        assertThat(controller.fetchIdentity("medicare", null).getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
        assertThat(controller.fetchCoverage("medicare", null).getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
        assertThat(controller.fetchVisits("medicare", null).getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
        verifyNoInteractions(cache);
    }

    @Test
    @DisplayName("a source other than medicare is a 404, without looking anything up")
    void unknownSourceIs404() {
        assertThat(controller.fetchIdentity("athena", null).getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
        assertThat(controller.fetchCoverage("epic", null).getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
        assertThat(controller.fetchVisits("cerner", null).getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
        verifyNoInteractions(medicareService, ehrService, cache);
    }

    @Test
    @DisplayName("the source name is case-insensitive")
    void sourceIsCaseInsensitive() {
        notLinked();

        assertThat(controller.fetchCoverage("MEDICARE", null).getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
        assertThat(controller.fetchCoverage("Medicare", null).getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
    }

    @Test
    @DisplayName("production (sandbox off) data is not labelled synthetic")
    void productionIsNotSynthetic() {
        ReflectionTestUtils.setField(properties, "sandbox", false);
        linked();
        when(cache.coverage(crosswalk, ACTOR)).thenReturn(new CachedRead(List.of(), FETCHED));

        assertThat(envelope(controller.fetchCoverage("medicare", null)).synthetic()).isFalse();
    }

    private static final long PATIENT = 2L;
    private static final long CAREGIVER = 12L;

    private void caregiverAllowed() {
        when(ehrService.canReadMedicareFor(PATIENT)).thenReturn(true);
        when(medicareService.getId()).thenReturn(MEDICARE);
        when(ehrService.getCrosswalkForPatient(PATIENT, MEDICARE)).thenReturn(Optional.of(crosswalk));
        when(ehrService.currentUserId()).thenReturn(Optional.of(CAREGIVER));
    }

    @Test
    @DisplayName("a linked caregiver reads the patient's coverage, and the cache records the caregiver as the acting user")
    void linkedCaregiverReadsCoverage() throws Exception {
        caregiverAllowed();
        final JsonNode active = resource("{\"resourceType\":\"Coverage\",\"id\":\"part-a\",\"status\":\"active\"}");
        when(cache.coverage(crosswalk, CAREGIVER)).thenReturn(new CachedRead(List.of(active), FETCHED));

        final MedicareEnvelope body = envelope(controller.fetchCoverage("medicare", PATIENT));

        assertThat(body.resources()).containsExactly(active);
        verify(ehrService, never()).getCrosswalk(anyLong());
    }

    @Test
    @DisplayName("a linked caregiver reads the patient's identity and visits through the same patient lookup")
    void linkedCaregiverReadsIdentityAndVisits() throws Exception {
        caregiverAllowed();
        final JsonNode patient = resource("{\"resourceType\":\"Patient\",\"id\":\"bene-1\"}");
        final JsonNode claim = resource("{\"resourceType\":\"ExplanationOfBenefit\",\"id\":\"c1\",\"status\":\"active\"}");
        when(cache.patient(crosswalk, CAREGIVER)).thenReturn(new CachedRead(List.of(patient), FETCHED));
        when(cache.visits(crosswalk, CAREGIVER)).thenReturn(new CachedRead(List.of(claim), FETCHED));

        assertThat(envelope(controller.fetchIdentity("medicare", PATIENT)).resources()).containsExactly(patient);
        assertThat(envelope(controller.fetchVisits("medicare", PATIENT)).resources()).containsExactly(claim);
    }

    @Test
    @DisplayName("a caller without access to the patient gets a 403 on every read, and nothing is looked up or retrieved")
    void noAccessIs403() {
        when(ehrService.canReadMedicareFor(PATIENT)).thenReturn(false);

        for (final ResponseEntity<Object> response : List.of(
                controller.fetchIdentity("medicare", PATIENT),
                controller.fetchCoverage("medicare", PATIENT),
                controller.fetchVisits("medicare", PATIENT))) {
            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
            assertThat(response.getBody()).isEqualTo(Map.of("source", MedicareProperties.SOURCE_MEDICARE, "error", "medicare_forbidden"));
        }
        verify(ehrService, never()).getCrosswalkForPatient(anyLong(), anyLong());
        verifyNoInteractions(cache, medicareService);
    }

    @Test
    @DisplayName("an allowed caregiver whose patient never connected Medicare gets a 404, as the patient would")
    void allowedButPatientNotConnectedIs404() {
        when(ehrService.canReadMedicareFor(PATIENT)).thenReturn(true);
        when(medicareService.getId()).thenReturn(MEDICARE);
        when(ehrService.getCrosswalkForPatient(PATIENT, MEDICARE)).thenReturn(Optional.empty());

        assertThat(controller.fetchCoverage("medicare", PATIENT).getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
        verifyNoInteractions(cache);
    }

    @Test
    @DisplayName("without a patientId the read is the caller's own and the access check is not consulted")
    void ownReadSkipsAccessCheck() {
        notLinked();

        controller.fetchVisits("medicare", null);

        verify(ehrService, never()).canReadMedicareFor(any());
    }

    @Test
    @DisplayName("mock mode still refuses a caller without access to the patient, before serving any fixture")
    void mockModeStillChecksAccess() {
        ReflectionTestUtils.setField(properties, "mode", MedicareProperties.MODE_MOCK);
        when(ehrService.canReadMedicareFor(PATIENT)).thenReturn(false);

        assertThat(controller.fetchCoverage("medicare", PATIENT).getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
        verifyNoInteractions(sources);
    }
}
