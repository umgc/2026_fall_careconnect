package com.careconnect.service.ai.ask;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import software.amazon.awssdk.core.SdkBytes;
import software.amazon.awssdk.services.bedrockruntime.BedrockRuntimeClient;
import software.amazon.awssdk.services.bedrockruntime.model.InvokeModelRequest;
import software.amazon.awssdk.services.bedrockruntime.model.InvokeModelResponse;

import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class GroundedAskLlmServiceTest {

    @Test
    @DisplayName("generate parses structured JSON answer and citationRefs")
    void generate_parsesStructuredJson() throws Exception {
        final BedrockRuntimeClient client = mock(BedrockRuntimeClient.class);
        final GroundedAskLlmService service = new GroundedAskLlmService(
                client, new ObjectMapper(), "amazon.nova-lite-v1:0", true);

        final String body = """
                {"output":{"message":{"content":[{"text":"{\\"claims\\":[{\\"text\\":\\"Started metformin.\\",\\"citations\\":[{\\"ref\\":\\"C1\\",\\"evidence\\":\\"Started metformin\\"}]}]}"}]}}}
                """;
        when(client.invokeModel(any(InvokeModelRequest.class)))
                .thenReturn(InvokeModelResponse.builder()
                        .body(SdkBytes.fromUtf8String(body))
                        .build());

        final Optional<GroundedAskLlmService.GroundedLlmResult> result =
                service.generate("system", "user");

        assertThat(result).isPresent();
        assertThat(result.get().answerText()).contains("metformin");
        assertThat(result.get().citationRefs()).containsExactly("C1");

        final ArgumentCaptor<InvokeModelRequest> captor =
                ArgumentCaptor.forClass(InvokeModelRequest.class);
        verify(client).invokeModel(captor.capture());
        final com.fasterxml.jackson.databind.JsonNode payload =
                new ObjectMapper().readTree(captor.getValue().body().asUtf8String());
        assertThat(payload.path("system").get(0).path("text").asText()).isEqualTo("system");
        assertThat(payload.path("messages").get(0).path("content").get(0)
                .path("text").asText()).isEqualTo("user");
    }

    @Test
    @DisplayName("generate classifies disabled AWS as configuration failure")
    void generate_awsDisabled() {
        final GroundedAskLlmService service = new GroundedAskLlmService(
                mock(BedrockRuntimeClient.class),
                new ObjectMapper(),
                "amazon.nova-lite-v1:0",
                false);

        assertThatThrownBy(() -> service.generate("system", "user"))
                .isInstanceOfSatisfying(
                        GroundedProviderException.class,
                        exception -> assertThat(exception.getKind())
                                .isEqualTo(GroundedProviderException.Kind.CONFIGURATION));
    }

    @Test
    @DisplayName("generate rejects model output with uncited claims")
    void generate_uncitedClaim_throwsValidationFailure() {
        final BedrockRuntimeClient client = mock(BedrockRuntimeClient.class);
        final GroundedAskLlmService service = new GroundedAskLlmService(
                client, new ObjectMapper(), "amazon.nova-lite-v1:0", true);
        final String body = """
                {"output":{"message":{"content":[{"text":"{\\"claims\\":[{\\"text\\":\\"Unsupported claim\\",\\"citations\\":[]}]}"}]}}}
                """;
        when(client.invokeModel(any(InvokeModelRequest.class)))
                .thenReturn(InvokeModelResponse.builder()
                        .body(SdkBytes.fromUtf8String(body))
                        .build());

        assertThatThrownBy(() -> service.generate("system", "user"))
                .isInstanceOf(GroundedOutputValidationException.class);
    }

    @Test
    @DisplayName("generate rejects a malformed provider response")
    void generate_malformedProviderPayload_throwsValidationFailure() {
        final BedrockRuntimeClient client = mock(BedrockRuntimeClient.class);
        final GroundedAskLlmService service = new GroundedAskLlmService(
                client, new ObjectMapper(), "amazon.nova-lite-v1:0", true);
        when(client.invokeModel(any(InvokeModelRequest.class)))
                .thenReturn(InvokeModelResponse.builder()
                        .body(SdkBytes.fromUtf8String("not-json"))
                        .build());

        assertThatThrownBy(() -> service.generate("system", "user"))
                .isInstanceOf(GroundedOutputValidationException.class);
    }
}
