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
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

/**
 * The Medicare reads in live mode, the default: a linked patient gets FHIR from the cache in an
 * envelope, with the status gate applied, and anything else is a 404. Mock mode is
 * {@code EhrControllerMockModeTest}; the real cache and JPA layer underneath are
 * {@code MedicareReadIntegrationTest}.
 * <p>
 * Test IDs TC-MCR-CACHE-035..042 are permanent. Never renumber, never reuse.
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
    @DisplayName("TC-MCR-CACHE-035: a linked patient gets their Patient resource from the cache, labelled live and synthetic (sandbox), with the cache's fetchedAt")
    void linkedPatientRead() throws Exception {
        linked();
        final JsonNode patient = resource("{\"resourceType\":\"Patient\",\"id\":\"bene-1\"}");
        when(cache.patient(crosswalk, ACTOR)).thenReturn(new CachedRead(List.of(patient), FETCHED));

        final MedicareEnvelope body = envelope(controller.fetchIdentity("medicare"));

        assertThat(body.mode()).isEqualTo(MedicareProperties.MODE_LIVE);
        assertThat(body.synthetic()).isTrue();
        assertThat(body.total()).isEqualTo(1);
        assertThat(body.resources()).containsExactly(patient);
        assertThat(body.fetchedAt()).isEqualTo(FETCHED);
    }

    @Test
    @DisplayName("TC-MCR-CACHE-036: a linked patient with nothing cached or returned gets an empty single-resource envelope, not an error")
    void linkedPatientWithNoResource() {
        linked();
        when(cache.patient(crosswalk, ACTOR)).thenReturn(new CachedRead(List.of(), FETCHED));

        final MedicareEnvelope body = envelope(controller.fetchIdentity("medicare"));

        assertThat(body.total()).isZero();
        assertThat(body.resources()).isEmpty();
    }

    @Test
    @DisplayName("TC-MCR-CACHE-037: coverage goes through the status gate: a cancelled coverage is not served")
    void coverageIsGated() throws Exception {
        linked();
        final JsonNode active = resource("{\"resourceType\":\"Coverage\",\"id\":\"part-a\",\"status\":\"active\"}");
        final JsonNode cancelled = resource("{\"resourceType\":\"Coverage\",\"id\":\"part-d\",\"status\":\"cancelled\"}");
        when(cache.coverage(crosswalk, ACTOR)).thenReturn(new CachedRead(List.of(active, cancelled), FETCHED));

        final MedicareEnvelope body = envelope(controller.fetchCoverage("medicare"));

        assertThat(body.resources()).containsExactly(active);
        assertThat(body.total()).isEqualTo(1);
        assertThat(body.fetchedAt()).isEqualTo(FETCHED);
    }

    @Test
    @DisplayName("TC-MCR-CACHE-038: visits go through the status gate: an entered-in-error claim is not served")
    void visitsAreGated() throws Exception {
        linked();
        final JsonNode claim = resource("{\"resourceType\":\"ExplanationOfBenefit\",\"id\":\"c1\",\"status\":\"active\"}");
        final JsonNode voided = resource("{\"resourceType\":\"ExplanationOfBenefit\",\"id\":\"c2\",\"status\":\"entered-in-error\"}");
        when(cache.visits(crosswalk, ACTOR)).thenReturn(new CachedRead(List.of(claim, voided), FETCHED));

        assertThat(envelope(controller.fetchVisits("medicare")).resources()).containsExactly(claim);
    }

    @Test
    @DisplayName("TC-MCR-CACHE-039: no completed link is a 404 on every read, and the cache is never asked")
    void notLinkedIs404() {
        notLinked();

        assertThat(controller.fetchIdentity("medicare").getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
        assertThat(controller.fetchCoverage("medicare").getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
        assertThat(controller.fetchVisits("medicare").getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
        verifyNoInteractions(cache);
    }

    @Test
    @DisplayName("TC-MCR-CACHE-040: a source other than medicare is a 404, without looking anything up")
    void unknownSourceIs404() {
        assertThat(controller.fetchIdentity("athena").getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
        assertThat(controller.fetchCoverage("epic").getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
        assertThat(controller.fetchVisits("cerner").getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
        verifyNoInteractions(medicareService, ehrService, cache);
    }

    @Test
    @DisplayName("TC-MCR-CACHE-041: the source name is case-insensitive")
    void sourceIsCaseInsensitive() {
        notLinked();

        assertThat(controller.fetchCoverage("MEDICARE").getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
        assertThat(controller.fetchCoverage("Medicare").getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
    }

    @Test
    @DisplayName("TC-MCR-CACHE-042: production (sandbox off) data is not labelled synthetic")
    void productionIsNotSynthetic() {
        ReflectionTestUtils.setField(properties, "sandbox", false);
        linked();
        when(cache.coverage(crosswalk, ACTOR)).thenReturn(new CachedRead(List.of(), FETCHED));

        assertThat(envelope(controller.fetchCoverage("medicare")).synthetic()).isFalse();
    }
}
