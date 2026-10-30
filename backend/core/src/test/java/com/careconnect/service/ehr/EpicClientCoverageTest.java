package com.careconnect.service.ehr;

import com.careconnect.client.ehr.EhrApiClient;
import com.careconnect.config.EpicProperties;
import com.careconnect.dto.ehr.EpicTokenResponse;
import com.careconnect.model.Patient;
import com.careconnect.model.ehr.EhrAppointmentRecord;
import com.careconnect.model.ehr.EhrCredential;
import com.careconnect.model.ehr.EhrPatientCrosswalk;
import com.careconnect.model.ehr.EhrRawPayload;
import com.careconnect.model.ehr.EhrSource;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.ehr.EhrAppointmentRecordRepository;
import com.careconnect.repository.ehr.EhrCredentialRepository;
import com.careconnect.repository.ehr.EhrPatientCrosswalkRepository;
import com.careconnect.repository.ehr.EhrRawPayloadRepository;
import com.careconnect.repository.ehr.EhrSourceRepository;
import com.careconnect.security.TokenCryptor;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.client.HttpClientErrorException;
import org.springframework.web.client.RestTemplate;

import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class EpicClientCoverageTest {

    private final ObjectMapper mapper = new ObjectMapper();

    private JsonNode json(String s) throws Exception {
        return mapper.readTree(s);
    }

    @Test
    void fetchReadAndErrorPathsAreAudited() throws Exception {
        RestTemplate http = mock(RestTemplate.class);
        EpicProperties cfg = mock(EpicProperties.class);
        EpicOAuthService oauth = mock(EpicOAuthService.class);
        EhrAuditService audit = mock(EhrAuditService.class);
        when(cfg.getFhirBaseUrl()).thenReturn("https://fhir/api/R4");
        when(oauth.validAccessToken(1L)).thenReturn("tok");
        when(oauth.patientFhirId(1L)).thenReturn("pat-1");
        EpicFhirClient client = new EpicFhirClient(http, cfg, oauth, audit);
        assertThat(client.sourceCode()).isEqualTo(EpicProperties.SOURCE_EPIC);

        JsonNode bundle = json("{\"resourceType\":\"Bundle\",\"entry\":["
                + "{\"resource\":{\"resourceType\":\"Condition\",\"id\":\"c1\"}},"
                + "{\"resource\":null},{\"x\":1},"
                + "{\"resource\":{\"resourceType\":\"OperationOutcome\",\"issue\":["
                + "{\"severity\":\"warning\",\"code\":\"info\",\"diagnostics\":\"missing param\"},"
                + "{\"severity\":\"info\",\"details\":{\"text\":\"more\"}}]}},"
                + "{\"resource\":{\"resourceType\":\"OperationOutcome\"}},"
                + "{\"resource\":{\"id\":\"no-type\"}}]}");
        when(http.exchange(anyString(), eq(HttpMethod.GET), any(HttpEntity.class), eq(JsonNode.class)))
                .thenReturn(ResponseEntity.ok(bundle))
                .thenReturn(ResponseEntity.ok(json("{\"resourceType\":\"Bundle\"}")))
                .thenReturn(ResponseEntity.ok(json("{\"resourceType\":\"Patient\",\"id\":\"pat-1\"}")))
                .thenReturn(ResponseEntity.ok(json("{\"resourceType\":\"Bundle\"}")));
        assertThat(client.fetch(1L, "Condition", Map.of("category", "problem"))).hasSize(4);
        assertThat(client.fetch(1L, "Condition", null)).isEmpty();
        assertThat(client.read(1L, "Patient", "pat-1")).hasSize(1);
        assertThat(client.read(1L, "Patient", "pat-1")).isEmpty();

        HttpHeaders headers = new HttpHeaders();
        headers.add("WWW-Authenticate", "Bearer error=insufficient_scope");
        HttpClientErrorException forbidden = HttpClientErrorException.create(HttpStatus.FORBIDDEN, "Forbidden",
                headers, "{}".getBytes(StandardCharsets.UTF_8), StandardCharsets.UTF_8);
        when(http.exchange(anyString(), eq(HttpMethod.GET), any(HttpEntity.class), eq(JsonNode.class)))
                .thenThrow(forbidden);
        assertThatThrownBy(() -> client.fetch(1L, "Condition", null)).isSameAs(forbidden);

        when(http.exchange(anyString(), eq(HttpMethod.GET), any(HttpEntity.class), eq(JsonNode.class)))
                .thenThrow(new IllegalStateException("boom"));
        assertThatThrownBy(() -> client.fetch(1L, "Condition", null)).isInstanceOf(IllegalStateException.class);
        assertThatThrownBy(() -> client.read(1L, "Patient", "p")).isInstanceOf(IllegalStateException.class);
        assertThatThrownBy(() -> client.everything(1L)).isInstanceOf(IllegalStateException.class);

        assertThat(EpicFhirClient.nextLink(null)).isNull();
        assertThat(EpicFhirClient.nextLink(json("{\"link\":[{\"relation\":\"self\",\"url\":\"u\"}]}"))).isNull();
    }

    @Test
    void auditServiceRecordsAndFailsSoft() {
        EhrAuditLogger logger = mock(EhrAuditLogger.class);
        PatientRepository patients = mock(PatientRepository.class);
        Patient p = new Patient();
        p.setId(5L);
        when(patients.findByUserId(1L)).thenReturn(Optional.of(p));
        when(patients.findByUserId(2L)).thenReturn(Optional.empty());
        EhrAuditService audit = new EhrAuditService(logger, patients);
        audit.record(1L, "EPIC", "EPIC_FETCH", "Condition", "detail", EhrAuditService.OUTCOME_OK);
        audit.record(1L, "EPIC", "EPIC_FETCH", null, null, EhrAuditService.OUTCOME_EMPTY);
        audit.record(1L, "EPIC", null, "X", null, "RETRY");
        audit.record(1L, "EPIC", "E", "other");
        audit.record(1L, "EPIC", "E", null);
        audit.record(2L, "EPIC", "E", "OK");
        when(patients.findByUserId(3L)).thenThrow(new RuntimeException("db"));
        audit.record(3L, "EPIC", "E", "OK");
        verify(logger, org.mockito.Mockito.times(5)).log(anyLong(), anyString(), anyString(), any(), anyLong(), any(), any());
    }

    @Test
    void oauthTokenLifecycle() {
        RestTemplate http = mock(RestTemplate.class);
        EpicProperties cfg = mock(EpicProperties.class);
        TokenCryptor crypto = mock(TokenCryptor.class);
        EhrCredentialRepository repo = mock(EhrCredentialRepository.class);
        EhrAuditService audit = mock(EhrAuditService.class);
        when(cfg.getFhirBaseUrl()).thenReturn("https://fhir.epic.com/interconnect-fhir-oauth/api/FHIR/R4");
        when(cfg.getClientId()).thenReturn("cid");
        when(crypto.decrypt(anyString())).thenAnswer(inv -> "plain-" + inv.getArgument(0));
        when(crypto.encrypt(anyString())).thenAnswer(inv -> "enc-" + inv.getArgument(0));
        EpicOAuthService svc = new EpicOAuthService(http, cfg, crypto, repo, audit);

        EhrCredential fresh = new EhrCredential();
        fresh.setAccessTokenEnc("a");
        fresh.setPatientFhirId("pat-9");
        fresh.setExpiresAt(Instant.now().plusSeconds(3600));
        when(repo.findFirstByUserIdAndSourceOrderByIdDesc(1L, EpicProperties.SOURCE_EPIC)).thenReturn(Optional.of(fresh));
        assertThat(svc.validAccessToken(1L)).isEqualTo("plain-a");
        assertThat(svc.patientFhirId(1L)).isEqualTo("pat-9");

        EhrCredential noRefresh = new EhrCredential();
        when(repo.findFirstByUserIdAndSourceOrderByIdDesc(2L, EpicProperties.SOURCE_EPIC)).thenReturn(Optional.of(noRefresh));
        assertThatThrownBy(() -> svc.validAccessToken(2L)).isInstanceOf(IllegalStateException.class);

        EhrCredential expired = new EhrCredential();
        expired.setRefreshTokenEnc("r");
        expired.setExpiresAt(Instant.now().minusSeconds(10));
        when(repo.findFirstByUserIdAndSourceOrderByIdDesc(3L, EpicProperties.SOURCE_EPIC)).thenReturn(Optional.of(expired));
        when(http.getForObject(anyString(), eq(JsonNode.class))).thenReturn(null);
        when(http.postForEntity(anyString(), any(HttpEntity.class), eq(EpicTokenResponse.class)))
                .thenReturn(ResponseEntity.ok(new EpicTokenResponse("new", "newr", "Bearer", 60L, "s", "p")))
                .thenReturn(ResponseEntity.ok(new EpicTokenResponse("new2", null, "Bearer", null, null, null)))
                .thenReturn(ResponseEntity.ok(new EpicTokenResponse(null, null, null, null, null, null)))
                .thenReturn(ResponseEntity.status(HttpStatus.BAD_REQUEST).build());
        assertThat(svc.validAccessToken(3L)).isEqualTo("plain-enc-new");
        expired.setExpiresAt(null);
        assertThat(svc.validAccessToken(3L)).isEqualTo("plain-enc-new2");
        expired.setExpiresAt(null);
        assertThatThrownBy(() -> svc.validAccessToken(3L)).isInstanceOf(IllegalStateException.class);
        expired.setExpiresAt(null);
        assertThatThrownBy(() -> svc.validAccessToken(3L)).isInstanceOf(IllegalStateException.class);

        when(cfg.isConfidentialClient()).thenReturn(true);
        when(cfg.getClientSecret()).thenReturn("secret");
        when(http.postForEntity(anyString(), any(HttpEntity.class), eq(EpicTokenResponse.class)))
                .thenThrow(HttpClientErrorException.create(HttpStatus.BAD_REQUEST, "Bad", new HttpHeaders(),
                        "{\"error\":\"invalid_grant\"}".getBytes(StandardCharsets.UTF_8), StandardCharsets.UTF_8));
        expired.setExpiresAt(null);
        assertThatThrownBy(() -> svc.validAccessToken(3L)).isInstanceOf(HttpClientErrorException.class);

        when(repo.findFirstByUserIdAndSourceOrderByIdDesc(4L, EpicProperties.SOURCE_EPIC)).thenReturn(Optional.empty());
        assertThatThrownBy(() -> svc.patientFhirId(4L)).isInstanceOf(IllegalStateException.class);

        when(repo.findByUserIdAndSource(1L, EpicProperties.SOURCE_EPIC)).thenReturn(List.of(fresh));
        when(repo.findByUserIdAndSource(2L, EpicProperties.SOURCE_EPIC)).thenReturn(List.of());
        svc.disconnect(1L);
        svc.disconnect(2L);
        verify(repo).deleteAll(List.of(fresh));
    }

    @Test
    void appointmentSyncStoresRawPayloadAndUpserts() throws Exception {
        EhrSourceRepository sources = mock(EhrSourceRepository.class);
        EhrPatientCrosswalkRepository crosswalks = mock(EhrPatientCrosswalkRepository.class);
        EhrRawPayloadRepository raws = mock(EhrRawPayloadRepository.class);
        EhrAppointmentRecordRepository appts = mock(EhrAppointmentRecordRepository.class);
        EhrApiClient api = mock(EhrApiClient.class);
        EhrAppointmentSyncService svc = new EhrAppointmentSyncService(sources, crosswalks, raws, appts, mapper);

        Patient patient = new Patient();
        patient.setId(1L);
        EhrSource source = new EhrSource();
        source.setId(2L);
        source.setCode("EPIC");
        when(api.sourceCode()).thenReturn("EPIC");
        when(sources.findByCode("EPIC")).thenReturn(Optional.of(source));
        EhrPatientCrosswalk cw = new EhrPatientCrosswalk();
        cw.setExternalPatientId("ext-1");
        when(crosswalks.findByPatientIdAndSourceId(1L, 2L)).thenReturn(Optional.of(cw));
        when(api.fetchResources("Appointment", "ext-1")).thenReturn(List.of(json(
                "{\"resourceType\":\"Appointment\",\"id\":\"ap-1\",\"status\":\"booked\","
                        + "\"start\":\"2026-11-01T09:00:00Z\",\"end\":\"2026-11-01T09:30:00Z\"}")));
        when(raws.findByPatientIdAndSourceIdAndResourceTypeAndExternalResourceId(any(), any(), any(), any()))
                .thenReturn(Optional.empty());
        when(raws.save(any())).thenAnswer(inv -> inv.getArgument(0));
        EhrAppointmentRecord existing = new EhrAppointmentRecord();
        existing.setId(77L);
        when(appts.findByPatientIdAndSourceIdAndExternalAppointmentId(any(), any(), any()))
                .thenReturn(Optional.of(existing));
        when(appts.save(any())).thenAnswer(inv -> inv.getArgument(0));

        List<EhrAppointmentRecord> saved = svc.sync(patient, api);
        assertThat(saved).hasSize(1);
        assertThat(saved.get(0).getId()).isEqualTo(77L);
        verify(raws).save(any(EhrRawPayload.class));

        when(sources.findByCode("EPIC")).thenReturn(Optional.empty());
        assertThatThrownBy(() -> svc.sync(patient, api)).isInstanceOf(IllegalStateException.class);
        when(sources.findByCode("EPIC")).thenReturn(Optional.of(source));
        when(crosswalks.findByPatientIdAndSourceId(1L, 2L)).thenReturn(Optional.empty());
        assertThatThrownBy(() -> svc.sync(patient, api)).isInstanceOf(IllegalStateException.class);
    }
}
