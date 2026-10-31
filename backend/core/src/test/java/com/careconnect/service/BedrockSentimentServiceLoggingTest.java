package com.careconnect.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import ch.qos.logback.classic.Level;
import ch.qos.logback.classic.Logger;
import com.careconnect.service.BedrockSentimentService.SentimentResult;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.Map;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.slf4j.LoggerFactory;
import software.amazon.awssdk.core.SdkBytes;
import software.amazon.awssdk.services.bedrockruntime.BedrockRuntimeClient;
import software.amazon.awssdk.services.bedrockruntime.model.InvokeModelRequest;
import software.amazon.awssdk.services.bedrockruntime.model.InvokeModelResponse;

/**
 * Runs the main {@link BedrockSentimentService} entry points with debug logging enabled against a
 * mocked {@link BedrockRuntimeClient}, covering the logged and Bedrock-failure fallback paths.
 */
@DisplayName("BedrockSentimentService logged and fallback paths")
class BedrockSentimentServiceLoggingTest {

    private static final String CALL_ID = "call-log-1";

    private final Logger serviceLogger = (Logger) LoggerFactory.getLogger(BedrockSentimentService.class);
    private Level originalLevel;

    @BeforeEach
    void enableDebug() {
        originalLevel = serviceLogger.getLevel();
        serviceLogger.setLevel(Level.DEBUG);
    }

    @AfterEach
    void restore() {
        serviceLogger.setLevel(originalLevel);
    }

    private static BedrockSentimentService returning(final String body) {
        final BedrockRuntimeClient client = mock(BedrockRuntimeClient.class);
        when(client.invokeModel(any(InvokeModelRequest.class)))
                .thenReturn(InvokeModelResponse.builder().body(SdkBytes.fromUtf8String(body)).build());
        return new BedrockSentimentService(client, new ObjectMapper(), true);
    }

    private static BedrockSentimentService failing() {
        final BedrockRuntimeClient client = mock(BedrockRuntimeClient.class);
        when(client.invokeModel(any(InvokeModelRequest.class))).thenThrow(new RuntimeException("throttled"));
        return new BedrockSentimentService(client, new ObjectMapper(), true);
    }

    @Test
    @DisplayName("Bedrock failures fall back to heuristics for text, video and final overall sentiment")
    void bedrockFailures_fallBack() {
        final BedrockSentimentService service = failing();

        assertThat(service.analyzeText("I feel awful and scared", CALL_ID).channel()).isEqualTo("TEXT");
        assertThat(service.analyzeVideoFrame("AAAA", "jpeg", CALL_ID)).isNotNull();
        final SentimentResult overall = service.analyzeFinalOverallSentiment(CALL_ID, Map.of(
                "VOICE", new SentimentResult(0.2, "DISTRESSED", "  shaky\\n voice  ", "VOICE", CALL_ID, 1L, false)));
        assertThat(overall.channel()).isEqualTo("COMBINED");
        assertThat(service.analyzeFinalOverallSentiment(CALL_ID, null)).isNotNull();
        assertThat(service.summaryEngine()).startsWith("aws_bedrock:");
        assertThatThrownBy(() -> service.completeJson("{}", null, 50)).isInstanceOf(RuntimeException.class);
    }

    @Test
    @DisplayName("completeJson without Bedrock is rejected and the local engine label is reported")
    void localMode() {
        final BedrockSentimentService service = new BedrockSentimentService(null, new ObjectMapper(), false);

        assertThat(service.summaryEngine()).startsWith("local:");
        assertThatThrownBy(() -> service.completeJson("{}", null, 50)).hasMessageContaining("not available");
    }

    @Test
    @DisplayName("a parsed Bedrock final verdict maps NEGATIVE/NEUTRAL/POSITIVE labels")
    void finalOverall_mapsLabels() {
        final String claude = "{\"content\":[{\"type\":\"text\",\"text\":\"{\\\"score\\\":0.9,\\\"label\\\":\\\"POSITIVE\\\",\\\"notes\\\":\\\"ok\\\"}\"}]}";
        final String nova = "{\"output\":{\"message\":{\"content\":[{\"text\":\"{\\\"score\\\":0.9,\\\"label\\\":\\\"POSITIVE\\\",\\\"notes\\\":\\\"ok\\\"}\"}]}}}";
        for (final String body : new String[] {claude, nova}) {
            final SentimentResult result = returning(body).analyzeFinalOverallSentiment(CALL_ID, Map.of());
            assertThat(result.channel()).isEqualTo("COMBINED");
        }
    }
}
