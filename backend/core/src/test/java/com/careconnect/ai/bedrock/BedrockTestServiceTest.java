package com.careconnect.ai.bedrock;

import static org.assertj.core.api.Assertions.assertThat;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.fasterxml.jackson.databind.ObjectMapper;

import software.amazon.awssdk.core.SdkBytes;
import software.amazon.awssdk.services.bedrockruntime.BedrockRuntimeClient;
import software.amazon.awssdk.services.bedrockruntime.model.InvokeModelRequest;
import software.amazon.awssdk.services.bedrockruntime.model.InvokeModelResponse;

class BedrockTestServiceTest {

    @Test
    @DisplayName("testPrompt uses configured Nova model payload and parses response")
    void testPrompt_novaPayloadAndResponse() {
        BedrockRuntimeClient mockClient = mock(BedrockRuntimeClient.class);
        BedrockTestService service = new BedrockTestService(
                mockClient,
                "amazon.nova-lite-v1:0",
                new ObjectMapper()
        );

        String aiResponseBody = "{\"output\":{\"message\":{\"content\":[{\"text\":\"Nova reply\"}]}}}";
        when(mockClient.invokeModel(any(InvokeModelRequest.class)))
                .thenReturn(InvokeModelResponse.builder().body(SdkBytes.fromUtf8String(aiResponseBody)).build());

        String output = service.testPrompt("hello");

        ArgumentCaptor<InvokeModelRequest> captor = ArgumentCaptor.forClass(InvokeModelRequest.class);
        verify(mockClient).invokeModel(captor.capture());
        InvokeModelRequest sent = captor.getValue();
        String payload = sent.body().asUtf8String();

        assertThat(output).isEqualTo("Nova reply");
        assertThat(sent.modelId()).isEqualTo("amazon.nova-lite-v1:0");
        assertThat(payload).contains("\"inferenceConfig\"");
        assertThat(payload).doesNotContain("\"anthropic_version\"");
    }

    @Test
    @DisplayName("testPrompt uses configured Claude model payload and parses response")
    void testPrompt_claudePayloadAndResponse() {
        BedrockRuntimeClient mockClient = mock(BedrockRuntimeClient.class);
        BedrockTestService service = new BedrockTestService(
                mockClient,
                "anthropic.claude-3-5-sonnet-20240620-v1:0",
            new ObjectMapper()
        );

        String aiResponseBody = "{\"content\":[{\"type\":\"text\",\"text\":\"Claude reply\"}]}";
        when(mockClient.invokeModel(any(InvokeModelRequest.class)))
                .thenReturn(InvokeModelResponse.builder().body(SdkBytes.fromUtf8String(aiResponseBody)).build());

        String output = service.testPrompt("hello");

        ArgumentCaptor<InvokeModelRequest> captor = ArgumentCaptor.forClass(InvokeModelRequest.class);
        verify(mockClient).invokeModel(captor.capture());
        InvokeModelRequest sent = captor.getValue();
        String payload = sent.body().asUtf8String();

        assertThat(output).isEqualTo("Claude reply");
        assertThat(sent.modelId()).isEqualTo("anthropic.claude-3-5-sonnet-20240620-v1:0");
        assertThat(payload).contains("\"anthropic_version\":\"bedrock-2023-05-31\"");
        assertThat(payload).contains("\"max_tokens\":200");
        assertThat(payload).doesNotContain("\"inferenceConfig\"");
    }
}
