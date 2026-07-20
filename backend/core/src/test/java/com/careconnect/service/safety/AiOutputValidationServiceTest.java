package com.careconnect.service.safety;

import com.careconnect.ai.AIService;
import com.careconnect.ai.AIServiceFactory;
import com.careconnect.dto.ChatResponse;
import com.careconnect.model.confirmation.ConfirmationSourceType;
import com.careconnect.model.safety.AuditSourceFeature;
import com.careconnect.service.MedicalDataAnonymizer;
import com.careconnect.service.confirmation.ConfirmationService;
import com.careconnect.service.safety.AiOutputValidationService.ValidationOutcome;
import com.careconnect.service.safety.AiOutputValidationService.ValidationResult;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class AiOutputValidationServiceTest {

    @Mock AiAuditLedgerService auditLedgerService;
    @Mock MedicalDataAnonymizer anonymizer;
    @Mock ConfirmationService confirmationService;
    @Mock AIServiceFactory aiServiceFactory;
    @Mock AIService judgeService;

    @InjectMocks AiOutputValidationService service;

    private ValidationResult validate(String output) {
        return service.validate(output, "What are my meds?", AuditSourceFeature.ASK_AI, 42L, 7L, "sess-1");
    }

    private void stubJudge(String verdictResponse) {
        when(aiServiceFactory.getService()).thenReturn(judgeService);
        when(judgeService.processChat(any()))
                .thenReturn(ChatResponse.builder().success(true).aiResponse(verdictResponse).build());
    }

    // ── Guardrail stage (no AI call) ──────────────────────────────────────────

    @Test
    void blankOutput_isRejected() {
        ValidationResult r = validate("   ");
        assertThat(r.outcome()).isEqualTo(ValidationOutcome.REJECT);
        verify(confirmationService, never()).createItem(any(), anyString(), anyString(), anyLong());
        verify(aiServiceFactory, never()).getService();
    }

    @Test
    void phiInOutput_isHeldAndQueued_withoutJudge() {
        when(anonymizer.containsPHI(anyString())).thenReturn(true);
        ValidationResult r = validate("Patient John Smith, SSN 123-45-6789, is stable.");
        assertThat(r.outcome()).isEqualTo(ValidationOutcome.HOLD);
        verify(confirmationService).createItem(eq(ConfirmationSourceType.ASK_AI), anyString(), eq("sess-1"), eq(42L));
        verify(aiServiceFactory, never()).getService();
    }

    @Test
    void highRiskDirective_isHeld_withoutJudge() {
        when(anonymizer.containsPHI(anyString())).thenReturn(false);
        ValidationResult r = validate("You should stop taking your medication right away.");
        assertThat(r.outcome()).isEqualTo(ValidationOutcome.HOLD);
        assertThat(r.reason()).contains("directive");
        verify(aiServiceFactory, never()).getService();
    }

    @Test
    void overlyLongOutput_isHeld() {
        ValidationResult r = validate("x".repeat(AiOutputValidationService.MAX_OUTPUT_LENGTH + 1));
        assertThat(r.outcome()).isEqualTo(ValidationOutcome.HOLD);
    }

    @Test
    void heldOutput_isTruncatedToMaxLength_whenQueued() {
        validate("x".repeat(AiOutputValidationService.MAX_OUTPUT_LENGTH + 500));
        ArgumentCaptor<String> payload = ArgumentCaptor.forClass(String.class);
        verify(confirmationService).createItem(any(), payload.capture(), any(), anyLong());
        assertThat(payload.getValue().length()).isEqualTo(AiOutputValidationService.MAX_OUTPUT_LENGTH);
    }

    @Test
    void expandedDirectivePhrases_areHeld_withoutJudge() {
        when(anonymizer.containsPHI(anyString())).thenReturn(false);
        for (String bad : java.util.List.of(
                "You can just quit your meds.",
                "Go ahead and discontinue therapy.",
                "You can stop the insulin.",
                "Feel free to skip your dose.",
                "You should increase your insulin.",
                "There is no need to call your doctor.")) {
            ValidationResult r = validate(bad);
            assertThat(r.outcome()).as(bad).isEqualTo(ValidationOutcome.HOLD);
            assertThat(r.reason()).as(bad).contains("directive");
        }
        verify(aiServiceFactory, never()).getService();
    }

    // ── Judge stage (second AI review) ────────────────────────────────────────

    @Test
    void judgeApproves_passes() {
        when(anonymizer.containsPHI(anyString())).thenReturn(false);
        stubJudge("VERDICT: PASS\nREASON: grounded and caveated");
        ValidationResult r = validate("Stay hydrated and check with your care team.");
        assertThat(r.outcome()).isEqualTo(ValidationOutcome.PASS);
        assertThat(r.isDeliverable()).isTrue();
    }

    @Test
    void judgeHolds_isHeldAndQueued() {
        when(anonymizer.containsPHI(anyString())).thenReturn(false);
        stubJudge("VERDICT: HOLD\nREASON: ungrounded claim");
        ValidationResult r = validate("Your lab result means everything is perfect.");
        assertThat(r.outcome()).isEqualTo(ValidationOutcome.HOLD);
        verify(confirmationService).createItem(eq(ConfirmationSourceType.ASK_AI), anyString(), eq("sess-1"), eq(42L));
    }

    @Test
    void judgeRejects_isRejected_notQueued() {
        when(anonymizer.containsPHI(anyString())).thenReturn(false);
        stubJudge("VERDICT: REJECT\nREASON: harmful advice");
        ValidationResult r = validate("Here is how to harm yourself.");
        assertThat(r.outcome()).isEqualTo(ValidationOutcome.REJECT);
        verify(confirmationService, never()).createItem(any(), anyString(), anyString(), anyLong());
    }

    @Test
    void judgeUnavailable_failsSafeToHold() {
        when(anonymizer.containsPHI(anyString())).thenReturn(false);
        when(aiServiceFactory.getService()).thenThrow(new RuntimeException("no provider"));
        ValidationResult r = validate("Some plausible answer.");
        assertThat(r.outcome()).isEqualTo(ValidationOutcome.HOLD);
        assertThat(r.reason()).contains("judge unavailable");
    }

    @Test
    void judgeUnparseableResponse_failsSafeToHold() {
        when(anonymizer.containsPHI(anyString())).thenReturn(false);
        stubJudge("I think that answer looks fine to me.");
        ValidationResult r = validate("Some plausible answer.");
        assertThat(r.outcome()).isEqualTo(ValidationOutcome.HOLD);
        assertThat(r.reason()).contains("unparseable");
    }

    // ── Auditing ──────────────────────────────────────────────────────────────

    @Test
    void everyOutcome_isAudited() {
        when(anonymizer.containsPHI(anyString())).thenReturn(false);
        stubJudge("VERDICT: PASS\nREASON: ok");
        validate("All good, talk to your care team.");
        verify(auditLedgerService).logValidation(eq(AuditSourceFeature.ASK_AI), eq(42L), eq(7L), eq("sess-1"), any());
    }

    @Test
    @SuppressWarnings("unchecked")
    void auditPayload_recordsDecisionNotRawOutput() {
        when(anonymizer.containsPHI(anyString())).thenReturn(false);
        stubJudge("VERDICT: PASS\nREASON: ok");
        validate("some benign text about hydration");

        ArgumentCaptor<Map<String, Object>> payload = ArgumentCaptor.forClass(Map.class);
        verify(auditLedgerService).logValidation(any(), anyLong(), anyLong(), anyString(), payload.capture());
        assertThat(payload.getValue())
                .containsKeys("outcome", "reason", "outputLength")
                .doesNotContainKey("output");
    }

    @Test
    void queueingFailure_stillReturnsHold() {
        when(anonymizer.containsPHI(anyString())).thenReturn(true);
        when(confirmationService.createItem(any(), anyString(), any(), anyLong()))
                .thenThrow(new RuntimeException("db down"));
        ValidationResult r = validate("John Smith at 555-123-4567");
        assertThat(r.outcome()).isEqualTo(ValidationOutcome.HOLD);
    }
}
