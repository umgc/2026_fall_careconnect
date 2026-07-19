package com.careconnect.controller;

import com.careconnect.model.User;
import com.careconnect.security.Role;
import com.careconnect.service.ai.ask.AiAskService;
import com.careconnect.service.ai.ask.AskAiGroundingException;
import com.careconnect.service.ai.ask.AskAiUnavailableException;
import com.careconnect.util.SecurityUtil;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import java.util.UUID;

import static org.hamcrest.Matchers.hasSize;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;
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
                .build();
        caller = new User();
        caller.setId(7L);
        caller.setRole(Role.PATIENT);
        when(securityUtil.resolveCurrentUser()).thenReturn(caller);
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

    private static String requestJson(final UUID sessionId) {
        final String session = sessionId == null
                ? "null"
                : "\"" + sessionId + "\"";
        return """
                {
                  "query": "What medication changed?",
                  "patientId": 42,
                  "modality": "TEXT",
                  "locale": "en-US",
                  "sessionId": %s
                }
                """.formatted(session);
    }
}
