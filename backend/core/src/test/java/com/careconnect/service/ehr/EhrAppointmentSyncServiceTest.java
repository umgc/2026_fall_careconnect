package com.careconnect.service.ehr;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.careconnect.client.ehr.EhrApiClient;
import com.careconnect.model.Patient;
import com.careconnect.model.ehr.EhrAppointmentRecord;
import com.careconnect.model.ehr.EhrPatientCrosswalk;
import com.careconnect.model.ehr.EhrRawPayload;
import com.careconnect.model.ehr.EhrSource;
import com.careconnect.repository.ehr.EhrAppointmentRecordRepository;
import com.careconnect.repository.ehr.EhrPatientCrosswalkRepository;
import com.careconnect.repository.ehr.EhrRawPayloadRepository;
import com.careconnect.repository.ehr.EhrSourceRepository;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class EhrAppointmentSyncServiceTest {

    private static final ObjectMapper JSON = new ObjectMapper();

    @Mock
    private EhrSourceRepository sourceRepository;

    @Mock
    private EhrPatientCrosswalkRepository crosswalkRepository;

    @Mock
    private EhrRawPayloadRepository rawPayloadRepository;

    @Mock
    private EhrAppointmentRecordRepository appointmentRepository;

    @Mock
    private EhrApiClient apiClient;

    private EhrAppointmentSyncService service;
    private Patient patient;
    private EhrSource source;

    @BeforeEach
    void setUp() {
        service = new EhrAppointmentSyncService(
                sourceRepository, crosswalkRepository, rawPayloadRepository,
                appointmentRepository, JSON);
        patient = Patient.builder().id(1L).build();
        source = EhrSource.builder().id(2L).code("ATHENAHEALTH").build();
    }

    @Test
    void refusesToSyncAnUnknownSourceCode() {
        when(apiClient.sourceCode()).thenReturn("ATHENAHEALTH");
        when(sourceRepository.findByCode("ATHENAHEALTH")).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.sync(patient, apiClient))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("ATHENAHEALTH");
    }

    @Test
    void refusesToSyncWithoutAnExistingCrosswalkEntry() {
        when(apiClient.sourceCode()).thenReturn("ATHENAHEALTH");
        when(sourceRepository.findByCode("ATHENAHEALTH")).thenReturn(Optional.of(source));
        when(crosswalkRepository.findByPatientIdAndSourceId(1L, 2L)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.sync(patient, apiClient))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("crosswalk");
    }

    @Test
    void storesTheRawPayloadThenUpsertsTheMappedAppointment() throws Exception {
        final EhrPatientCrosswalk crosswalk = EhrPatientCrosswalk.builder()
                .patient(patient).source(source).externalPatientId("ext-1").build();
        final JsonNode appointment = JSON.readTree(
                "{\"resourceType\":\"Appointment\",\"id\":\"appt-1\",\"status\":\"booked\"}");

        when(apiClient.sourceCode()).thenReturn("ATHENAHEALTH");
        when(sourceRepository.findByCode("ATHENAHEALTH")).thenReturn(Optional.of(source));
        when(crosswalkRepository.findByPatientIdAndSourceId(1L, 2L))
                .thenReturn(Optional.of(crosswalk));
        when(apiClient.fetchResources("Appointment", "ext-1")).thenReturn(List.of(appointment));
        when(rawPayloadRepository
                .findByPatientIdAndSourceIdAndResourceTypeAndExternalResourceId(
                        1L, 2L, "Appointment", "appt-1"))
                .thenReturn(Optional.empty());
        when(rawPayloadRepository.save(any(EhrRawPayload.class)))
                .thenAnswer(invocation -> {
                    final EhrRawPayload saved = invocation.getArgument(0);
                    saved.setId(10L);
                    return saved;
                });
        when(appointmentRepository.findByPatientIdAndSourceIdAndExternalAppointmentId(
                        1L, 2L, "appt-1"))
                .thenReturn(Optional.empty());
        when(appointmentRepository.save(any(EhrAppointmentRecord.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        final List<EhrAppointmentRecord> result = service.sync(patient, apiClient);

        assertThat(result).hasSize(1);
        final EhrAppointmentRecord saved = result.get(0);
        assertThat(saved.getExternalAppointmentId()).isEqualTo("appt-1");
        assertThat(saved.getRawPayload().getId()).isEqualTo(10L);

        final ArgumentCaptor<EhrRawPayload> rawPayloadCaptor =
                ArgumentCaptor.forClass(EhrRawPayload.class);
        verify(rawPayloadRepository).save(rawPayloadCaptor.capture());
        assertThat(rawPayloadCaptor.getValue().getResourceType()).isEqualTo("Appointment");
        assertThat(rawPayloadCaptor.getValue().getExternalResourceId()).isEqualTo("appt-1");
        assertThat(rawPayloadCaptor.getValue().getPayload()).containsEntry("status", "booked");
    }

    @Test
    void reSyncingAnExistingAppointmentUpdatesItInsteadOfDuplicating() throws Exception {
        final EhrPatientCrosswalk crosswalk = EhrPatientCrosswalk.builder()
                .patient(patient).source(source).externalPatientId("ext-1").build();
        final JsonNode appointment = JSON.readTree(
                "{\"resourceType\":\"Appointment\",\"id\":\"appt-1\",\"status\":\"fulfilled\"}");
        final EhrAppointmentRecord existing = EhrAppointmentRecord.builder()
                .id(99L).patient(patient).source(source)
                .externalAppointmentId("appt-1").status("booked").build();

        when(apiClient.sourceCode()).thenReturn("ATHENAHEALTH");
        when(sourceRepository.findByCode("ATHENAHEALTH")).thenReturn(Optional.of(source));
        when(crosswalkRepository.findByPatientIdAndSourceId(1L, 2L))
                .thenReturn(Optional.of(crosswalk));
        when(apiClient.fetchResources("Appointment", "ext-1")).thenReturn(List.of(appointment));
        when(rawPayloadRepository
                .findByPatientIdAndSourceIdAndResourceTypeAndExternalResourceId(
                        1L, 2L, "Appointment", "appt-1"))
                .thenReturn(Optional.empty());
        when(rawPayloadRepository.save(any(EhrRawPayload.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));
        when(appointmentRepository.findByPatientIdAndSourceIdAndExternalAppointmentId(
                        1L, 2L, "appt-1"))
                .thenReturn(Optional.of(existing));
        when(appointmentRepository.save(any(EhrAppointmentRecord.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        final EhrAppointmentRecord saved = service.sync(patient, apiClient).get(0);

        assertThat(saved.getId()).isEqualTo(99L);
        assertThat(saved.getStatus()).isEqualTo("fulfilled");
    }
}
