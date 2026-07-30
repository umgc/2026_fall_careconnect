package com.careconnect.controller;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.careconnect.exception.GlobalExceptionHandler;
import com.careconnect.model.ConsentGrant;
import com.careconnect.model.User;
import com.careconnect.security.Role;
import com.careconnect.service.ConsentService;
import com.careconnect.util.SecurityUtil;
import java.time.Instant;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

@ExtendWith(MockitoExtension.class)
@DisplayName("ConsentController")
class ConsentControllerTest {

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
    @DisplayName("POST grant returns 403 for non-patient caller")
    void grant_forbiddenForCaregiver() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(user(20L, Role.CAREGIVER));

        mockMvc.perform(post("/api/v3/consent/ai-retrieval")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"granteeUserId\":20}"))
                .andExpect(status().isForbidden());

        verify(consentService, never()).grantAiRetrievalConsent(any(), any(), any(), any());
    }

    @Test
    @DisplayName("DELETE revoke returns 403 for non-patient caller")
    void revoke_forbiddenForCaregiver() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(user(20L, Role.CAREGIVER));

        mockMvc.perform(delete("/api/v3/consent/ai-retrieval")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"granteeUserId\":20}"))
                .andExpect(status().isForbidden());

        verify(consentService, never()).revokeAiRetrievalConsent(any(), any());
    }

    @Test
    @DisplayName("GET check returns 403 when caller is neither self nor admin")
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
    @DisplayName("GET check returns effective and explicit consent flags")
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
    @DisplayName("POST grant succeeds for patient caller")
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
}
