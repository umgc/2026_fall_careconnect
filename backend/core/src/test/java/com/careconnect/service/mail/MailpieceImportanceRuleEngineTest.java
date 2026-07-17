package com.careconnect.service.mail;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class MailpieceImportanceRuleEngineTest {

    private MailpieceImportanceRuleEngine engine;

    @BeforeEach
    void setUp() {
        engine = new MailpieceImportanceRuleEngine();
    }

    @Test
    @DisplayName("pharmacy/prescription keywords classify HIGH without AI escalation")
    void evaluate_highMedicalKeywords() {
        final var outcome = engine.evaluate("CVS Pharmacy", "Prescription ready", null);

        assertThat(outcome.result().level()).isEqualTo(MailpieceImportanceLevel.HIGH);
        assertThat(outcome.result().category()).isEqualTo("MEDICAL");
        assertThat(outcome.result().confidence().doubleValue())
                .isGreaterThanOrEqualTo(MailpieceImportanceRuleEngine.HIGH_CONFIDENCE_THRESHOLD);
        assertThat(outcome.escalateToAi()).isFalse();
        assertThat(outcome.result().reasoning()).contains("prescription");
    }

    @Test
    @DisplayName("marketing keywords classify LOW")
    void evaluate_lowMarketingKeywords() {
        final var outcome = engine.evaluate("Retail Co", "Special offer coupon catalog", null);

        assertThat(outcome.result().level()).isEqualTo(MailpieceImportanceLevel.LOW);
        assertThat(outcome.result().category()).isEqualTo("MARKETING");
        assertThat(outcome.escalateToAi()).isFalse();
    }

    @Test
    @DisplayName("no keywords escalate to AI with UNKNOWN")
    void evaluate_unknownEscalates() {
        final var outcome = engine.evaluate("Neighbor", "Photo greeting card", null);

        assertThat(outcome.result().level()).isEqualTo(MailpieceImportanceLevel.UNKNOWN);
        assertThat(outcome.escalateToAi()).isTrue();
    }

    @Test
    @DisplayName("conflicting moderate and marketing keywords escalate")
    void evaluate_conflictEscalates() {
        final var outcome = engine.evaluate(
                "Brand Bank", "Account statement and special offer coupon", null);

        assertThat(outcome.result().level()).isEqualTo(MailpieceImportanceLevel.MODERATE);
        assertThat(outcome.escalateToAi()).isTrue();
        assertThat(outcome.result().reasoning()).containsIgnoringCase("conflicting");
    }
}
