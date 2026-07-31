package com.careconnect.service;

import com.careconnect.ai.AIService;
import com.careconnect.ai.AIServiceFactory;
import com.careconnect.dto.ChatRequest;
import com.careconnect.dto.ChatResponse;
import com.careconnect.service.safety.AiOutputValidationService;
import com.careconnect.service.safety.AiOutputValidationService.ValidationOutcome;
import com.careconnect.service.safety.AiOutputValidationService.ValidationResult;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.when;

/**
 * WBS 3.15.3 
 * PASS delivers as-is, HOLD/REJECT replace the raw text so it never reaches the user.
 */
@ExtendWith(MockitoExtension.class)
class BedrockAIChatAdapterTest {

    @Mock AIServiceFactory aiServiceFactory;
    @Mock AIService downstream;
    @Mock AiOutputValidationService outputValidationService;

    @InjectMocks BedrockAIChatAdapter adapter;

    private ChatRequest request() {
        ChatRequest r = new ChatRequest();
        r.setUserId(7L);
        r.setPatientId(42L);
        r.setConversationId("conv-1");
        r.setMessage("hi");
        return r;
    }

    private void stubDownstream(String aiText) {
        when(aiServiceFactory.getService()).thenReturn(downstream);
        when(downstream.processChat(any()))
                .thenReturn(ChatResponse.builder().success(true).aiResponse(aiText).build());
    }

    private void stubValidation(ValidationOutcome outcome, String reason) {
        when(outputValidationService.validate(anyString(), anyString(), any(), anyLong(), anyLong(), anyString()))
                .thenReturn(new ValidationResult(outcome, reason));
    }

    @Test
    void pass_deliversRawOutput() {
        stubDownstream("stay hydrated");
        stubValidation(ValidationOutcome.PASS, "ok");

        ChatResponse r = adapter.processChat(request());

        assertThat(r.getAiResponse()).isEqualTo("stay hydrated");
        assertThat(r.getSuccess()).isTrue();
    }

    @Test
    void hold_replacesOutputAndFlagsForReview() {
        stubDownstream("stop taking your medication");
        stubValidation(ValidationOutcome.HOLD, "unreviewed medical directive");

        ChatResponse r = adapter.processChat(request());

        assertThat(r.getAiResponse()).doesNotContain("stop taking your medication");
        assertThat(r.getAiResponse()).contains("reviewed");
        assertThat(r.getSuccess()).isTrue();
        assertThat(r.getErrorCode()).isEqualTo("HELD_FOR_REVIEW");
    }

    @Test
    void reject_replacesOutputAndFailsResponse() {
        stubDownstream("");
        stubValidation(ValidationOutcome.REJECT, "empty output");

        ChatResponse r = adapter.processChat(request());

        assertThat(r.getSuccess()).isFalse();
        assertThat(r.getErrorCode()).isEqualTo("OUTPUT_REJECTED");
    }

    @Test
    void upstreamFailure_skipsValidation() {
        when(aiServiceFactory.getService()).thenReturn(downstream);
        when(downstream.processChat(any()))
                .thenReturn(ChatResponse.builder().success(false).errorCode("INTERNAL_ERROR").build());

        ChatResponse r = adapter.processChat(request());

        assertThat(r.getSuccess()).isFalse();
        assertThat(r.getErrorCode()).isEqualTo("INTERNAL_ERROR");
    }
}
