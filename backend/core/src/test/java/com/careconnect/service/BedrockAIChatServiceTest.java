package com.careconnect.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.careconnect.dto.ChatRequest;
import com.careconnect.dto.ChatResponse;
import com.fasterxml.jackson.databind.ObjectMapper;

import software.amazon.awssdk.core.SdkBytes;
import software.amazon.awssdk.services.bedrockruntime.BedrockRuntimeClient;
import software.amazon.awssdk.services.bedrockruntime.model.InvokeModelRequest;
import software.amazon.awssdk.services.bedrockruntime.model.InvokeModelResponse;

class BedrockAIChatServiceTest {

    @Test
    @DisplayName("processChat builds Nova payload and parses Nova response")
    void processChat_novaModel_buildsNovaPayloadAndParsesNovaResponse() {
        BedrockRuntimeClient mockClient = mock(BedrockRuntimeClient.class);
        BedrockAIChatService service = new BedrockAIChatService(mockClient, "amazon.nova-lite-v1:0", new ObjectMapper());

        String aiResponseBody = "{\"output\":{\"message\":{\"content\":[{\"text\":\"Hello from Nova\"}]}}}";
        SdkBytes responseBytes = SdkBytes.fromUtf8String(aiResponseBody);
        InvokeModelResponse invokeResponse = InvokeModelResponse.builder()
                .body(responseBytes)
                .build();
        when(mockClient.invokeModel(any(InvokeModelRequest.class))).thenReturn(invokeResponse);

        ChatRequest request = new ChatRequest();
        request.setMessage("Hello");

        ChatResponse response = service.processChat(request);

        ArgumentCaptor<InvokeModelRequest> captor = ArgumentCaptor.forClass(InvokeModelRequest.class);
        verify(mockClient).invokeModel(captor.capture());
        InvokeModelRequest sent = captor.getValue();
        String payload = sent.body().asUtf8String();

        assertThat(response).isNotNull();
        assertThat(response.getAiResponse()).isEqualTo("Hello from Nova");
        assertThat(response.getAiProvider()).isEqualTo("bedrock");
        assertThat(response.getModelUsed()).isEqualTo("amazon.nova-lite-v1:0");
        assertThat(response.getSuccess()).isTrue();
        assertThat(response.getTimestamp()).isNotNull();
        assertThat(sent.modelId()).isEqualTo("amazon.nova-lite-v1:0");
        assertThat(payload).contains("\"messages\"");
        assertThat(payload).contains("\"inferenceConfig\"");
        assertThat(payload).doesNotContain("\"anthropic_version\"");
    }

    @Test
    @DisplayName("processChat supports Claude payload and response parsing")
    void processChat_claudeModel_buildsClaudePayloadAndParsesClaudeResponse() {
        BedrockRuntimeClient mockClient = mock(BedrockRuntimeClient.class);
        BedrockAIChatService service = new BedrockAIChatService(mockClient, "amazon.nova-lite-v1:0", new ObjectMapper());

        String aiResponseBody = "{\"id\":\"msg_1\",\"content\":[{\"type\":\"text\",\"text\":\"Hello from Claude\"}]}";
        SdkBytes responseBytes = SdkBytes.fromUtf8String(aiResponseBody);
        InvokeModelResponse invokeResponse = InvokeModelResponse.builder()
                .body(responseBytes)
                .build();
        when(mockClient.invokeModel(any(InvokeModelRequest.class))).thenReturn(invokeResponse);

        ChatRequest request = new ChatRequest();
        request.setMessage("Hello Claude");
        request.setPreferredModel("anthropic.claude-3-5-sonnet-20240620-v1:0");

        ChatResponse response = service.processChat(request);

        ArgumentCaptor<InvokeModelRequest> captor = ArgumentCaptor.forClass(InvokeModelRequest.class);
        verify(mockClient).invokeModel(captor.capture());
        InvokeModelRequest sent = captor.getValue();
        String payload = sent.body().asUtf8String();

        assertThat(response).isNotNull();
        assertThat(response.getAiResponse()).isEqualTo("Hello from Claude");
        assertThat(response.getAiProvider()).isEqualTo("bedrock");
        assertThat(response.getModelUsed()).isEqualTo("anthropic.claude-3-5-sonnet-20240620-v1:0");
        assertThat(response.getSuccess()).isTrue();
        assertThat(sent.modelId()).isEqualTo("anthropic.claude-3-5-sonnet-20240620-v1:0");
        assertThat(payload).contains("\"anthropic_version\":\"bedrock-2023-05-31\"");
        assertThat(payload).contains("\"max_tokens\":500");
        assertThat(payload).contains("\"messages\"");
        assertThat(payload).doesNotContain("\"inferenceConfig\"");
    }

