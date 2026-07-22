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
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class GroundedAskLlmServiceTest {

    @Test
    @DisplayName("generate parses structured JSON answer and citationRefs")
    void generate_parsesStructuredJson() {
        final BedrockRuntimeClient client = mock(BedrockRuntimeClient.class);
        final GroundedAskLlmService service = new GroundedAskLlmService(
                client, new ObjectMapper(), "amazon.nova-lite-v1:0", true);

        final String body = """
                {"output":{"message":{"content":[{"text":"{\\"answerText\\":\\"Started metformin.\\",\\"citationRefs\\":[\\"C1\\"]}"}]}}}
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
        assertThat(captor.getValue().body().asUtf8String()).contains("system");
    }

    @Test
    @DisplayName("generate returns empty when AWS disabled")
    void generate_awsDisabled() {
        final GroundedAskLlmService service = new GroundedAskLlmService(
                mock(BedrockRuntimeClient.class),
                new ObjectMapper(),
                "amazon.nova-lite-v1:0",
                false);

        assertThat(service.generate("system", "user")).isEmpty();
    }
}
