package com.careconnect.integration.cerner;

import com.careconnect.integration.cerner.CernerAllergyService.CernerSourceException;
import com.careconnect.integration.cerner.CernerAllergyService.UnknownPatientException;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import java.security.Principal;
import java.util.List;

import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/** Controller-slice tests (M3-SC-CTL) using standalone MockMvc and mocked collaborators. */
@ExtendWith(MockitoExtension.class)
class CernerAllergyControllerTest {

    private static final String URL = "/v1/api/cerner/patients/42/allergies";
    private static final Principal USER = () -> "clinician";

    @Mock
    private CernerAllergyService service;
    @Mock
    private CernerAccessPolicy policy;

    private MockMvc mvc;

    @BeforeEach
    void setUp() {
        mvc = MockMvcBuilders.standaloneSetup(new CernerAllergyController(service, policy)).build();
    }

    @Test
    @Tag("M3-REQ-04")
    @DisplayName("CTL: authorized request returns 200 with camelCase fields and source")
    void ok() throws Exception {
        when(policy.canView("clinician", 42)).thenReturn(true);
        when(service.getAllergies(42)).thenReturn(List.of(new CernerAllergyMapper.Allergy(
                "CERNER", "a1", "Penicillin", "7980", "active", "confirmed", "severe",
                "2024-03-01T15:00:00Z", List.of("Hives"))));

        mvc.perform(get(URL).principal(USER))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.source").value("CERNER"))
                .andExpect(jsonPath("$.allergies[0].sourceRecordId").value("a1"))
                .andExpect(jsonPath("$.allergies[0].substanceText").value("Penicillin"))
                .andExpect(jsonPath("$.allergies[0].recordedDate").value("2024-03-01T15:00:00Z"))
                .andExpect(jsonPath("$.allergies[0].access_token").doesNotExist());
    }

    @Test
    @Tag("M3-REQ-09")
    @DisplayName("CTL: missing login returns 401 and service is not called")
    void unauthenticated() throws Exception {
        mvc.perform(get(URL))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.source").value("CARECONNECT"));

        verifyNoInteractions(service, policy);
    }

    @Test
    @Tag("M3-REQ-03")
    @DisplayName("CTL: no patient permission returns 403 and does not call service")
    void forbidden() throws Exception {
        when(policy.canView("clinician", 42)).thenReturn(false);

        mvc.perform(get(URL).principal(USER))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value("ACCESS_DENIED"))
                .andExpect(jsonPath("$.retryable").value(false));

        verify(service, never()).getAllergies(anyLong());
    }

    @Test
    @DisplayName("CTL: unknown local patient returns 404")
    void notFound() throws Exception {
        when(policy.canView("clinician", 42)).thenReturn(true);
        when(service.getAllergies(42)).thenThrow(new UnknownPatientException());

        mvc.perform(get(URL).principal(USER))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code").value("PATIENT_NOT_FOUND"));
    }

    @Test
    @DisplayName("CTL: invalid patient id returns 400 without calling collaborators")
    void badRequest() throws Exception {
        mvc.perform(get("/v1/api/cerner/patients/abc/allergies").principal(USER))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("INVALID_PATIENT_ID"));

        verifyNoInteractions(service, policy);
    }

    @Test
    @Tag("M3-REQ-09")
    @DisplayName("CTL: expired Cerner authorization maps to source error envelope")
    void sourceAuthExpired() throws Exception {
        when(policy.canView("clinician", 42)).thenReturn(true);
        when(service.getAllergies(42)).thenThrow(new CernerSourceException("CERNER_AUTH_EXPIRED", false));

        mvc.perform(get(URL).principal(USER))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("CERNER_AUTH_EXPIRED"))
                .andExpect(jsonPath("$.source").value("CERNER"))
                .andExpect(jsonPath("$.retryable").value(false));
    }

    @Test
    @DisplayName("CTL: Cerner unavailable is retryable and leaks no internal details")
    void sourceUnavailable() throws Exception {
        when(policy.canView("clinician", 42)).thenReturn(true);
        when(service.getAllergies(42)).thenThrow(new CernerSourceException("CERNER_UNAVAILABLE", true));

        mvc.perform(get(URL).principal(USER))
                .andExpect(status().isBadGateway())
                .andExpect(jsonPath("$.code").value("CERNER_UNAVAILABLE"))
                .andExpect(jsonPath("$.retryable").value(true))
                .andExpect(jsonPath("$.message").value("Cerner source error"))
                .andExpect(jsonPath("$.stackTrace").doesNotExist());
    }

    @Test
    @Tag("M3-REQ-04")
    @DisplayName("CTL: empty result serializes as successful empty response")
    void empty() throws Exception {
        when(policy.canView("clinician", 42)).thenReturn(true);
        when(service.getAllergies(42)).thenReturn(List.of());

        mvc.perform(get(URL).principal(USER))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.allergies").isEmpty());
    }
}
