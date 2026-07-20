package com.careconnect.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import software.amazon.awssdk.core.SdkBytes;
import software.amazon.awssdk.services.bedrockruntime.BedrockRuntimeClient;
import software.amazon.awssdk.services.bedrockruntime.model.InvokeModelRequest;
import software.amazon.awssdk.services.bedrockruntime.model.InvokeModelResponse;

class BedrockStructuredAnalysisServiceTest {

    @Test
    @DisplayName("complete sends Claude system+user payload and parses response")
    void complete_claudePayloadAndResponse() {
        BedrockRuntimeClient mockClient = mock(BedrockRuntimeClient.class);
        BedrockStructuredAnalysisService service = new BedrockStructuredAnalysisService(
                mockClient,
                new ObjectMapper(),
                "anthropic.claude-3-5-sonnet-20240620-v1:0"
        );

        String aiResponseBody = "{\"content\":[{\"type\":\"text\",\"text\":\"{\\\"allergen\\\":\\\"Penicillin\\\"}\"}]}";
        when(mockClient.invokeModel(any(InvokeModelRequest.class)))
                .thenReturn(InvokeModelResponse.builder().body(SdkBytes.fromUtf8String(aiResponseBody)).build());

        String output = service.complete("system prompt", "user prompt");

        ArgumentCaptor<InvokeModelRequest> captor = ArgumentCaptor.forClass(InvokeModelRequest.class);
        verify(mockClient).invokeModel(captor.capture());
        String payload = captor.getValue().body().asUtf8String();

        assertThat(output).contains("Penicillin");
        assertThat(payload).contains("\"system\":\"system prompt\"");
        assertThat(payload).contains("user prompt");
    }

    @Test
    @DisplayName("complete returns empty string when AWS disabled")
    void complete_awsDisabled_returnsEmpty() {
        BedrockStructuredAnalysisService service = new BedrockStructuredAnalysisService(
                mock(BedrockRuntimeClient.class),
                new ObjectMapper(),
                "anthropic.claude-3-5-sonnet-20240620-v1:0",
                false
        );

        assertThat(service.complete("system", "user")).isEmpty();
    }
}
