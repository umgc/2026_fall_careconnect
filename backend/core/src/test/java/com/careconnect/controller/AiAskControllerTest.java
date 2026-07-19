package com.careconnect.controller;

import com.careconnect.dto.ai.AiAskRequest;
import com.careconnect.dto.ai.InputModality;
import com.careconnect.model.User;
import com.careconnect.security.Role;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.ai.ask.AiAskService;
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
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@ExtendWith(MockitoExtension.class)
class AiAskControllerTest {

    @Mock
    private AiAskService aiAskService;
    @Mock
    private SecurityUtil securityUtil;

    private MockMvc mockMvc;
    private User caller;

    @BeforeEach
    void setUp() {
        mockMvc = MockMvcBuilders.standaloneSetup(
                        new AiAskController(aiAskService, securityUtil))
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
