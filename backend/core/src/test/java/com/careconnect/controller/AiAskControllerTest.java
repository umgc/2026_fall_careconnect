package com.careconnect.controller;

import com.careconnect.dto.ai.AiAskRequest;
import com.careconnect.dto.ai.InputModality;
import com.careconnect.model.User;
import com.careconnect.security.Permission;
import com.careconnect.security.RequirePermission;
import com.careconnect.security.Role;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.ai.ask.AiAskConfirmationService;
import com.careconnect.service.ai.ask.AiAskService;
import com.careconnect.service.ai.ask.AiAskShareService;
import com.careconnect.service.ai.ask.AskAiGroundingException;
import com.careconnect.service.ai.ask.AskAiRejectedException;
import com.careconnect.service.ai.ask.AskAiUnavailableException;
import com.careconnect.service.ai.retrieval.ForbiddenScopeException;
import com.careconnect.service.ai.retrieval.ScopeDenialReason;
import com.careconnect.util.SecurityUtil;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.ArgumentCaptor;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import java.util.UUID;

import static org.hamcrest.Matchers.hasSize;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@ExtendWith(MockitoExtension.class)
class AiAskControllerTest {

    @Mock
    private AiAskService aiAskService;
    @Mock
    private AiAskConfirmationService askConfirmationService;
    @Mock
    private AiAskShareService askShareService;
    @Mock
    private SecurityUtil securityUtil;

    private MockMvc mockMvc;
    private User caller;

    @BeforeEach
    void setUp() {
        mockMvc = MockMvcBuilders.standaloneSetup(
                        new AiAskController(
                                aiAskService, askConfirmationService, askShareService, securityUtil))
                .setControllerAdvice(new AiAskExceptionAdvice())
                .build();
        caller = new User();
        caller.setId(7L);
        caller.setRole(Role.PATIENT);
        lenient().when(securityUtil.resolveCurrentUser()).thenReturn(caller);
    }

    @Test
    @DisplayName("primary Ask AI URL returns correlated 502 WITHHELD contract")
    void ask_primaryUrl_groundingFailurePreservesCorrelation() throws Exception {
        final UUID requestId = UUID.randomUUID();
        final UUID auditId = UUID.randomUUID();
        final UUID sessionId = UUID.randomUUID();
        when(aiAskService.ask(any(), any())).thenThrow(new AskAiGroundingException(
                requestId, auditId, sessionId, "Citation validation failed"));

        mockMvc.perform(post("/api/ai/ask")
                        .contentType("application/json")
                        .content(requestJson(null)))
                .andExpect(status().isBadGateway())
                .andExpect(jsonPath("$.success").value(false))
                .andExpect(jsonPath("$.requestId").value(requestId.toString()))
                .andExpect(jsonPath("$.auditId").value(auditId.toString()))
                .andExpect(jsonPath("$.sessionId").value(sessionId.toString()))
                .andExpect(jsonPath("$.deliveryStatus").value("WITHHELD"))
                .andExpect(jsonPath("$.answer").doesNotExist())
                .andExpect(jsonPath("$.citations", hasSize(0)))
                .andExpect(jsonPath("$.error.code").value("UNGROUNDED_RESPONSE"));
        final ArgumentCaptor<AiAskRequest> requestCaptor =
                ArgumentCaptor.forClass(AiAskRequest.class);
        verify(aiAskService).ask(any(), requestCaptor.capture());
        assertThat(requestCaptor.getValue().inputModality()).isEqualTo(InputModality.TEXT);
    }

    @Test
    @DisplayName("versioned Ask AI URL returns correlated 503 and preserves request session")
    void ask_versionedUrl_unavailablePreservesCorrelation() throws Exception {
        final UUID requestId = UUID.randomUUID();
        final UUID auditId = UUID.randomUUID();
        final UUID sessionId = UUID.randomUUID();
        when(aiAskService.ask(any(), any())).thenThrow(new AskAiUnavailableException(
                requestId,
                auditId,
                sessionId,
                "RETRIEVAL_UNAVAILABLE",
                "Bedrock unavailable",
                null));

        mockMvc.perform(post("/v1/api/ai/ask")
                        .contentType("application/json")
                        .content(requestJson(sessionId)))
                .andExpect(status().isServiceUnavailable())
                .andExpect(jsonPath("$.requestId").value(requestId.toString()))
                .andExpect(jsonPath("$.auditId").value(auditId.toString()))
                .andExpect(jsonPath("$.sessionId").value(sessionId.toString()))
                .andExpect(jsonPath("$.deliveryStatus").value("WITHHELD"))
                .andExpect(jsonPath("$.answer").doesNotExist())
                .andExpect(jsonPath("$.citations", hasSize(0)))
                .andExpect(jsonPath("$.error.code").value("RETRIEVAL_UNAVAILABLE"));
    }

