package com.careconnect.integration.cerner;

import com.careconnect.config.CernerProperties;
import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.model.ehr.EhrPatientCrosswalk;
import com.careconnect.model.ehr.EhrRawPayload;
import com.careconnect.model.ehr.EhrSource;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.ehr.EhrPatientCrosswalkRepository;
import com.careconnect.repository.ehr.EhrRawPayloadRepository;
import com.careconnect.repository.ehr.EhrSourceRepository;
import com.careconnect.service.ehr.CernerOAuthService;
import com.careconnect.service.ehr.CernerOAuthService.CernerReauthorizationRequiredException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.ArgumentCaptor;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class DefaultCernerAllergyServiceTest {

    @Mock private PatientRepository patients;
    @Mock private EhrSourceRepository sources;
    @Mock private EhrPatientCrosswalkRepository crosswalks;
    @Mock private EhrRawPayloadRepository rawPayloads;
    @Mock private CernerOAuthService oauth;
    @Mock private CernerAllergyHttpClient client;

    private DefaultCernerAllergyService service;

    @BeforeEach
    void setUp() {
        service = new DefaultCernerAllergyService(
                patients, sources, crosswalks, rawPayloads, oauth, client,
                Clock.fixed(Instant.parse("2026-10-21T12:00:00Z"), ZoneOffset.UTC));
    }

    @Test
    void retrievesWithPatientOwnedCredentialAndOracleHealthCrosswalk() {
        arrangeLinkedPatient("12724066");
        when(oauth.patientFhirId(77L)).thenReturn("Patient/12724066");
        when(oauth.validAccessToken(77L)).thenReturn("access-token");
        List<CernerAllergyMapper.Allergy> expected = List.of(new CernerAllergyMapper.Allergy(
                CernerProperties.SOURCE_ORACLE_HEALTH, "allergy-1", "Aspirin", "1191",
                "active", "confirmed", "severe", "2024-09-25T05:56:38Z",
                List.of("Papular eruption")));
        when(client.getAllergyResult("12724066", "access-token"))
                .thenReturn(new CernerAllergyHttpClient.Result(expected, List.of()));

        assertThat(service.getAllergies(42L)).isEqualTo(expected);

        verify(sources).findByCode(CernerProperties.SOURCE_ORACLE_HEALTH);
        verify(client).getAllergyResult("12724066", "access-token");
    }

    @Test
    void refusesMismatchedSmartPatientContextBeforeCallingCerner() {
        arrangeLinkedPatient("12724066");
        when(oauth.patientFhirId(77L)).thenReturn("different-patient");

        assertThatThrownBy(() -> service.getAllergies(42L))
                .isInstanceOf(CernerAllergyService.CernerSourceException.class)
                .extracting(exception -> ((CernerAllergyService.CernerSourceException) exception).code())
                .isEqualTo("CERNER_PATIENT_CONTEXT_MISMATCH");

        verify(oauth, never()).validAccessToken(77L);
        verify(client, never()).getAllergyResult("12724066", "access-token");
    }

    @Test
    void convertsMissingOrExpiredCredentialToStableSourceError() {
        arrangeLinkedPatient("12724066");
        when(oauth.patientFhirId(77L))
                .thenThrow(new CernerReauthorizationRequiredException("missing"));

        assertThatThrownBy(() -> service.getAllergies(42L))
                .isInstanceOf(CernerAllergyService.CernerSourceException.class)
                .extracting(exception -> ((CernerAllergyService.CernerSourceException) exception).code())
                .isEqualTo("CERNER_AUTH_EXPIRED");
    }

    @Test
    void refreshesOnceAfterUpstreamRejectsAnOtherwiseCurrentToken() {
        arrangeLinkedPatient("12724066");
        when(oauth.patientFhirId(77L)).thenReturn("12724066");
        when(oauth.validAccessToken(77L)).thenReturn("stale-token");
        when(oauth.refreshAccessToken(77L)).thenReturn("fresh-token");
        when(client.getAllergyResult("12724066", "stale-token"))
                .thenThrow(new CernerAllergyService.CernerSourceException(
                        "CERNER_AUTH_EXPIRED", false));
        when(client.getAllergyResult("12724066", "fresh-token"))
                .thenReturn(new CernerAllergyHttpClient.Result(List.of(), List.of()));

        assertThat(service.getAllergies(42L)).isEmpty();

        verify(oauth).refreshAccessToken(77L);
        verify(client).getAllergyResult("12724066", "fresh-token");
    }

    @Test
    void storesValidatedRawAllergyUsingCanonicalSourceId() throws Exception {
        arrangeLinkedPatient("12724066");
        when(oauth.patientFhirId(77L)).thenReturn("12724066");
        when(oauth.validAccessToken(77L)).thenReturn("access-token");
        JsonNode raw = new ObjectMapper().readTree(
                "{\"resourceType\":\"AllergyIntolerance\",\"id\":\"allergy-1\","
                        + "\"patient\":{\"reference\":\"Patient/12724066\"}}");
        when(client.getAllergyResult("12724066", "access-token"))
                .thenReturn(new CernerAllergyHttpClient.Result(List.of(), List.of(raw)));
        when(rawPayloads.findByPatientIdAndSourceIdAndResourceTypeAndExternalResourceId(
                42L, 5L, "AllergyIntolerance", "allergy-1"))
                .thenReturn(Optional.empty());

        service.getAllergies(42L);

        ArgumentCaptor<EhrRawPayload> saved = ArgumentCaptor.forClass(EhrRawPayload.class);
        verify(rawPayloads).save(saved.capture());
        assertThat(saved.getValue().getPatientId()).isEqualTo(42L);
        assertThat(saved.getValue().getSourceId()).isEqualTo(5L);
        assertThat(saved.getValue().getExternalResourceId()).isEqualTo("allergy-1");
        assertThat(saved.getValue().getRetrievedAt().toInstant())
                .isEqualTo(Instant.parse("2026-10-21T12:00:00Z"));
        assertThat(saved.getValue().getPayload()).contains("AllergyIntolerance");
    }

    private void arrangeLinkedPatient(final String externalPatientId) {
        User owner = User.builder().id(77L).build();
        Patient patient = Patient.builder().id(42L).user(owner).build();
        EhrSource source = EhrSource.builder()
                .id(5L)
                .code(CernerProperties.SOURCE_ORACLE_HEALTH)
                .build();
        EhrPatientCrosswalk crosswalk = EhrPatientCrosswalk.builder()
                .patientId(42L)
                .sourceId(5L)
                .externalPatientId(externalPatientId)
                .build();
        when(patients.findById(42L)).thenReturn(Optional.of(patient));
        when(sources.findByCode(CernerProperties.SOURCE_ORACLE_HEALTH)).thenReturn(Optional.of(source));
        when(crosswalks.findByPatientIdAndSourceId(42L, 5L)).thenReturn(Optional.of(crosswalk));
    }
}
