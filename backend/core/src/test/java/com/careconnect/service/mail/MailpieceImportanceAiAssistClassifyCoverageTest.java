package com.careconnect.service.mail;

import com.careconnect.ai.AIService;
import com.careconnect.ai.AIServiceFactory;
import com.careconnect.dto.ChatResponse;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class MailpieceImportanceAiAssistClassifyCoverageTest {

    @SuppressWarnings("unchecked")
    private static ObjectProvider<AIServiceFactory> provider(AIServiceFactory factory) {
        ObjectProvider<AIServiceFactory> p = mock(ObjectProvider.class);
        when(p.getIfAvailable()).thenReturn(factory);
        return p;
    }

    @Test
    void classifyCallsModelAndParsesJson() {
        AIServiceFactory factory = mock(AIServiceFactory.class);
        AIService ai = mock(AIService.class);
        when(factory.getService()).thenReturn(ai);
        ChatResponse resp = new ChatResponse();
        resp.setAiResponse("Here: {\"importanceLevel\":\"HIGH\",\"confidence\":0.9,"
                + "\"category\":\"medical\",\"reasoning\":\"Lab results\"} thanks");
        when(ai.processChat(any())).thenReturn(resp);
        MailpieceImportanceAiAssist assist = new MailpieceImportanceAiAssist(
                provider(factory), new ObjectMapper(), "model-x", true);

        MailpieceImportanceResult hint = MailpieceImportanceResult.of(MailpieceImportanceLevel.MODERATE, 0.5,
                MailpieceImportanceResult.METHOD_AI, "rules", "hint", "OTHER");
        assertThat(assist.classify("Clinic", "Results", "ocr text", hint)).isPresent();
        assertThat(assist.classify(null, null, null, null)).isPresent();

        resp.setAiResponse("{\"importanceLevel\":\"LOW\",\"category\":\"weird\"}");
        assertThat(assist.classify("a", "b", "c", null)).isPresent();
        resp.setAiResponse("{\"category\":\"\"}");
        assertThat(assist.classify("a", "b", "c", null)).isEmpty();
        resp.setAiResponse("not json at all");
        assertThat(assist.classify("a", "b", "c", null)).isEmpty();
        when(ai.processChat(any())).thenReturn(null);
        assertThat(assist.classify("a", "b", "c", null)).isEmpty();
        when(ai.processChat(any())).thenThrow(new RuntimeException("bedrock down"));
        assertThat(assist.classify("a", "b", "c", null)).isEmpty();
    }

    @Test
    void classifySkipsWhenFactoryUnavailableOrDisabled() {
        assertThat(new MailpieceImportanceAiAssist(provider(null), new ObjectMapper(), "m", true)
                .classify("a", "b", "c", null)).isEmpty();
        assertThat(new MailpieceImportanceAiAssist(provider(null), new ObjectMapper(), "m", false)
                .classify("a", "b", "c", null)).isEmpty();
    }
}