    @Test
    @DisplayName("post-allocation safety rejection preserves correlation")
    void ask_safetyRejectionPreservesCorrelation() throws Exception {
        final UUID requestId = UUID.randomUUID();
        final UUID auditId = UUID.randomUUID();
        final UUID sessionId = UUID.randomUUID();
        when(aiAskService.ask(any(), any())).thenThrow(new AskAiRejectedException(
                requestId,
                auditId,
                sessionId,
                "SAFETY_VALIDATION_FAILED",
                "Query blocked by input safety checks",
                422));

        mockMvc.perform(post("/api/ai/ask")
                        .contentType("application/json")
                        .content(requestJson(sessionId)))
                .andExpect(status().isUnprocessableEntity())
                .andExpect(jsonPath("$.requestId").value(requestId.toString()))
                .andExpect(jsonPath("$.auditId").value(auditId.toString()))
                .andExpect(jsonPath("$.sessionId").value(sessionId.toString()))
                .andExpect(jsonPath("$.deliveryStatus").value("WITHHELD"))
                .andExpect(jsonPath("$.error.code").value("SAFETY_VALIDATION_FAILED"));
    }

    @Test
    @DisplayName("bean validation returns correlated Ask AI WITHHELD contract")
    void ask_invalidRequestUsesAskAiContract() throws Exception {
        mockMvc.perform(post("/api/ai/ask")
                        .contentType("application/json")
                        .content("{\"query\":\" \",\"patientId\":null}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.success").value(false))
                .andExpect(jsonPath("$.requestId").isNotEmpty())
                .andExpect(jsonPath("$.auditId").isNotEmpty())
                .andExpect(jsonPath("$.deliveryStatus").value("WITHHELD"))
                .andExpect(jsonPath("$.error.code").value("INVALID_REQUEST"));
    }

    @Test
    void ask_nonPositivePatientIdIsRejectedBeforeServiceInvocation() throws Exception {
        mockMvc.perform(post("/api/ai/ask")
                        .contentType("application/json")
                        .content(requestJson(null).replace(
                                "\"patientId\": 42", "\"patientId\": 0")))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.deliveryStatus").value("WITHHELD"))
                .andExpect(jsonPath("$.error.code").value("INVALID_REQUEST"));

        verify(aiAskService, org.mockito.Mockito.never()).ask(any(), any());
    }