    @Test
    @DisplayName("processChat accepts Claude inference profile ID")
    void processChat_claudeInferenceProfileId_isAccepted() {
        BedrockRuntimeClient mockClient = mock(BedrockRuntimeClient.class);
        BedrockAIChatService service = new BedrockAIChatService(mockClient, "amazon.nova-lite-v1:0", new ObjectMapper());

        String aiResponseBody = "{\"content\":[{\"type\":\"text\",\"text\":\"Hello from Claude profile\"}]}";
        SdkBytes responseBytes = SdkBytes.fromUtf8String(aiResponseBody);
        InvokeModelResponse invokeResponse = InvokeModelResponse.builder()
                .body(responseBytes)
                .build();
        when(mockClient.invokeModel(any(InvokeModelRequest.class))).thenReturn(invokeResponse);

        String profileId = "us.anthropic.claude-sonnet-4-20250514-v1:0";

        ChatRequest request = new ChatRequest();
        request.setMessage("Hello Claude profile");
        request.setPreferredModel(profileId);

        ChatResponse response = service.processChat(request);

        ArgumentCaptor<InvokeModelRequest> captor = ArgumentCaptor.forClass(InvokeModelRequest.class);
        verify(mockClient).invokeModel(captor.capture());
        InvokeModelRequest sent = captor.getValue();
        String payload = sent.body().asUtf8String();

        assertThat(response).isNotNull();
        assertThat(response.getAiResponse()).isEqualTo("Hello from Claude profile");
        assertThat(response.getModelUsed()).isEqualTo(profileId);
        assertThat(sent.modelId()).isEqualTo(profileId);
        assertThat(payload).contains("\"anthropic_version\":\"bedrock-2023-05-31\"");
    }

    @Test
    @DisplayName("processChat maps Claude Sonnet 4 base model ID to inference profile ID")
    void processChat_claudeSonnet4BaseId_isNormalizedToProfileId() {
        BedrockRuntimeClient mockClient = mock(BedrockRuntimeClient.class);
        BedrockAIChatService service = new BedrockAIChatService(mockClient, "anthropic.claude-sonnet-4-20250514-v1:0", new ObjectMapper());

        String aiResponseBody = "{\"content\":[{\"type\":\"text\",\"text\":\"Hello from normalized Claude\"}]}";
        SdkBytes responseBytes = SdkBytes.fromUtf8String(aiResponseBody);
        InvokeModelResponse invokeResponse = InvokeModelResponse.builder()
                .body(responseBytes)
                .build();
        when(mockClient.invokeModel(any(InvokeModelRequest.class))).thenReturn(invokeResponse);

        ChatRequest request = new ChatRequest();
        request.setMessage("Hello normalized");

        ChatResponse response = service.processChat(request);

        ArgumentCaptor<InvokeModelRequest> captor = ArgumentCaptor.forClass(InvokeModelRequest.class);
        verify(mockClient).invokeModel(captor.capture());
        InvokeModelRequest sent = captor.getValue();

        assertThat(response).isNotNull();
        assertThat(response.getAiResponse()).isEqualTo("Hello from normalized Claude");
        assertThat(sent.modelId()).isEqualTo("us.anthropic.claude-sonnet-4-20250514-v1:0");
    }

    @Test
    void processChat_unapprovedModel_throwsIllegalArgumentException() {
        BedrockRuntimeClient mockClient = mock(BedrockRuntimeClient.class);
        BedrockAIChatService service = new BedrockAIChatService(mockClient, "amazon.nova-lite-v1:0", new ObjectMapper());

        ChatRequest request = new ChatRequest();
        request.setMessage("Hello");
        request.setPreferredModel("anthropic.claude-4-opus-v1:0");

        assertThatThrownBy(() -> service.processChat(request))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("not approved");
    }

    @Test
    void getPatientConversations_throwsUnsupportedOperationException() {
        BedrockRuntimeClient mockClient = mock(BedrockRuntimeClient.class);
        BedrockAIChatService service = new BedrockAIChatService(mockClient, "amazon.nova-lite-v1:0", new ObjectMapper());

        assertThatThrownBy(() -> service.getPatientConversations(1L))
                .isInstanceOf(UnsupportedOperationException.class);
    }

    @Test
    void getConversationMessages_throwsUnsupportedOperationException() {
        BedrockRuntimeClient mockClient = mock(BedrockRuntimeClient.class);
        BedrockAIChatService service = new BedrockAIChatService(mockClient, "amazon.nova-lite-v1:0", new ObjectMapper());

        assertThatThrownBy(() -> service.getConversationMessages("conv-123"))
                .isInstanceOf(UnsupportedOperationException.class);
    }

    @Test
    void getRecentMessagesForUser_throwsUnsupportedOperationException() {
        BedrockRuntimeClient mockClient = mock(BedrockRuntimeClient.class);
        BedrockAIChatService service = new BedrockAIChatService(mockClient, "amazon.nova-lite-v1:0", new ObjectMapper());

        assertThatThrownBy(() -> service.getRecentMessagesForUser(1L, 10))
                .isInstanceOf(UnsupportedOperationException.class);
    }

    @Test
    void deactivateConversation_throwsUnsupportedOperationException() {
        BedrockRuntimeClient mockClient = mock(BedrockRuntimeClient.class);
        BedrockAIChatService service = new BedrockAIChatService(mockClient, "amazon.nova-lite-v1:0", new ObjectMapper());

        assertThatThrownBy(() -> service.deactivateConversation("conv-123"))
                .isInstanceOf(UnsupportedOperationException.class);
    }
}
