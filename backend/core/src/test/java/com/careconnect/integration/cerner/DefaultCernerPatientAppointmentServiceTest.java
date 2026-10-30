package com.careconnect.integration.cerner;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.careconnect.config.CernerProperties;
import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.model.ehr.EhrAppointmentRecord;
import com.careconnect.model.ehr.EhrPatientCrosswalk;
import com.careconnect.model.ehr.EhrRawPayload;
import com.careconnect.model.ehr.EhrSource;
import com.careconnect.model.ehr.EhrSourceIdentity;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.ehr.EhrAppointmentRecordRepository;
import com.careconnect.repository.ehr.EhrPatientCrosswalkRepository;
import com.careconnect.repository.ehr.EhrRawPayloadRepository;
import com.careconnect.repository.ehr.EhrSourceIdentityRepository;
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
class DefaultCernerPatientAppointmentServiceTest {

    private static final Instant WINDOW_START = Instant.parse("2010-01-01T00:00:00Z");
    private static final Instant WINDOW_END = Instant.parse("2027-01-01T00:00:00Z");

    @Mock private PatientRepository patients;
    @Mock private EhrSourceRepository sources;
    @Mock private EhrPatientCrosswalkRepository crosswalks;
    @Mock private EhrRawPayloadRepository rawPayloads;
    @Mock private EhrSourceIdentityRepository identities;
    @Mock private EhrAppointmentRecordRepository appointments;
    @Mock private CernerOAuthService oauth;
    @Mock private CernerFhirBundleHttpClient client;

    private final ObjectMapper json = new ObjectMapper();
    private DefaultCernerPatientAppointmentService service;

    @BeforeEach
    void setUp() {
        service = new DefaultCernerPatientAppointmentService(
                patients,
                sources,
                crosswalks,
                rawPayloads,
                identities,
                appointments,
                oauth,
                client,
                Clock.fixed(Instant.parse("2026-10-21T12:00:00Z"), ZoneOffset.UTC));
    }

    @Test
    @Tag("M3-REQ-01")
    void patientReadRetainsRawPayloadAndUpsertsSharedSourceIdentity() throws Exception {
        arrangeContext();
        arrangeRawSave();
        when(client.getPatient("synthetic-patient-1", "access"))
                .thenReturn(patientFixture());
        when(identities.findByPatientIdAndSourceId(42L, 5L)).thenReturn(Optional.empty());
        when(identities.save(any())).thenAnswer(invocation -> invocation.getArgument(0));

        final EhrSourceIdentity saved = service.synchronizePatient(42L);

        assertThat(saved.getGivenName()).isEqualTo("Synthetic");
        assertThat(saved.getFamilyName()).isEqualTo("Patient");
        assertThat(saved.getSourceId()).isEqualTo(5L);
        verify(rawPayloads).save(any(EhrRawPayload.class));
        verify(identities).save(any(EhrSourceIdentity.class));
    }

    @Test
    @Tag("M3-REQ-05")
    void proposedAppointmentWithoutTimesIsRetainedAndUpserted() throws Exception {
        arrangeContext();
        arrangeRawSave();
        final JsonNode appointment = appointmentFixture(
                "/cerner/fhir/appointment/bundle-proposed-no-times.json");
        when(client.getAppointments(
                "synthetic-patient-1", "access", WINDOW_START, WINDOW_END))
                .thenReturn(new CernerFhirBundleHttpClient.Result(List.of(appointment)));
        when(appointments.findByPatientIdAndSourceIdAndExternalAppointmentId(
                42L, 5L, "synthetic-appointment-proposed"))
                .thenReturn(Optional.empty());
        when(appointments.save(any())).thenAnswer(invocation -> invocation.getArgument(0));

        final List<EhrAppointmentRecord> saved = service.synchronizeAppointments(
                42L, WINDOW_START, WINDOW_END);

        assertThat(saved).singleElement().satisfies(record -> {
            assertThat(record.getStatus()).isEqualTo("proposed");
            assertThat(record.getStartTime()).isNull();
            assertThat(record.getEndTime()).isNull();
            assertThat(record.getRawPayload().getId()).isEqualTo(101L);
            assertThat(record.getSource().getCode())
                    .isEqualTo(CernerProperties.SOURCE_ORACLE_HEALTH);
        });
    }

    @Test
    @Tag("M3-REQ-06")
    void olderAppointmentCannotReplaceNewerCanonicalOrRawRecord() throws Exception {
        arrangeContext();
        final JsonNode appointment = appointmentFixture(
                "/cerner/fhir/appointment/bundle-one-appointment.json");
        when(client.getAppointments(
                "synthetic-patient-1", "access", WINDOW_START, WINDOW_END))
                .thenReturn(new CernerFhirBundleHttpClient.Result(List.of(appointment)));
        final EhrAppointmentRecord current = EhrAppointmentRecord.builder()
                .id(9L)
                .externalAppointmentId("synthetic-appointment-1")
                .sourceUpdatedAt(java.time.LocalDateTime.of(2027, 1, 1, 0, 0))
                .build();
        when(appointments.findByPatientIdAndSourceIdAndExternalAppointmentId(
                42L, 5L, "synthetic-appointment-1"))
                .thenReturn(Optional.of(current));
        assertThat(service.synchronizeAppointments(42L, WINDOW_START, WINDOW_END))
                .containsExactly(current);

        verify(rawPayloads, never()).save(any());
        verify(appointments, never()).save(any());
    }

