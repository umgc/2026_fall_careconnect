package com.careconnect.controller;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.careconnect.exception.AppException;
import com.careconnect.exception.GlobalExceptionHandler;
import com.careconnect.model.ConsentGrant;
import com.careconnect.model.User;
import com.careconnect.security.Role;
import com.careconnect.service.consent.ConsentService;
import com.careconnect.util.SecurityUtil;

import java.time.Instant;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

@ExtendWith(MockitoExtension.class)
@DisplayName("ConsentController")
class ConsentControllerTest {

    private static final String MEDICARE_VIEW = "/api/v3/consent/medicare-view";

    @Mock
    private ConsentService consentService;
    @Mock
    private SecurityUtil securityUtil;

    private MockMvc mockMvc;

    @BeforeEach
    void setUp() {
        mockMvc = MockMvcBuilders.standaloneSetup(
                        new ConsentController(consentService, securityUtil))
                .setControllerAdvice(new GlobalExceptionHandler())
                .build();
    }

    private User user(final long id, final Role role) {
        final User user = new User();
        user.setId(id);
        user.setRole(role);
        return user;
    }

    @Test
    @DisplayName("TC-CONSENT-020 POST ai-retrieval by a non-patient caller is 403")
    void grant_forbiddenForCaregiver() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(user(20L, Role.CAREGIVER));