    @Test
    @DisplayName("malformed JSON returns correlated Ask AI WITHHELD contract")
    void ask_malformedJsonUsesAskAiContract() throws Exception {
        mockMvc.perform(post("/api/ai/ask")
                        .contentType("application/json")
                        .content("{not-json"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.requestId").isNotEmpty())
                .andExpect(jsonPath("$.auditId").isNotEmpty())
                .andExpect(jsonPath("$.deliveryStatus").value("WITHHELD"))
                .andExpect(jsonPath("$.error.code").value("INVALID_REQUEST"));
    }

    @Test
    @DisplayName("unknown request fields are rejected by the strict contract")
    void ask_unknownFieldIsRejected() throws Exception {
        mockMvc.perform(post("/api/ai/ask")
                        .contentType("application/json")
                        .content(requestJson(null).replace(
                                "\"inputModality\": \"TEXT\"",
                                "\"inputModality\": \"TEXT\", \"unknown\": true")))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error.code").value("INVALID_REQUEST"));
    }

    @Test
    void ask_sourceTypesRejectsNullElements() throws Exception {
        mockMvc.perform(post("/api/ai/ask")
                        .contentType("application/json")
                        .content(requestJson(null).replace(
                                "\"locale\": \"en-US\"",
                                "\"locale\": \"en-US\", \"sourceTypes\": [null]")))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error.code").value("INVALID_REQUEST"));
    }

    @Test
    void ask_authenticationFailureIs401Contract() throws Exception {
        when(aiAskService.ask(any(), any()))
                .thenThrow(new UnauthorizedException("token expired"));

        mockMvc.perform(post("/api/ai/ask")
                        .contentType("application/json")
                        .content(requestJson(null)))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.deliveryStatus").value("WITHHELD"))
                .andExpect(jsonPath("$.error.code").value("UNAUTHORIZED"));
    }

    @Test
    void ask_unexpectedPipelineFailureIsStableCorrelatedContract() throws Exception {
        when(aiAskService.ask(any(), any()))
                .thenThrow(new IllegalStateException("patient@example.com"));

        mockMvc.perform(post("/api/ai/ask")
                        .contentType("application/json")
                        .content(requestJson(null)))
                .andExpect(status().isInternalServerError())
                .andExpect(jsonPath("$.requestId").isNotEmpty())
                .andExpect(jsonPath("$.auditId").isNotEmpty())
                .andExpect(jsonPath("$.deliveryStatus").value("WITHHELD"))
                .andExpect(jsonPath("$.error.code").value("INTERNAL_ERROR"))
                .andExpect(jsonPath("$.error.message")
                        .value("Ask AI could not complete the request"));
    }

    @Test
    void ask_forbiddenScopeDoesNotExposePatientOrRelationshipDetails() throws Exception {
        final UUID auditId = UUID.randomUUID();
        when(aiAskService.ask(any(), any())).thenThrow(ForbiddenScopeException.of(
                ScopeDenialReason.PATIENT_OUT_OF_SCOPE,
                42L,
                7L,
                "Patient 42 has no active caregiver link for caller 7",
                auditId));

        mockMvc.perform(post("/api/ai/ask")
                        .contentType("application/json")
                        .content(requestJson(null)))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.error.code").value("FORBIDDEN_SCOPE"))
                .andExpect(jsonPath("$.error.message")
                        .value("Requested records are not available for Ask AI"));
    }

    @Test
    void askEndpointRequiresAiFeaturePermission() throws Exception {
        final RequirePermission requirement = AiAskController.class
                .getMethod("ask", AiAskRequest.class)
                .getAnnotation(RequirePermission.class);

        assertThat(requirement).isNotNull();
        assertThat(requirement.value()).isEqualTo(Permission.USE_AI_FEATURES);
    }

    @Test
    @DisplayName("share endpoint returns share receipt on success")
    void share_successReturnsReceipt() throws Exception {
        when(askShareService.share(any(), any()))
                .thenReturn(new com.careconnect.dto.ai.AiAskShareResponse(
                        UUID.fromString("11111111-1111-1111-1111-111111111111"),
                        42L,
                        UUID.fromString("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"),
                        java.util.List.of(11L, 12L),
                        2,
                        java.time.Instant.parse("2026-07-27T12:00:00Z")));

        mockMvc.perform(post("/api/ai/ask/share")
                        .contentType("application/json")
                        .content("""
                                {
                                  "patientId": 42,
                                  "sessionId": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
                                  "messages": [
                                    {"role": "user", "text": "Hello", "occurredAt": "2026-07-27T12:00:00Z"}
                                  ]
                                }
                                """))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.shareId").value("11111111-1111-1111-1111-111111111111"))
                .andExpect(jsonPath("$.patientId").value(42))
                .andExpect(jsonPath("$.recipientUserIds", hasSize(2)))
                .andExpect(jsonPath("$.messageCount").value(2));
    }

    @Test
    @DisplayName("share endpoint maps forbidden scope to 403")
    void share_forbiddenScopeReturns403() throws Exception {
        when(askShareService.share(any(), any()))
                .thenThrow(ForbiddenScopeException.of(
                        ScopeDenialReason.PATIENT_OUT_OF_SCOPE,
                        42L,
                        7L,
                        "no access",
                        UUID.randomUUID()));

        mockMvc.perform(post("/v1/api/ai/ask/share")
                        .contentType("application/json")
                        .content("""
                                {
                                  "patientId": 42,
                                  "messages": [
                                    {"role": "user", "text": "Hello"}
                                  ]
                                }
                                """))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.error").value("FORBIDDEN_SCOPE"));
    }

    @Test
    @DisplayName("share endpoint maps AskAiRejectedException to status from exception")
    void share_rejectedReturnsMappedStatus() throws Exception {
        when(askShareService.share(any(), any()))
                .thenThrow(new AskAiRejectedException("NO_CAREGIVER", "No linked caregiver", 400));

        mockMvc.perform(post("/api/ai/ask/share")
                        .contentType("application/json")
                        .content("""
                                {
                                  "patientId": 42,
                                  "messages": [
                                    {"role": "user", "text": "Hello"}
                                  ]
                                }
                                """))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").value("NO_CAREGIVER"))
                .andExpect(jsonPath("$.message").value("No linked caregiver"));
    }

    @Test
    @DisplayName("list shares returns receipts for authorized patient")
    void listShares_success() throws Exception {
        when(askShareService.listShares(any(), eq(42L)))
                .thenReturn(java.util.List.of(new com.careconnect.dto.ai.AiAskShareResponse(
                        UUID.fromString("11111111-1111-1111-1111-111111111111"),
                        42L,
                        null,
                        java.util.List.of(11L),
                        1,
                        java.time.Instant.parse("2026-07-27T12:00:00Z"))));

        mockMvc.perform(get("/api/ai/ask/shares").param("patientId", "42"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(1)))
                .andExpect(jsonPath("$[0].shareId").value("11111111-1111-1111-1111-111111111111"))
                .andExpect(jsonPath("$[0].recipientUserIds[0]").value(11));
    }

    @Test
    @DisplayName("confirmation endpoint returns saved decision")
    void confirm_successReturnsDecision() throws Exception {
        final var saved = new com.careconnect.model.ai.ask.AiAskConfirmationDecision();
        saved.setDecision("CONFIRMED");
        saved.setSessionId(UUID.fromString("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"));
        saved.setCreatedAt(java.time.Instant.parse("2026-07-27T12:00:00Z"));
        when(askConfirmationService.recordDecision(any(), any())).thenReturn(saved);

        mockMvc.perform(post("/api/ai/ask/confirmation")
                        .contentType("application/json")
                        .content("""
                                {
                                  "sessionId": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
                                  "patientId": 42,
                                  "decision": "CONFIRMED"
                                }
                                """))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true))
                .andExpect(jsonPath("$.decision").value("CONFIRMED"));
    }

