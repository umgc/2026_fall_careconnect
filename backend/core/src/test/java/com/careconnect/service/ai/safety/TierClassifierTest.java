package com.careconnect.service.ai.safety;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

class TierClassifierTest {

    private TierClassifier classifier;

    private static SafetyInput input(final String query, final String draft) {
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
                false,
                List.of());
    }

    @BeforeEach
    void setUp() {
        classifier = new TierClassifier();
    }

    @Test
    @DisplayName("emergency pattern takes priority over medication-change")
    void emergency_outranksMedicationChange() {
        final SafetyOutcome outcome = classifier.classify(
                input("chest pain — should I stop taking metformin?", "call 911"),
                new ArrayList<>());

        assertThat(outcome.decision()).isEqualTo(SafetyDecision.HOLD_TIER2);
        assertThat(outcome.triggerCodes()).containsExactly("EMERGENCY_SYMPTOM");
    }

    @Test
    @DisplayName("dosage calc takes priority over medication-change")
    void dosageCalc_outranksMedicationChange() {
        final SafetyOutcome outcome = classifier.classify(
                input("calculate how much to take and then increase the dose", "ok"),
                new ArrayList<>());

        assertThat(outcome.decision()).isEqualTo(SafetyDecision.HOLD_TIER2);
        assertThat(outcome.triggerCodes()).containsExactly("DOSAGE_CALC");
    }

    @Test
    @DisplayName("medication-change holds when no higher-priority pattern matches")
    void medicationChange_holdsWhenNoHigherPriority() {
        final SafetyOutcome outcome = classifier.classify(
                input("Can I increase the dose of my medicine?", "Records mention dose."),
                new ArrayList<>());

        assertThat(outcome.decision()).isEqualTo(SafetyDecision.HOLD_TIER2);
        assertThat(outcome.triggerCodes()).containsExactly("MEDICATION_CHANGE");
    }

    @Test
    @DisplayName("grounding failure short-circuits to Tier-2 hold")
    void groundingFailed_holdsBeforePatterns() {
        final SafetyInput input = new SafetyInput(
                "routine visit notes",
                "The weather was pleasant.",
                List.of(),
                42L,
                7L,
                UUID.randomUUID(),
                UUID.randomUUID(),
                UUID.randomUUID(),
                "ASK_AI",
                "en-US",
                true,
                List.of("UNSUPPORTED_CLAIM"));

        final SafetyOutcome outcome = classifier.classify(input, new ArrayList<>());

        assertThat(outcome.decision()).isEqualTo(SafetyDecision.HOLD_TIER2);
        assertThat(outcome.triggerCodes()).containsExactly("UNSUPPORTED_CLAIM");
    }

    @Test
    @DisplayName("general medication mention delivers Tier 1 with confirm escalation")
    void generalMed_deliversWithConfirmEscalation() {
        final SafetyOutcome outcome = classifier.classify(
                input("What medication is listed?", "Metformin 500 mg twice daily"),
                new ArrayList<>());

        assertThat(outcome.decision()).isEqualTo(SafetyDecision.DELIVER_TIER1);
        assertThat(outcome.triggerCodes()).contains("GENERAL_MEDICATION_MENTION");
        assertThat(outcome.escalationLevel()).isEqualTo("confirm-with-provider");
    }

    @Test
    @DisplayName("non-clinical text delivers Tier 1 with no escalation")
    void safeText_deliversNoneEscalation() {
        final SafetyOutcome outcome = classifier.classify(
                input("What was discussed?", "Follow-up visit reviewed routine labs."),
                new ArrayList<>());

        assertThat(outcome.decision()).isEqualTo(SafetyDecision.DELIVER_TIER1);
        assertThat(outcome.escalationLevel()).isEqualTo("none");
    }
}