    @Test
    @Tag("M3-REQ-09")
    void patientReadRefreshesOnceAfterExpiredToken() throws Exception {
        arrangeContext();
        arrangeRawSave();
        when(client.getPatient("synthetic-patient-1", "access"))
                .thenThrow(new CernerAllergyService.CernerSourceException(
                        "CERNER_AUTH_EXPIRED", false));
        when(oauth.refreshAccessToken(77L)).thenReturn("refreshed");
        when(client.getPatient("synthetic-patient-1", "refreshed"))
                .thenReturn(patientFixture());
        when(identities.findByPatientIdAndSourceId(42L, 5L)).thenReturn(Optional.empty());
        when(identities.save(any())).thenAnswer(invocation -> invocation.getArgument(0));

        assertThat(service.synchronizePatient(42L).getGivenName()).isEqualTo("Synthetic");
        verify(oauth).refreshAccessToken(77L);
    }

    @Test
    @Tag("M3-REQ-09")
    void appointmentRefreshFailureBecomesSourceAuthExpired() {
        arrangeContext();
        when(client.getAppointments(
                eq("synthetic-patient-1"), eq("access"), eq(WINDOW_START), eq(WINDOW_END)))
                .thenThrow(new CernerAllergyService.CernerSourceException(
                        "CERNER_AUTH_EXPIRED", false));
        when(oauth.refreshAccessToken(77L))
                .thenThrow(new CernerReauthorizationRequiredException("reauthorize"));

        assertThatThrownBy(() -> service.synchronizeAppointments(
                42L, WINDOW_START, WINDOW_END))
                .isInstanceOf(CernerAllergyService.CernerSourceException.class)
                .satisfies(error -> assertThat(
                        ((CernerAllergyService.CernerSourceException) error).code())
                        .isEqualTo("CERNER_AUTH_EXPIRED"));
    }

    @Test
    @Tag("M3-REQ-06")
    void malformedAppointmentBecomesInvalidResponse() throws Exception {
        arrangeContext();
        when(client.getAppointments(
                "synthetic-patient-1", "access", WINDOW_START, WINDOW_END))
                .thenReturn(new CernerFhirBundleHttpClient.Result(List.of(
                        json.readTree("{\"resourceType\":\"Appointment\"}"))));

        assertThatThrownBy(() -> service.synchronizeAppointments(
                42L, WINDOW_START, WINDOW_END))
                .isInstanceOf(CernerAllergyService.CernerSourceException.class)
                .satisfies(error -> assertThat(
                        ((CernerAllergyService.CernerSourceException) error).code())
                        .isEqualTo("CERNER_INVALID_RESPONSE"));
    }

    @Test
    void unsupportedAppointmentModesReturnEmptyResults() {
        assertThat(service.synchronizeAppointmentsWithTokenRefresh(42L, WINDOW_START, WINDOW_END))
                .isEmpty();
        assertThat(service.synchronizeAppointmentsAllowingEmptyResults(42L, WINDOW_START, WINDOW_END))
                .isEmpty();
        assertThat(service.synchronizeAppointmentsWithPaginationAndRateLimiting(
                42L, WINDOW_START, WINDOW_END)).isEmpty();
        assertThat(service.synchronizeAppointmentsWithReferenceMismatchHandling(
                42L, WINDOW_START, WINDOW_END)).isEmpty();
        assertThat(service.validatePatientAndAppointmentExpectedOutputFixtures(
                42L, WINDOW_START, WINDOW_END)).isFalse();
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
        when(patients.findById(42L)).thenReturn(Optional.of(patient));
        when(sources.findByCode(CernerProperties.SOURCE_ORACLE_HEALTH))
                .thenReturn(Optional.of(source));
        when(crosswalks.findByPatientIdAndSourceId(42L, 5L)).thenReturn(Optional.of(
                EhrPatientCrosswalk.builder()
                        .patientId(42L)
                        .sourceId(5L)
                        .externalPatientId("synthetic-patient-1")
                        .build()));
        when(oauth.patientFhirId(77L)).thenReturn("Patient/synthetic-patient-1");
        when(oauth.validAccessToken(77L)).thenReturn("access");
    }

    private void arrangeRawSave() {
        when(rawPayloads.findByPatientIdAndSourceIdAndResourceTypeAndExternalResourceId(
                any(), any(), any(), any())).thenReturn(Optional.empty());
        final AtomicLong id = new AtomicLong(100L);
        when(rawPayloads.save(any())).thenAnswer(invocation -> {
            final EhrRawPayload raw = invocation.getArgument(0);
            raw.setId(id.incrementAndGet());
            return raw;
        });
    }

    private JsonNode patientFixture() throws Exception {
        try (var input = getClass().getResourceAsStream(
                "/cerner/fhir/patient/patient-complete.json")) {
            assertThat(input).isNotNull();
            return json.readTree(input);
        }
    }

    private JsonNode appointmentFixture(final String path) throws Exception {
        try (var input = getClass().getResourceAsStream(path)) {
            assertThat(input).isNotNull();
            return json.readTree(input).path("entry").path(0).path("resource");
        }
    }
}
