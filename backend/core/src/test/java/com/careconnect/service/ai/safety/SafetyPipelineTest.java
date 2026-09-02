package com.careconnect.service.ai.safety;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

class SafetyPipelineTest {

    private SafetyPipeline pipeline;

    private static SafetyInput input(
            final String query,
            final String draft,
            final boolean groundingFailed,
            final List<String> groundingCodes) {
        return new SafetyInput(
                query,
                draft,
                List.of(),
                42L,
                7L,
                UUID.randomUUID(),
                UUID.randomUUID(),
                UUID.randomUUID(),
                "ASK_AI",
                "en-US",
                groundingFailed,
                groundingCodes);
    }

    @BeforeEach
    void setUp() {
        pipeline = new SafetyPipeline(new TierClassifier());
    }

    @Test
    @DisplayName("emergency symptom text holds at Tier 2")
    void emergency_holdsTier2() {
        final SafetyOutcome outcome = pipeline.process(input(
                "I have chest pain right now",
                "Based on records, patient reported chest pain.",
                false,
                List.of()));

        assertThat(outcome.decision()).isEqualTo(SafetyDecision.HOLD_TIER2);
        assertThat(outcome.tier()).isEqualTo(2);
        assertThat(outcome.triggerCodes()).contains("EMERGENCY_SYMPTOM");
    }

    @Test
    @DisplayName("medication-change text holds at Tier 2")
    void medicationChange_holdsTier2() {
        final SafetyOutcome outcome = pipeline.process(input(
                "Should I stop taking metformin?",
                "Records show metformin was started.",
                false,
                List.of()));

        assertThat(outcome.decision()).isEqualTo(SafetyDecision.HOLD_TIER2);
        assertThat(outcome.triggerCodes()).contains("MEDICATION_CHANGE");
    }

    @Test
    @DisplayName("dosage calculation text holds at Tier 2")
    void dosageCalc_holdsTier2() {
        final SafetyOutcome outcome = pipeline.process(input(
                "How much should I take for a dosage calculation?",
                "Records mention a prior dose of 500 mg.",
                false,
                List.of()));

        assertThat(outcome.decision()).isEqualTo(SafetyDecision.HOLD_TIER2);
        assertThat(outcome.triggerCodes()).contains("DOSAGE_CALC");
    }

    @Test
    @DisplayName("safe grounded text delivers at Tier 1")
    void safeText_deliversTier1() {
        final SafetyOutcome outcome = pipeline.process(input(
                "What was discussed at the last visit?",
                "The follow-up visit reviewed routine labs.",
                false,
                List.of()));

        assertThat(outcome.decision()).isEqualTo(SafetyDecision.DELIVER_TIER1);
        assertThat(outcome.tier()).isEqualTo(1);
    }

    @Test
    @DisplayName("grounding failure with draft holds for HITL review")
    void groundingFailedWithDraft_holds() {
        final SafetyOutcome outcome = pipeline.process(input(
                "What medication changed?",
                "Started metformin 500mg twice daily",
                true,
                List.of("UNSUPPORTED_CLAIM")));

        assertThat(outcome.decision()).isEqualTo(SafetyDecision.HOLD_TIER2);
        assertThat(outcome.triggerCodes()).contains("UNSUPPORTED_CLAIM");
        assertThat(outcome.findings()).extracting(ValidationFinding::code)
                .contains("UNSUPPORTED_CLAIM");
    }

    @Test
    @DisplayName("grounding failure with empty draft blocks")
    void groundingFailedEmptyDraft_blocks() {
        final SafetyOutcome outcome = pipeline.process(input(
                "What medication changed?",
                "",
                true,
                List.of("UNSUPPORTED_CLAIM")));

        assertThat(outcome.decision()).isEqualTo(SafetyDecision.BLOCK);
        assertThat(outcome.triggerCodes()).contains("GROUNDING_FAILED");
    }
}
