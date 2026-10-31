package com.careconnect.service.ehr;

import com.careconnect.config.OracleProperties;
import com.careconnect.model.Patient;
import com.careconnect.model.ehr.EhrSource;
import com.careconnect.model.ehr.MedicareProperties;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.ehr.EhrRawPayloadRepository;
import com.careconnect.repository.ehr.EhrResourceRepository;
import com.careconnect.repository.ehr.EhrSourceRepository;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.beans.factory.ObjectProvider;

import java.io.IOException;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Unit tests for {@link OracleSandboxIngestService}. Pure Mockito with a stubbed {@link HttpClient}
 * (supplied via the package-private test constructor) so the open-sandbox fetch branches — 2xx with
 * entries, non-2xx, no-entry bodies, and transport failure (synthetic fallback) — are all covered
 * without touching the network. Repositories and the mirror projector are mocked.
 */
class OracleSandboxIngestServiceTest {

    private static final long USER = 7L;
    private static final long PATIENT = 3L;

    private final OracleProperties oracle = new OracleProperties();
    private final EhrSourceRepository sourceRepo = mock(EhrSourceRepository.class);
    private final EhrRawPayloadRepository rawPayloadRepo = mock(EhrRawPayloadRepository.class);
    private final EhrResourceRepository resourceRepo = mock(EhrResourceRepository.class);
    private final PatientRepository patientRepository = mock(PatientRepository.class);
    private final EhrMirrorProjector projector = mock(EhrMirrorProjector.class);
    private final ObjectMapper mapper = new ObjectMapper();
    private final HttpClient http = mock(HttpClient.class);

    @SuppressWarnings("unchecked")
    private final ObjectProvider<OracleSandboxIngestService> selfProvider = mock(ObjectProvider.class);

    private final OracleSandboxIngestService service = new OracleSandboxIngestService(
            oracle, sourceRepo, rawPayloadRepo, resourceRepo, patientRepository, projector, mapper,
            selfProvider, http);

    private void wireSelfProxyAndSources() {
        when(selfProvider.getObject()).thenReturn(service);
        when(sourceRepo.findByCode(OracleProperties.SOURCE_ORACLE))
                .thenReturn(Optional.of(src(40L, OracleProperties.SOURCE_ORACLE)));
        when(sourceRepo.findByCode(MedicareProperties.SOURCE_MEDICARE))
                .thenReturn(Optional.of(src(20L, MedicareProperties.SOURCE_MEDICARE)));
        when(projector.projectForSource(eq(USER), eq(PATIENT), eq(OracleProperties.SOURCE_ORACLE)))
                .thenReturn(2);
        when(projector.projectForSource(eq(USER), eq(PATIENT), eq(MedicareProperties.SOURCE_MEDICARE)))
                .thenReturn(4);
        final Patient p = new Patient();
        p.setId(PATIENT);
        when(patientRepository.findByUserId(USER)).thenReturn(Optional.of(p));
    }

    private EhrSource src(final long id, final String code) {
        final EhrSource s = new EhrSource();
        s.setId(id);
        s.setCode(code);
        return s;
    }

    @SuppressWarnings("unchecked")
    private HttpResponse<String> response(final int status, final String body) {
        final HttpResponse<String> r = mock(HttpResponse.class);
        when(r.statusCode()).thenReturn(status);
        when(r.body()).thenReturn(body);
        return r;
    }

    private String bundle(final String type, final String id) {
        return "{\"resourceType\":\"Bundle\",\"entry\":[{\"resource\":{\"resourceType\":\"" + type
                + "\",\"id\":\"" + id + "\",\"status\":\"final\",\"code\":{\"text\":\"X\"}}}]}";
    }

    // --- guards ------------------------------------------------------------

    @Test
    void ingestAllThrowsWhenNoPatientRecord() {
        when(patientRepository.findByUserId(USER)).thenReturn(Optional.empty());
        assertThatThrownBy(() -> service.ingestAll(USER))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("No patient record");
    }

    @Test
    void persistAndMirrorReturnsErrorWhenSourceNotSeeded() {
        when(sourceRepo.findByCode("ORACLE_HEALTH")).thenReturn(Optional.empty());
        final Map<String, Object> result =
                service.persistAndMirror(USER, PATIENT, "ORACLE_HEALTH", List.of());
        assertThat(result).containsKey("error");
        verify(rawPayloadRepo, never()).save(any());
    }

    // --- fetch branches: 2xx-with-entries, non-2xx, no-entry, transport failure ---

