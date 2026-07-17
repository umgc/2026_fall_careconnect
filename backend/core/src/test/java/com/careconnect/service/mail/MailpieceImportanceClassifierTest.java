package com.careconnect.service.mail;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class MailpieceImportanceClassifierTest {

    @Mock
    private MailpieceImportanceAiAssist aiAssist;

    private MailpieceImportanceClassifier classifier;

    @BeforeEach
    void setUp() {
        classifier = new MailpieceImportanceClassifier(new MailpieceImportanceRuleEngine(), aiAssist);
    }

    @Test
    @DisplayName("high-confidence rule hit skips AI and records RULES reasoning")
    void classify_highConfidenceRules_skipsAi() {
        final MailpieceImportanceResult result =
                classifier.classify("LabCorp", "Lab results available", null);

        assertThat(result.level()).isEqualTo(MailpieceImportanceLevel.HIGH);
        assertThat(result.method()).isEqualTo(MailpieceImportanceResult.METHOD_RULES);
        assertThat(result.reasoning()).isNotBlank();
        verify(aiAssist, never()).classify(anyString(), anyString(), any(), any());
    }

    @Test
    @DisplayName("inconclusive rules escalate to AI and become HYBRID")
    void classify_escalatesToHybrid() {
        when(aiAssist.classify(anyString(), anyString(), any(), any()))
                .thenReturn(Optional.of(MailpieceImportanceResult.of(
                        MailpieceImportanceLevel.MODERATE,
                        0.81d,
                        MailpieceImportanceResult.METHOD_AI,
                        "aws_bedrock:test",
                        "Looks like a utility bill.",
                        "FINANCIAL")));

        final MailpieceImportanceResult result =
                classifier.classify("Local Utility", "Your envelope", null);

        assertThat(result.method()).isEqualTo(MailpieceImportanceResult.METHOD_HYBRID);
        assertThat(result.level()).isEqualTo(MailpieceImportanceLevel.MODERATE);
        assertThat(result.reasoning()).contains("Rules suggested");
        assertThat(result.reasoning()).contains("AI confirmed");
    }

    @Test
    @DisplayName("AI failure keeps rule result with recorded fallback reasoning")
    void classify_aiUnavailable_keepsRules() {
        when(aiAssist.classify(anyString(), anyString(), any(), any()))
                .thenReturn(Optional.empty());

        final MailpieceImportanceResult result =
                classifier.classify("Unknown Sender", "Letter", null);

        assertThat(result.method()).isEqualTo(MailpieceImportanceResult.METHOD_RULES);
        assertThat(result.reasoning()).contains("AI assist unavailable");
    }
}
