package com.careconnect.integration.cerner;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.careconnect.integration.cerner.CernerAllergyService.CernerSourceException;
import com.careconnect.model.ehr.EhrAppointmentRecord;
import com.careconnect.model.ehr.EhrSourceIdentity;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.security.test.context.support.WithMockUser;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

/** Spring MVC slice coverage for the provisional Patient and Appointment endpoints. */
@WebMvcTest(
        controllers = CernerPatientAppointmentController.class,
        properties = "careconnect.cerner.patient-appointment.enabled=true")
class CernerPatientAppointmentControllerTest {

    @Autowired private MockMvc mvc;

    @MockitoBean private CernerPatientAppointmentService service;
    @MockitoBean private CernerAccessPolicy policy;

    @Test
    @Tag("M3-REQ-01")
    @WithMockUser(username = "clinician")
    @DisplayName("Patient endpoint serializes the provisional normalized view without internal IDs")
    void patientSuccess() throws Exception {
        when(policy.canView("clinician", 42L)).thenReturn(true);
        final EhrSourceIdentity identity = EhrSourceIdentity.builder()
                .id(91L)
                .patientId(42L)
                .sourceId(5L)
                .sourceUpdatedAt(Instant.parse("2026-10-20T14:30:00Z"))
                .givenName("Sandy")
                .familyName("Smart")
                .dateOfBirth(LocalDate.parse("1980-01-02"))
                .gender("female")
                .build();
        when(service.synchronizePatientWithSourceRecord(42L))
                .thenReturn(new CernerPatientAppointmentService.PatientSynchronization(
                        "cerner-patient-1", identity));

        mvc.perform(get("/v1/api/cerner/patients/42"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.source").value("ORACLE_HEALTH"))
                .andExpect(jsonPath("$.patient.source").value("ORACLE_HEALTH"))
                .andExpect(jsonPath("$.patient.sourceRecordId").value("cerner-patient-1"))
                .andExpect(jsonPath("$.patient.givenName").value("Sandy"))
                .andExpect(jsonPath("$.patient.familyName").value("Smart"))
                .andExpect(jsonPath("$.patient.dateOfBirth").value("1980-01-02"))
                .andExpect(jsonPath("$.patient.id").doesNotExist())
                .andExpect(jsonPath("$.patient.patientId").doesNotExist())
                .andExpect(jsonPath("$.patient.sourceId").doesNotExist());
    }

    @Test
    @Tag("M3-REQ-19")
    @WithMockUser(username = "clinician")
    @DisplayName("Appointment endpoint serializes bounded normalized records")
    void appointmentSuccess() throws Exception {
        when(policy.canView("clinician", 42L)).thenReturn(true);
        when(service.synchronizeAppointments(
                        42L,
                        Instant.parse("2026-10-01T00:00:00Z"),
                        Instant.parse("2026-11-01T00:00:00Z")))
                .thenReturn(List.of(EhrAppointmentRecord.builder()
                        .id(92L)
                        .externalAppointmentId("appointment-1")
                        .status("proposed")
                        .startTime(LocalDateTime.parse("2026-10-25T14:00:00"))
                        .endTime(LocalDateTime.parse("2026-10-25T14:30:00"))
                        .providerName("Synthetic Provider")
                        .build()));

        mvc.perform(get("/v1/api/cerner/patients/42/appointments")
                        .param("start", "2026-10-01T00:00:00Z")
                        .param("end", "2026-11-01T00:00:00Z"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.source").value("ORACLE_HEALTH"))
                .andExpect(jsonPath("$.appointments[0].source").value("ORACLE_HEALTH"))
                .andExpect(jsonPath("$.appointments[0].sourceRecordId").value("appointment-1"))
                .andExpect(jsonPath("$.appointments[0].status").value("proposed"))
                .andExpect(jsonPath("$.appointments[0].startTime")
                        .value("2026-10-25T14:00Z"))
                .andExpect(jsonPath("$.appointments[0].id").doesNotExist());
    }

    @Test
    @Tag("M3-REQ-19")
    @WithMockUser(username = "clinician")
    void appointmentEmptyResultIsSuccessful() throws Exception {
        when(policy.canView("clinician", 42L)).thenReturn(true);
        when(service.synchronizeAppointments(anyLong(), any(), any())).thenReturn(List.of());

        mvc.perform(get("/v1/api/cerner/patients/42/appointments")
                        .param("start", "2026-10-01T00:00:00Z")
                        .param("end", "2026-11-01T00:00:00Z"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.appointments").isEmpty());
    }

    @Test
    @WithMockUser(username = "clinician")
    void invalidAppointmentRangeReturnsBadRequestWithoutRetrieval() throws Exception {
        when(policy.canView("clinician", 42L)).thenReturn(true);

        mvc.perform(get("/v1/api/cerner/patients/42/appointments")
                        .param("start", "2026-11-01T00:00:00Z")
                        .param("end", "2026-10-01T00:00:00Z"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("INVALID_DATE_RANGE"));

        verify(service, never()).synchronizeAppointments(anyLong(), any(), any());
    }

    @Test
    @Tag("M3-REQ-03")
    @WithMockUser(username = "clinician")
    void deniedPatientReturnsForbiddenWithoutRetrieval() throws Exception {
        when(policy.canView("clinician", 42L)).thenReturn(false);

        mvc.perform(get("/v1/api/cerner/patients/42"))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value("ACCESS_DENIED"));

        verify(service, never()).synchronizePatientWithSourceRecord(anyLong());
    }

    @Test
    @WithMockUser(username = "clinician")
    void invalidPatientIdReturnsBadRequest() throws Exception {
        mvc.perform(get("/v1/api/cerner/patients/not-a-number"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("INVALID_PATIENT_ID"));
    }

    @Test
    @Tag("M3-REQ-09")
    @WithMockUser(username = "clinician")
    void expiredAuthorizationUsesStableErrorEnvelope() throws Exception {
        when(policy.canView("clinician", 42L)).thenReturn(true);
        when(service.synchronizePatientWithSourceRecord(42L))
                .thenThrow(new CernerSourceException("CERNER_AUTH_EXPIRED", false));

        mvc.perform(get("/v1/api/cerner/patients/42"))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("CERNER_AUTH_EXPIRED"))
                .andExpect(jsonPath("$.source").value("ORACLE_HEALTH"))
                .andExpect(jsonPath("$.retryable").value(false));
    }
}
