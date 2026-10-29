package com.careconnect.integration.cerner;

import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.careconnect.integration.cerner.CernerAllergyService.CernerSourceException;
import com.careconnect.model.ehr.EhrConditionRecord;
import com.careconnect.model.ehr.EhrEncounterRecord;
import java.util.List;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.security.test.context.support.WithMockUser;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

/** Spring MVC slice coverage for the provisional Condition and Encounter endpoints. */
@WebMvcTest(
        controllers = CernerClinicalController.class,
        properties = "careconnect.cerner.clinical.enabled=true")
class CernerClinicalControllerTest {

    @Autowired private MockMvc mvc;

    @MockitoBean private CernerConditionEncounterService service;
    @MockitoBean private CernerAccessPolicy policy;

    @Test
    @Tag("M3-REQ-17")
    @WithMockUser(username = "clinician")
    @DisplayName("Condition endpoint serializes provisional camelCase DTO without internal IDs")
    void conditionSuccess() throws Exception {
        when(policy.canView("clinician", 42L)).thenReturn(true);
        when(service.synchronizeConditions(42L)).thenReturn(List.of(EhrConditionRecord.builder()
                .id(91L)
                .patientId(42L)
                .sourceId(5L)
                .rawPayloadId(101L)
                .externalConditionId("condition-1")
                .clinicalStatus("active")
                .verificationStatus("confirmed")
                .conditionText("Synthetic condition")
                .build()));

        mvc.perform(get("/v1/api/cerner/patients/42/conditions"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.source").value("ORACLE_HEALTH"))
                .andExpect(jsonPath("$.conditions[0].sourceRecordId").value("condition-1"))
                .andExpect(jsonPath("$.conditions[0].conditionText")
                        .value("Synthetic condition"))
                .andExpect(jsonPath("$.conditions[0].id").doesNotExist())
                .andExpect(jsonPath("$.conditions[0].patientId").doesNotExist())
                .andExpect(jsonPath("$.conditions[0].rawPayloadId").doesNotExist());
    }

    @Test
    @Tag("M3-REQ-18")
    @WithMockUser(username = "clinician")
    @DisplayName("Encounter endpoint returns a successful empty collection")
    void encounterEmpty() throws Exception {
        when(policy.canView("clinician", 42L)).thenReturn(true);
        when(service.synchronizeEncounters(42L)).thenReturn(List.of());

        mvc.perform(get("/v1/api/cerner/patients/42/encounters"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.source").value("ORACLE_HEALTH"))
                .andExpect(jsonPath("$.encounters").isEmpty());
    }

    @Test
    @Tag("M3-REQ-18")
    @WithMockUser(username = "clinician")
    @DisplayName("Encounter endpoint serializes source identity and normalized status")
    void encounterSuccess() throws Exception {
        when(policy.canView("clinician", 42L)).thenReturn(true);
        when(service.synchronizeEncounters(42L)).thenReturn(List.of(EhrEncounterRecord.builder()
                .id(92L)
                .patientId(42L)
                .sourceId(5L)
                .rawPayloadId(102L)
                .externalEncounterId("encounter-1")
                .status("finished")
                .classCode("AMB")
                .build()));

        mvc.perform(get("/v1/api/cerner/patients/42/encounters"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.encounters[0].source").value("ORACLE_HEALTH"))
                .andExpect(jsonPath("$.encounters[0].sourceRecordId").value("encounter-1"))
                .andExpect(jsonPath("$.encounters[0].status").value("finished"))
                .andExpect(jsonPath("$.encounters[0].id").doesNotExist());
    }

    @Test
    @Tag("M3-REQ-03")
    @WithMockUser(username = "clinician")
    void deniedPatientReturnsForbiddenWithoutRetrieval() throws Exception {
        when(policy.canView("clinician", 42L)).thenReturn(false);

        mvc.perform(get("/v1/api/cerner/patients/42/conditions"))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value("ACCESS_DENIED"));

        verify(service, never()).synchronizeConditions(anyLong());
    }

    @Test
    @WithMockUser(username = "clinician")
    void invalidPatientIdReturnsBadRequest() throws Exception {
        mvc.perform(get("/v1/api/cerner/patients/not-a-number/conditions"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("INVALID_PATIENT_ID"));
    }

    @Test
    @Tag("M3-REQ-09")
    @WithMockUser(username = "clinician")
    void expiredAuthorizationUsesStableErrorEnvelope() throws Exception {
        when(policy.canView("clinician", 42L)).thenReturn(true);
        when(service.synchronizeConditions(42L))
                .thenThrow(new CernerSourceException("CERNER_AUTH_EXPIRED", false));

        mvc.perform(get("/v1/api/cerner/patients/42/conditions"))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("CERNER_AUTH_EXPIRED"))
                .andExpect(jsonPath("$.source").value("ORACLE_HEALTH"))
                .andExpect(jsonPath("$.retryable").value(false));
    }

    @Test
    @Tag("M3-REQ-07")
    @WithMockUser(username = "clinician")
    void upstreamTimeoutIsRetryableAndLeaksNoDetails() throws Exception {
        when(policy.canView("clinician", 42L)).thenReturn(true);
        when(service.synchronizeEncounters(42L))
                .thenThrow(new CernerSourceException("CERNER_TIMEOUT", true));

        mvc.perform(get("/v1/api/cerner/patients/42/encounters"))
                .andExpect(status().isBadGateway())
                .andExpect(jsonPath("$.code").value("CERNER_TIMEOUT"))
                .andExpect(jsonPath("$.message").value("Cerner source error"))
                .andExpect(jsonPath("$.retryable").value(true))
                .andExpect(jsonPath("$.stackTrace").doesNotExist());
    }
}