        mockMvc.perform(post("/api/v3/consent/ai-retrieval")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"granteeUserId\":20}"))
                .andExpect(status().isForbidden());

        verify(consentService, never()).grantAiRetrievalConsent(any(), any(), any(), any());
    }

    @Test
    @DisplayName("TC-CONSENT-021 DELETE ai-retrieval by a non-patient caller is 403")
    void revoke_forbiddenForCaregiver() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(user(20L, Role.CAREGIVER));

        mockMvc.perform(delete("/api/v3/consent/ai-retrieval")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"granteeUserId\":20}"))
                .andExpect(status().isForbidden());

        verify(consentService, never()).revokeAiRetrievalConsent(any(), any());
    }

    @Test
    @DisplayName("TC-CONSENT-022 GET ai-retrieval is 403 when the caller is neither party nor an admin")
    void check_forbiddenForUnrelatedCaller() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(user(99L, Role.CAREGIVER));

        mockMvc.perform(get("/api/v3/consent/ai-retrieval")
                        .param("patientUserId", "10")
                        .param("granteeUserId", "20"))
                .andExpect(status().isForbidden());

        verify(consentService, never()).isAiRetrievalConsentGranted(any(), any());
        verify(consentService, never()).isEffectiveAiRetrievalConsent(any(), any());
    }

    @Test
    @DisplayName("TC-CONSENT-023 GET ai-retrieval returns the effective and explicit consent flags")
    void check_returnsEffectiveAndExplicit() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(user(10L, Role.PATIENT));
        when(consentService.isAiRetrievalConsentGranted(20L, 10L)).thenReturn(false);
        when(consentService.isEffectiveAiRetrievalConsent(20L, 10L)).thenReturn(true);

        mockMvc.perform(get("/api/v3/consent/ai-retrieval")
                        .param("patientUserId", "10")
                        .param("granteeUserId", "20"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.granted").value(true))
                .andExpect(jsonPath("$.effectiveConsent").value(true))
                .andExpect(jsonPath("$.explicitGrant").value(false));
    }

    @Test
    @DisplayName("TC-CONSENT-024 POST ai-retrieval by the patient is 201")
    void grant_okForPatient() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(user(10L, Role.PATIENT));
        when(consentService.grantAiRetrievalConsent(eq(10L), eq(20L), any(), any()))
                .thenReturn(ConsentGrant.builder()
                        .id(1L)
                        .patientUserId(10L)
                        .granteeUserId(20L)
                        .granteeRole("CAREGIVER")
                        .scope(ConsentGrant.SCOPE_AI_RETRIEVAL)
                        .status(ConsentGrant.STATUS_ACTIVE)
                        .grantedAt(Instant.parse("2026-07-24T00:00:00Z"))
                        .build());

        mockMvc.perform(post("/api/v3/consent/ai-retrieval")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"granteeUserId\":20,\"granteeRole\":\"CAREGIVER\"}"))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.patientUserId").value(10))
                .andExpect(jsonPath("$.granteeUserId").value(20));
    }

    // ---- EHR_VIEW consent endpoints ------------------------------------------------

    @Test
    @DisplayName("POST ehr-view returns 403 for non-patient caller")
    void grantEhrView_forbiddenForCaregiver() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(user(20L, Role.CAREGIVER));

        mockMvc.perform(post("/api/v3/consent/ehr-view")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"granteeUserId\":30}"))
                .andExpect(status().isForbidden())
                // I3b: the refusal names EHR view consent, not AI retrieval consent.
                .andExpect(jsonPath("$.error").value("Only the patient may manage EHR view consent"));

        verify(consentService, never()).grantEhrViewConsent(any(), any(), any(), any());
    }

    @Test
    @DisplayName("POST ehr-view returns 400 when granteeUserId is missing")
    void grantEhrView_badRequestWhenGranteeMissing() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(user(10L, Role.PATIENT));

        mockMvc.perform(post("/api/v3/consent/ehr-view")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{}"))
                .andExpect(status().isBadRequest());

        verify(consentService, never()).grantEhrViewConsent(any(), any(), any(), any());
    }

    @Test
    @DisplayName("POST ehr-view grants consent for a patient caller")
    void grantEhrView_okForPatient() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(user(10L, Role.PATIENT));
        when(consentService.grantEhrViewConsent(eq(10L), eq(20L), any(), any()))
                .thenReturn(ConsentGrant.builder()
                        .id(7L)
                        .patientUserId(10L)
                        .granteeUserId(20L)
                        .granteeRole("CAREGIVER")
                        .scope("EHR_VIEW")
                        .status(ConsentGrant.STATUS_ACTIVE)
                        .grantedAt(Instant.parse("2026-07-24T00:00:00Z"))
                        .build());

        mockMvc.perform(post("/api/v3/consent/ehr-view")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"granteeUserId\":20,\"granteeRole\":\"CAREGIVER\"}"))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.patientUserId").value(10))
                .andExpect(jsonPath("$.granteeUserId").value(20))
                .andExpect(jsonPath("$.scope").value("EHR_VIEW"));
    }

    @Test
    @DisplayName("DELETE ehr-view returns 403 for non-patient caller")
    void revokeEhrView_forbiddenForCaregiver() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(user(20L, Role.CAREGIVER));

        mockMvc.perform(delete("/api/v3/consent/ehr-view")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"granteeUserId\":30}"))
                .andExpect(status().isForbidden())
                // I3b: the refusal names EHR view consent, not AI retrieval consent.
                .andExpect(jsonPath("$.error").value("Only the patient may manage EHR view consent"));

        verify(consentService, never()).revokeEhrViewConsent(any(), any());
    }

    @Test
    @DisplayName("DELETE ehr-view returns 400 when granteeUserId is missing")
    void revokeEhrView_badRequestWhenGranteeMissing() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(user(10L, Role.PATIENT));

        mockMvc.perform(delete("/api/v3/consent/ehr-view")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{}"))
                .andExpect(status().isBadRequest());

        verify(consentService, never()).revokeEhrViewConsent(any(), any());
    }

    @Test
    @DisplayName("DELETE ehr-view revokes and returns the count for a patient caller")
    void revokeEhrView_okForPatient() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(user(10L, Role.PATIENT));
        when(consentService.revokeEhrViewConsent(10L, 20L)).thenReturn(2);

        mockMvc.perform(delete("/api/v3/consent/ehr-view")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"granteeUserId\":20}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.patientUserId").value(10))
                .andExpect(jsonPath("$.granteeUserId").value(20))
                .andExpect(jsonPath("$.revokedCount").value(2));
    }

    @Test
    @DisplayName("GET ehr-view returns 403 when caller is neither party nor admin")
    void checkEhrView_forbiddenForUnrelatedCaller() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(user(99L, Role.CAREGIVER));

        mockMvc.perform(get("/api/v3/consent/ehr-view")
                        .param("patientUserId", "10")
                        .param("granteeUserId", "20"))
                .andExpect(status().isForbidden());

        verify(consentService, never()).isEhrViewConsentGranted(any(), any());
    }

    @Test
    @DisplayName("GET ehr-view returns the granted flag for the patient themselves")
    void checkEhrView_okForSelfPatient() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(user(10L, Role.PATIENT));
        when(consentService.isEhrViewConsentGranted(20L, 10L)).thenReturn(true);

        mockMvc.perform(get("/api/v3/consent/ehr-view")
                        .param("patientUserId", "10")
                        .param("granteeUserId", "20"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.patientUserId").value(10))
                .andExpect(jsonPath("$.granteeUserId").value(20))
                .andExpect(jsonPath("$.granted").value(true));
    }

    // ===== Medicare View (MEDICARE_VIEW) consent endpoints, PR #325 / WBS 6.2.56 =====
    // Test IDs TC-MCR-CONSENT-020 to 031, Software Test Plan §3.20. Status and body come from the
    // real GlobalExceptionHandler.

    @Test
    @DisplayName("TC-MCR-CONSENT-020 POST medicare-view by the patient returns 201 with a MEDICARE_VIEW grant; the patient id comes from the token, not the body")
    void medicareView_grant_createdForPatient() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(user(10L, Role.PATIENT));
        when(consentService.grantMedicareViewConsent(eq(10L), eq(20L), isNull(), isNull()))
                .thenReturn(ConsentGrant.builder()
                        .id(1L)
                        .patientUserId(10L)
                        .granteeUserId(20L)
                        .granteeRole("CAREGIVER")
                        .scope(ConsentGrant.SCOPE_MEDICARE_VIEW)
                        .status(ConsentGrant.STATUS_ACTIVE)
                        .grantedAt(Instant.parse("2026-10-13T00:00:00Z"))
                        .build());

        mockMvc.perform(post(MEDICARE_VIEW)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"granteeUserId\":20,\"patientUserId\":99}"))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.patientUserId").value(10))
                .andExpect(jsonPath("$.granteeUserId").value(20))
                .andExpect(jsonPath("$.scope").value("MEDICARE_VIEW"))
                .andExpect(jsonPath("$.status").value("ACTIVE"));
    }

    @Test
    @DisplayName("TC-MCR-CONSENT-021 POST medicare-view by a caregiver, family member or admin is 403 naming Medicare View consent, and nothing is granted")
    void medicareView_grant_forbiddenForNonPatients() throws Exception {
        for (final Role role : new Role[] {Role.CAREGIVER, Role.FAMILY_MEMBER, Role.ADMIN}) {
            when(securityUtil.resolveCurrentUser()).thenReturn(user(20L, role));

            mockMvc.perform(post(MEDICARE_VIEW)
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{\"granteeUserId\":20}"))
                    .andExpect(status().isForbidden())
                    .andExpect(jsonPath("$.error").value("Only the patient may manage Medicare View consent"));
        }

        verify(consentService, never()).grantMedicareViewConsent(any(), any(), any(), any());
    }

    @Test
    @DisplayName("TC-MCR-CONSENT-022 POST medicare-view without granteeUserId is 400 and nothing is granted")
    void medicareView_grant_requiresGrantee() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(user(10L, Role.PATIENT));

        mockMvc.perform(post(MEDICARE_VIEW)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").value("granteeUserId is required"));

        verify(consentService, never()).grantMedicareViewConsent(any(), any(), any(), any());
    }

    @Test
    @DisplayName("TC-MCR-CONSENT-023 POST medicare-view for a user with no caregiver link answers the service's 400")
    void medicareView_grant_noLinkIs400() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(user(10L, Role.PATIENT));
        when(consentService.grantMedicareViewConsent(eq(10L), eq(30L), any(), any()))
                .thenThrow(new AppException(HttpStatus.BAD_REQUEST,
                        "No active caregiver relationship with this patient"));

        mockMvc.perform(post(MEDICARE_VIEW)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"granteeUserId\":30}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").value("No active caregiver relationship with this patient"));
    }

    @Test
    @DisplayName("TC-MCR-CONSENT-024 DELETE medicare-view by the patient revokes for that patient and returns the count")
    void medicareView_revoke_okForPatient() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(user(10L, Role.PATIENT));
        when(consentService.revokeMedicareViewConsent(10L, 20L)).thenReturn(1);

        mockMvc.perform(delete(MEDICARE_VIEW)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"granteeUserId\":20}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.patientUserId").value(10))
                .andExpect(jsonPath("$.granteeUserId").value(20))
                .andExpect(jsonPath("$.revokedCount").value(1));
    }

    @Test
    @DisplayName("TC-MCR-CONSENT-025 DELETE medicare-view by a caregiver is 403 and nothing is revoked")
    void medicareView_revoke_forbiddenForCaregiver() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(user(20L, Role.CAREGIVER));

        mockMvc.perform(delete(MEDICARE_VIEW)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"granteeUserId\":20}"))
                .andExpect(status().isForbidden());

        verify(consentService, never()).revokeMedicareViewConsent(any(), any());
    }

    @Test
    @DisplayName("TC-MCR-CONSENT-026 DELETE medicare-view without granteeUserId is 400 and nothing is revoked")
    void medicareView_revoke_requiresGrantee() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(user(10L, Role.PATIENT));

        mockMvc.perform(delete(MEDICARE_VIEW)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{}"))
                .andExpect(status().isBadRequest());

        verify(consentService, never()).revokeMedicareViewConsent(any(), any());
    }

    @Test
    @DisplayName("TC-MCR-CONSENT-027 GET medicare-view by the patient returns the grant flags for their caregiver")
    void medicareView_check_okForPatient() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(user(10L, Role.PATIENT));
        when(consentService.isMedicareViewConsentGranted(20L, 10L)).thenReturn(true);
        when(consentService.isEffectiveMedicareViewConsent(20L, 10L)).thenReturn(true);

        mockMvc.perform(get(MEDICARE_VIEW)
                        .param("patientUserId", "10")
                        .param("granteeUserId", "20"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.granted").value(true))
                .andExpect(jsonPath("$.explicitGrant").value(true))
                .andExpect(jsonPath("$.effectiveConsent").value(true));
    }

    @Test
    @DisplayName("TC-MCR-CONSENT-028 GET medicare-view by the caregiver grantee is allowed and reports no grant as granted=false")
    void medicareView_check_okForGranteeAndFalseWithoutGrant() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(user(20L, Role.CAREGIVER));
        when(consentService.isMedicareViewConsentGranted(20L, 10L)).thenReturn(false);
        when(consentService.isEffectiveMedicareViewConsent(20L, 10L)).thenReturn(false);

        mockMvc.perform(get(MEDICARE_VIEW)
                        .param("patientUserId", "10")
                        .param("granteeUserId", "20"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.granted").value(false))
                .andExpect(jsonPath("$.explicitGrant").value(false));
    }

    @Test
    @DisplayName("TC-MCR-CONSENT-029 GET medicare-view by a user who is neither the patient, the grantee nor an admin is 403 and nothing is looked up")
    void medicareView_check_forbiddenForUnrelatedCaller() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(user(99L, Role.CAREGIVER));

        mockMvc.perform(get(MEDICARE_VIEW)
                        .param("patientUserId", "10")
                        .param("granteeUserId", "20"))
                .andExpect(status().isForbidden());

        verify(consentService, never()).isMedicareViewConsentGranted(any(), any());
        verify(consentService, never()).isEffectiveMedicareViewConsent(any(), any());
    }

    @Test
    @DisplayName("TC-MCR-CONSENT-030 every medicare-view endpoint answers 401 when no user is signed in")
    void medicareView_unauthenticatedIs401() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(null);

        mockMvc.perform(post(MEDICARE_VIEW).contentType(MediaType.APPLICATION_JSON).content("{\"granteeUserId\":20}"))
                .andExpect(status().isUnauthorized());
        mockMvc.perform(delete(MEDICARE_VIEW).contentType(MediaType.APPLICATION_JSON).content("{\"granteeUserId\":20}"))
                .andExpect(status().isUnauthorized());
        mockMvc.perform(get(MEDICARE_VIEW).param("patientUserId", "10").param("granteeUserId", "20"))
                .andExpect(status().isUnauthorized());

        verifyNoInteractions(consentService);
    }

    @Test
    @DisplayName("TC-MCR-CONSENT-031 the AI-retrieval refusal still names AI retrieval consent (regression of the shared patient check)")
    void aiRetrieval_refusalMessageUnchanged() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(user(20L, Role.CAREGIVER));

        mockMvc.perform(post("/api/v3/consent/ai-retrieval")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"granteeUserId\":20}"))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.error").value("Only the patient may manage AI retrieval consent"));
    }
}
