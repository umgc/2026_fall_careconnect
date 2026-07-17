package com.careconnect.service.mail;

import com.careconnect.ai.AIServiceFactory;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;

import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;

class MailpieceImportanceAiAssistTest {

    private MailpieceImportanceAiAssist assist;

    @BeforeEach
    void setUp() {
        @SuppressWarnings("unchecked")
        final ObjectProvider<AIServiceFactory> provider = mock(ObjectProvider.class);
        assist = new MailpieceImportanceAiAssist(
                provider, new ObjectMapper(), "amazon.nova-lite-v1:0", true);
    }

    @Test
    @DisplayName("parseResponse extracts level, confidence, category, and reasoning")
    void parseResponse_validJson() {
        final Optional<MailpieceImportanceResult> result = assist.parseResponse("""
                {
                  "importanceLevel": "HIGH",
                  "confidence": 0.91,
                  "category": "MEDICAL",
                  "reasoning": "Hospital billing with clinical follow-up request."
                }
                """);

        assertThat(result).isPresent();
        assertThat(result.get().level()).isEqualTo(MailpieceImportanceLevel.HIGH);
        assertThat(result.get().confidence()).isEqualByComparingTo("0.91");
        assertThat(result.get().category()).isEqualTo("MEDICAL");
        assertThat(result.get().method()).isEqualTo(MailpieceImportanceResult.METHOD_AI);
        assertThat(result.get().reasoning()).contains("Hospital billing");
    }

    @Test
    @DisplayName("parseResponse tolerates markdown fences around JSON")
    void parseResponse_stripsMarkdown() {
        final Optional<MailpieceImportanceResult> result = assist.parseResponse("""
                ```json
                {"importanceLevel":"LOW","confidence":0.8,"category":"MARKETING","reasoning":"Coupon flyer."}
                ```
                """);

        assertThat(result).isPresent();
        assertThat(result.get().level()).isEqualTo(MailpieceImportanceLevel.LOW);
    }
}