    @Test
    void ingestAllCoversAllFetchBranchesAndMirrorsBothSources() throws Exception {
        wireSelfProxyAndSources();
        when(http.send(any(HttpRequest.class), any())).thenAnswer(inv -> {
            final String url = ((HttpRequest) inv.getArgument(0)).uri().toString();
            if (url.contains("/Condition")) {
                return response(500, "server error");                 // non-2xx branch
            }
            if (url.contains("/Observation")) {
                return response(200, "{\"resourceType\":\"Bundle\"}"); // 200 but no entry array
            }
            if (url.contains("/Immunization")) {
                throw new IOException("sandbox offline");              // transport-failure branch
            }
            // AllergyIntolerance + MedicationRequest -> 2xx with one entry each.
            final String type = url.substring(url.lastIndexOf('/') + 1, url.indexOf('?'));
            return response(200, bundle(type, type.toLowerCase() + "-1"));
        });

        final Map<String, Object> summary = service.ingestAll(USER);

        @SuppressWarnings("unchecked")
        final Map<String, Object> oracleSummary =
                (Map<String, Object>) summary.get(OracleProperties.SOURCE_ORACLE);
        assertThat(oracleSummary.get("rawPayloadsStored")).isEqualTo(2); // allergy + medication
        assertThat(oracleSummary.get("mirrorRows")).isEqualTo(2);
        @SuppressWarnings("unchecked")
        final Map<String, Object> medicareSummary =
                (Map<String, Object>) summary.get(MedicareProperties.SOURCE_MEDICARE);
        assertThat(medicareSummary.get("rawPayloadsStored")).isEqualTo(4); // synthetic claim set
        assertThat(medicareSummary.get("mirrorRows")).isEqualTo(4);

        // Idempotent re-ingest clears each source's prior rows first.
        verify(rawPayloadRepo).deleteByPatientIdAndSourceId(PATIENT, 40L);
        verify(resourceRepo).deleteByUserIdAndSource(USER, OracleProperties.SOURCE_ORACLE);
    }

    @Test
    void fallsBackToSyntheticOracleWhenSandboxIsUnreachable() throws Exception {
        wireSelfProxyAndSources();
        when(http.send(any(HttpRequest.class), any())).thenThrow(new IOException("offline"));

        final Map<String, Object> summary = service.ingestAll(USER);

        @SuppressWarnings("unchecked")
        final Map<String, Object> oracleSummary =
                (Map<String, Object>) summary.get(OracleProperties.SOURCE_ORACLE);
        // syntheticOracle() provides 5 resources.
        assertThat(oracleSummary.get("rawPayloadsStored")).isEqualTo(5);
    }

    // --- store-loop guards: missing type/id skipped, save failure survived ---

    @Test
    void persistAndMirrorSkipsIdlessResourcesAndSurvivesSaveFailure() {
        when(sourceRepo.findByCode(OracleProperties.SOURCE_ORACLE))
                .thenReturn(Optional.of(src(40L, OracleProperties.SOURCE_ORACLE)));
        when(projector.projectForSource(anyLong(), anyLong(), any())).thenReturn(0);
        when(rawPayloadRepo.save(any())).thenThrow(new RuntimeException("db down"));

        final JsonNode withId = mapper.createObjectNode()
                .put("resourceType", "Condition").put("id", "c1");
        final JsonNode noId = mapper.createObjectNode().put("resourceType", "Condition");
        final JsonNode noType = mapper.createObjectNode().put("id", "x"); // no resourceType -> skipped

        final Map<String, Object> result = service.persistAndMirror(
                USER, PATIENT, OracleProperties.SOURCE_ORACLE, List.of(withId, noId, noType));

        // withId attempted (save threw -> caught -> 0 stored), noId skipped before save.
        assertThat(result.get("rawPayloadsStored")).isEqualTo(0);
        assertThat(result.get("mirrorRows")).isEqualTo(0);
    }

    @Test
    void fetchFiltersOutMalformedBundleEntries() throws Exception {
        wireSelfProxyAndSources();
        final String mixed = "{\"resourceType\":\"Bundle\",\"entry\":["
                + "{\"noResource\":true},"                                             // entry without resource
                + "{\"resource\":{\"resourceType\":\"Observation\",\"id\":\"wrong\"}},"// type mismatch
                + "{\"resource\":{\"resourceType\":\"AllergyIntolerance\"}},"          // no id
                + "{\"resource\":{\"id\":\"nort\"}},"                                  // resource without resourceType
                + "{\"resource\":{\"resourceType\":\"AllergyIntolerance\",\"id\":\"a-ok\","
                + "\"code\":{\"text\":\"Pollen\"}}}]}";                                // the one valid entry
        when(http.send(any(HttpRequest.class), any())).thenAnswer(inv -> {
            final String url = ((HttpRequest) inv.getArgument(0)).uri().toString();
            return url.contains("/AllergyIntolerance")
                    ? response(200, mixed)
                    : response(200, "{\"resourceType\":\"Bundle\"}"); // other types: no entries
        });

        final Map<String, Object> summary = service.ingestAll(USER);

        @SuppressWarnings("unchecked")
        final Map<String, Object> oracleSummary =
                (Map<String, Object>) summary.get(OracleProperties.SOURCE_ORACLE);
        assertThat(oracleSummary.get("rawPayloadsStored")).isEqualTo(1); // only the valid entry survives
    }

    @Test
    void storesFetchedResourcesAsRawPayloads() {
        when(sourceRepo.findByCode(OracleProperties.SOURCE_ORACLE))
                .thenReturn(Optional.of(src(40L, OracleProperties.SOURCE_ORACLE)));
        when(projector.projectForSource(anyLong(), anyLong(), any())).thenReturn(1);

        final JsonNode obs = mapper.createObjectNode()
                .put("resourceType", "Observation").put("id", "o1").put("status", "final");

        final Map<String, Object> result = service.persistAndMirror(
                USER, PATIENT, OracleProperties.SOURCE_ORACLE, List.of(obs));

        assertThat(result.get("rawPayloadsStored")).isEqualTo(1);
        assertThat(result.get("mirrorRows")).isEqualTo(1);
        verify(rawPayloadRepo).save(any());
    }
}