    @Test
    @DisplayName("confirmation endpoint maps forbidden scope to 403")
    void confirm_forbiddenScopeReturns403() throws Exception {
        when(askConfirmationService.recordDecision(any(), any()))
                .thenThrow(ForbiddenScopeException.of(
                        ScopeDenialReason.PATIENT_OUT_OF_SCOPE,
                        42L,
                        7L,
                        "no access",
                        UUID.randomUUID()));

        mockMvc.perform(post("/api/ai/ask/confirmation")
                        .contentType("application/json")
                        .content("""
                                {
                                  "sessionId": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
                                  "patientId": 42,
                                  "decision": "CONFIRMED"
                                }
                                """))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.error").value("FORBIDDEN_SCOPE"));
    }

    @Test
    @DisplayName("confirmation endpoint maps illegal argument to 400")
    void confirm_illegalArgumentReturns400() throws Exception {
        when(askConfirmationService.recordDecision(any(), any()))
                .thenThrow(new IllegalArgumentException("bad decision"));

        mockMvc.perform(post("/api/ai/ask/confirmation")
                        .contentType("application/json")
                        .content("""
                                {
                                  "sessionId": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
                                  "patientId": 42,
                                  "decision": "NOPE"
                                }
                                """))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").value("bad decision"));
    }

    private static String requestJson(final UUID sessionId) {
        final String session = sessionId == null
                ? "null"
                : "\"" + sessionId + "\"";
        return """
                {
                  "query": "What medication changed?",
                  "patientId": 42,
                  "inputModality": "TEXT",
                  "locale": "en-US",
                  "sessionId": %s
                }
                """.formatted(session);
    }
}
