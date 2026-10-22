package com.careconnect.integration.cerner;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.careconnect.config.CernerProperties;
import com.careconnect.integration.cerner.CernerFhirBundleHttpClient.ResourceType;
import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.model.ehr.EhrConditionRecord;
import com.careconnect.model.ehr.EhrPatientCrosswalk;
import com.careconnect.model.ehr.EhrRawPayload;
import com.careconnect.model.ehr.EhrSource;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.ehr.EhrConditionRecordRepository;
import com.careconnect.repository.ehr.EhrEncounterRecordRepository;
import com.careconnect.repository.ehr.EhrPatientCrosswalkRepository;
import com.careconnect.repository.ehr.EhrRawPayloadRepository;
import com.careconnect.repository.ehr.EhrSourceRepository;
import com.careconnect.service.ehr.CernerOAuthService;
import com.careconnect.service.ehr.CernerOAuthService.CernerReauthorizationRequiredException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Optional;
import java.util.concurrent.atomic.AtomicLong;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class DefaultCernerConditionEncounterServiceTest {

    @Mock private PatientRepository patients;
    @Mock private EhrSourceRepository sources;
    @Mock private EhrPatientCrosswalkRepository crosswalks;
    @Mock private EhrRawPayloadRepository rawPayloads;
    @Mock private EhrConditionRecordRepository conditions;
    @Mock private EhrEncounterRecordRepository encounters;
    @Mock private CernerOAuthService oauth;
    @Mock private CernerFhirBundleHttpClient client;

    private final ObjectMapper json = new ObjectMapper();
    private DefaultCernerConditionEncounterService service;

    @BeforeEach
    void setUp() {
        service = new DefaultCernerConditionEncounterService(
                patients, sources, crosswalks, rawPayloads, conditions, encounters,
                oauth, client, Clock.fixed(
                        Instant.parse("2026-10-21T12:00:00Z"), ZoneOffset.UTC));
    }

    @Test
    @Tag("M3-REQ-04")
    void storesOriginalConditionAndUpsertsCanonicalRecord() throws Exception {
        arrangeContext();
        final JsonNode resource = resource(
                "/cerner/fhir/condition/bundle-one-condition.json");
        when(client.getResources(ResourceType.CONDITION, "synthetic-patient-1", "access"))
                .thenReturn(new CernerFhirBundleHttpClient.Result(List.of(resource)));
        when(conditions.findByPatientIdAndSourceIdAndExternalConditionId(
                42L, 5L, "synthetic-condition-1")).thenReturn(Optional.empty());
        arrangeRawSave();
        when(conditions.save(any())).thenAnswer(invocation -> invocation.getArgument(0));

        final List<EhrConditionRecord> saved = service.synchronizeConditions(42L);

        assertThat(saved).singleElement().satisfies(condition -> {
            assertThat(condition.getPatientId()).isEqualTo(42L);
            assertThat(condition.getSourceId()).isEqualTo(5L);
            assertThat(condition.getRawPayloadId()).isEqualTo(101L);
            assertThat(condition.getExternalConditionId()).isEqualTo("synthetic-condition-1");
        });
        verify(rawPayloads).save(any(EhrRawPayload.class));
        verify(conditions).save(any(EhrConditionRecord.class));
    }

    @Test
    @Tag("M3-REQ-04")
    void storesOriginalEncounterAndUpsertsCanonicalRecord() throws Exception {
        arrangeContext();
        final JsonNode resource = resource(
                "/cerner/fhir/encounter/bundle-one-encounter.json");
        when(client.getResources(ResourceType.ENCOUNTER, "synthetic-patient-1", "access"))
                .thenReturn(new CernerFhirBundleHttpClient.Result(List.of(resource)));
        when(encounters.findByPatientIdAndSourceIdAndExternalEncounterId(
                42L, 5L, "synthetic-encounter-1")).thenReturn(Optional.empty());
        arrangeRawSave();
        when(encounters.save(any())).thenAnswer(invocation -> invocation.getArgument(0));

        final var saved = service.synchronizeEncounters(42L);

        assertThat(saved).singleElement().satisfies(encounter -> {
            assertThat(encounter.getRawPayloadId()).isEqualTo(101L);
            assertThat(encounter.getExternalEncounterId()).isEqualTo("synthetic-encounter-1");
        });
        verify(rawPayloads).save(any(EhrRawPayload.class));
        verify(encounters).save(any());
    }

    @Test
    @Tag("M3-REQ-04")
    void emptyBundleDoesNotWrite() {
        arrangeContext();
        when(client.getResources(ResourceType.CONDITION, "synthetic-patient-1", "access"))
                .thenReturn(new CernerFhirBundleHttpClient.Result(List.of()));

        assertThat(service.synchronizeConditions(42L)).isEmpty();

        verify(rawPayloads, never()).save(any());
        verify(conditions, never()).save(any());
    }

    @Test
    @Tag("M3-REQ-09")
    void refreshesOnceAfterUnauthorizedResponse() {
        arrangeContext();
        when(client.getResources(ResourceType.CONDITION, "synthetic-patient-1", "access"))
                .thenThrow(new CernerAllergyService.CernerSourceException(
                        "CERNER_AUTH_EXPIRED", false));
        when(oauth.refreshAccessToken(77L)).thenReturn("fresh");
        when(client.getResources(ResourceType.CONDITION, "synthetic-patient-1", "fresh"))
                .thenReturn(new CernerFhirBundleHttpClient.Result(List.of()));

        assertThat(service.synchronizeConditions(42L)).isEmpty();

        verify(oauth).refreshAccessToken(77L);
    }

    @Test
    @Tag("M3-REQ-09")
    void failedRefreshReturnsStableAuthorizationError() {
        arrangeContext();
        when(client.getResources(ResourceType.ENCOUNTER, "synthetic-patient-1", "access"))
                .thenThrow(new CernerAllergyService.CernerSourceException(
                        "CERNER_AUTH_EXPIRED", false));
        when(oauth.refreshAccessToken(77L))
                .thenThrow(new CernerReauthorizationRequiredException("private"));

        assertThatThrownBy(() -> service.synchronizeEncounters(42L))
                .isInstanceOf(CernerAllergyService.CernerSourceException.class)
                .satisfies(error -> assertThat(
                        ((CernerAllergyService.CernerSourceException) error).code())
                        .isEqualTo("CERNER_AUTH_EXPIRED"));
    }

    @Test
    @Tag("M3-REQ-06")
    void olderResourceCannotReplaceNewerNormalizedOrRawData() throws Exception {
        arrangeContext();
        final JsonNode resource = resource(
                "/cerner/fhir/condition/bundle-one-condition.json");
        when(client.getResources(ResourceType.CONDITION, "synthetic-patient-1", "access"))
                .thenReturn(new CernerFhirBundleHttpClient.Result(List.of(resource)));
        final EhrConditionRecord current = EhrConditionRecord.builder()
                .id(9L)
                .patientId(42L)
                .sourceId(5L)
                .externalConditionId("synthetic-condition-1")
                .sourceUpdatedAt(Instant.parse("2027-01-01T00:00:00Z"))
                .build();
        when(conditions.findByPatientIdAndSourceIdAndExternalConditionId(
                42L, 5L, "synthetic-condition-1")).thenReturn(Optional.of(current));

        assertThat(service.synchronizeConditions(42L)).containsExactly(current);

        verify(rawPayloads, never()).save(any());
        verify(conditions, never()).save(any());
    }

    @Test
    @Tag("M3-REQ-06")
    void malformedClinicalResourceReturnsCleanSourceErrorAndWritesNothing() throws Exception {
        arrangeContext();
        final JsonNode malformed = resource(
                "/cerner/fhir/encounter/bundle-one-encounter.json");
        ((com.fasterxml.jackson.databind.node.ObjectNode) malformed).remove("status");
        when(client.getResources(ResourceType.ENCOUNTER, "synthetic-patient-1", "access"))
                .thenReturn(new CernerFhirBundleHttpClient.Result(List.of(malformed)));

        assertThatThrownBy(() -> service.synchronizeEncounters(42L))
                .isInstanceOf(CernerAllergyService.CernerSourceException.class)
                .satisfies(error -> {
                    final var sourceError = (CernerAllergyService.CernerSourceException) error;
                    assertThat(sourceError.code()).isEqualTo("CERNER_INVALID_RESPONSE");
                    assertThat(sourceError.getMessage()).isEqualTo("Cerner source error");
                    assertThat(sourceError.getCause()).isNull();
                });
        verify(rawPayloads, never()).save(any());
        verify(encounters, never()).save(any());
    }

    private void arrangeContext() {
        final Patient patient = Patient.builder()
                .id(42L)
                .user(User.builder().id(77L).build())
                .build();
        final EhrSource source = EhrSource.builder()
                .id(5L)
                .code(CernerProperties.SOURCE_ORACLE_HEALTH)
                .build();
        final EhrPatientCrosswalk crosswalk = EhrPatientCrosswalk.builder()
                .patientId(42L)
                .sourceId(5L)
                .externalPatientId("synthetic-patient-1")
                .build();
        when(patients.findById(42L)).thenReturn(Optional.of(patient));
        when(sources.findByCode(CernerProperties.SOURCE_ORACLE_HEALTH))
                .thenReturn(Optional.of(source));
        when(crosswalks.findByPatientIdAndSourceId(42L, 5L))
                .thenReturn(Optional.of(crosswalk));
        when(oauth.patientFhirId(77L)).thenReturn("Patient/synthetic-patient-1");
        when(oauth.validAccessToken(77L)).thenReturn("access");
    }

    private JsonNode resource(final String fixture) throws Exception {
        try (var input = getClass().getResourceAsStream(fixture)) {
            assertThat(input).isNotNull();
            return json.readTree(input).path("entry").path(0).path("resource");
        }
    }

    private void arrangeRawSave() {
        when(rawPayloads.findByPatientIdAndSourceIdAndResourceTypeAndExternalResourceId(
                any(), any(), any(), any())).thenReturn(Optional.empty());
        final AtomicLong id = new AtomicLong(100);
        when(rawPayloads.save(any())).thenAnswer(invocation -> {
            final EhrRawPayload raw = invocation.getArgument(0);
            raw.setId(id.incrementAndGet());
            return raw;
        });
    }
}
