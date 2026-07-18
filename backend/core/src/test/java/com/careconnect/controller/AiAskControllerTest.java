package com.careconnect.controller;

import com.careconnect.dto.ai.AiAskRequest;
import com.careconnect.dto.ai.AiAskResponse;
import com.careconnect.dto.ai.DeliveryStatus;
import com.careconnect.dto.ai.InputModality;
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
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class AiAskControllerTest {

    @Mock
    private AiAskService aiAskService;
    @Mock
    private SecurityUtil securityUtil;

    private AiAskController controller;
    private User caller;

    @BeforeEach
    void setUp() {
        controller = new AiAskController(aiAskService, securityUtil);
        caller = new User();
        caller.setId(7L);
        caller.setRole(Role.PATIENT);
        when(securityUtil.resolveCurrentUser()).thenReturn(caller);
    }

    @Test
    @DisplayName("ungrounded model response returns 502 WITHHELD without answer or citations")
    void ask_ungroundedResponse_returnsBadGatewayWithheld() throws Exception {
        final AiAskRequest request = request();
        when(aiAskService.ask(caller, request))
                .thenThrow(new AskAiGroundingException("Citation validation failed"));

        final ResponseEntity<AiAskResponse> response = controller.ask(request);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.BAD_GATEWAY);
        assertThat(response.getBody()).isNotNull();
        assertThat(response.getBody().success()).isFalse();
        assertThat(response.getBody().deliveryStatus()).isEqualTo(DeliveryStatus.WITHHELD);
        assertThat(response.getBody().answer()).isNull();
        assertThat(response.getBody().citations()).isEmpty();
        assertThat(response.getBody().error().code()).isEqualTo("UNGROUNDED_RESPONSE");
    }

    @Test
    @DisplayName("inference outage remains a 503 WITHHELD response")
    void ask_inferenceUnavailable_returnsServiceUnavailable() throws Exception {
        final AiAskRequest request = request();
        when(aiAskService.ask(caller, request))
                .thenThrow(new AskAiUnavailableException("Bedrock unavailable"));

        final ResponseEntity<AiAskResponse> response = controller.ask(request);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.SERVICE_UNAVAILABLE);
        assertThat(response.getBody()).isNotNull();
        assertThat(response.getBody().deliveryStatus()).isEqualTo(DeliveryStatus.WITHHELD);
        assertThat(response.getBody().error().code()).isEqualTo("RETRIEVAL_UNAVAILABLE");
    }

    private static AiAskRequest request() {
        return new AiAskRequest(
                "What medication changed?",
                42L,
                null,
                null,
                InputModality.TEXT,
                "en-US",
                null);
    }
}
