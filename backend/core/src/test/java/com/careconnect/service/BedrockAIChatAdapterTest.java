package com.careconnect.service;

import com.careconnect.ai.AIService;
import com.careconnect.ai.AIServiceFactory;
import com.careconnect.dto.ChatRequest;
import com.careconnect.dto.ChatResponse;
import com.careconnect.dto.UserAIConfigDTO;
import com.careconnect.model.UserAIConfig;
import com.careconnect.service.safety.AiOutputValidationService;
import com.careconnect.service.safety.AiOutputValidationService.ValidationOutcome;
import com.careconnect.service.safety.AiOutputValidationService.ValidationResult;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

/**
 * WBS 3.15.3 — PASS delivers as-is, HOLD/REJECT replace the raw text so it never reaches the user.
 * WBS 3.15.7 — the live Bedrock chat path assembles patient medical context (honoring the
 * data-source toggles) before invoking the model, and fails open.
 */
@ExtendWith(MockitoExtension.class)
class BedrockAIChatAdapterTest {

    @Mock AIServiceFactory aiServiceFactory;
    @Mock AIService downstream;
    @Mock AiOutputValidationService outputValidationService;
    @Mock MedicalContextService medicalContextService;
    @Mock UserAIConfigService userAIConfigService;

    @InjectMocks BedrockAIChatAdapter adapter;

    // --- WBS 3.15.3: output validation gate ---

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

    // --- WBS 3.15.7: patient context assembly ---

    private ChatRequest request(Long patientId) {
        ChatRequest r = new ChatRequest();
        r.setUserId(7L);
        r.setPatientId(patientId);
        r.setMessage("What are my meds?");
        return r;
    }

    /**
     * The adapter also runs the 3.15.3 validation gate after the model call, so the
     * validation service must be stubbed to PASS or these context tests would NPE on
     * a null ValidationResult. Uses any() rather than anyString() because the stubbed
     * response carries a null aiResponse, which anyString() would not match.
     */
    private ArgumentCaptor<ChatRequest> stubDownstream() {
        when(aiServiceFactory.getService()).thenReturn(downstream);
        when(downstream.processChat(any())).thenReturn(ChatResponse.builder().success(true).build());
        when(outputValidationService.validate(any(), any(), any(), any(), any(), any()))
                .thenReturn(new ValidationResult(ValidationOutcome.PASS, "ok"));
        return ArgumentCaptor.forClass(ChatRequest.class);
    }

    @Test
    void noPatientScope_sendsMessageUnchanged_andSkipsContext() {
        ArgumentCaptor<ChatRequest> captor = stubDownstream();

        adapter.processChat(request(null));

        verify(downstream).processChat(captor.capture());
        assertThat(captor.getValue().getMessage()).isEqualTo("What are my meds?");
        verifyNoInteractions(medicalContextService, userAIConfigService);
    }

    @Test
    void withPatient_prependsContextToMessage() {
        ArgumentCaptor<ChatRequest> captor = stubDownstream();
        when(userAIConfigService.getUserAIConfig(7L, 42L)).thenReturn(new UserAIConfigDTO());
        UserAIConfig cfg = new UserAIConfig();
        when(userAIConfigService.convertDTOToEntity(any())).thenReturn(cfg);
        when(medicalContextService.buildPatientContext(anyLong(), any(), any()))
                .thenReturn("PATIENT INFORMATION:\nName: Jane Doe");

        adapter.processChat(request(42L));

        verify(downstream).processChat(captor.capture());
        String sent = captor.getValue().getMessage();
        assertThat(sent)
                .contains("PATIENT INFORMATION:")
                .contains("USER QUESTION:")
                .contains("What are my meds?");
    }

    @Test
    void blankContext_sendsMessageUnchanged() {
        ArgumentCaptor<ChatRequest> captor = stubDownstream();
        when(userAIConfigService.getUserAIConfig(7L, 42L)).thenReturn(new UserAIConfigDTO());
        when(userAIConfigService.convertDTOToEntity(any())).thenReturn(new UserAIConfig());
        when(medicalContextService.buildPatientContext(anyLong(), any(), any())).thenReturn("   ");

        adapter.processChat(request(42L));

        verify(downstream).processChat(captor.capture());
        assertThat(captor.getValue().getMessage()).isEqualTo("What are my meds?");
    }

    @Test
    void contextAssemblyThrows_failsOpen_sendsOriginalMessage() {
        ArgumentCaptor<ChatRequest> captor = stubDownstream();
        when(userAIConfigService.getUserAIConfig(7L, 42L))
                .thenThrow(new RuntimeException("config lookup failed"));

        adapter.processChat(request(42L));

        verify(downstream).processChat(captor.capture());
        assertThat(captor.getValue().getMessage()).isEqualTo("What are my meds?");
        verify(medicalContextService, never()).buildPatientContext(anyLong(), any(), any());
    }
}
