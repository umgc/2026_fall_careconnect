package com.careconnect.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.test.util.ReflectionTestUtils;
import software.amazon.awssdk.core.SdkBytes;
import software.amazon.awssdk.services.bedrockruntime.BedrockRuntimeClient;
import software.amazon.awssdk.services.bedrockruntime.model.InvokeModelRequest;
import software.amazon.awssdk.services.bedrockruntime.model.InvokeModelResponse;

/**
 * Validates {@link BedrockSentimentService#completeJson}, the shared text-to-JSON call that
 * transcript condition screening relies on. The Bedrock runtime client is mocked so no AWS call
 * is made; replies are shaped like real Nova responses to exercise the existing extraction.
 */
class BedrockSentimentServiceCompleteJsonTest {

    private static final String NOVA_LITE = "amazon.nova-lite-v1:0";

    private BedrockSentimentService serviceReturning(final BedrockRuntimeClient client, final String body) {
        when(client.invokeModel(any(InvokeModelRequest.class))).thenReturn(
                InvokeModelResponse.builder().body(SdkBytes.fromUtf8String(body)).build());
        final BedrockSentimentService service = new BedrockSentimentService(client, new ObjectMapper(), true);
        ReflectionTestUtils.setField(service, "bedrockModelId", NOVA_LITE);
        return service;
    }

    /** Nova wraps JSON in prose and a code fence; only the object should come back, sent to the configured model. */
    @Test
    void completeJson_extractsFencedJsonFromNovaReply() throws Exception {
        // Arrange
        final BedrockRuntimeClient client = mock(BedrockRuntimeClient.class);
        final String reply = "{\"output\":{\"message\":{\"content\":[{\"text\":"
                + "\"Here you go:\\n```json\\n{\\\"conditions\\\":[]}\\n```\"}]}}}";
        final BedrockSentimentService service = serviceReturning(client, reply);

        // Act
        final String json = service.completeJson("prompt", null, 400);

        // Assert
        assertThat(json).isEqualTo("{\"conditions\":[]}");

        final ArgumentCaptor<InvokeModelRequest> request = ArgumentCaptor.forClass(InvokeModelRequest.class);
        verify(client).invokeModel(request.capture());
        assertThat(request.getValue().modelId()).isEqualTo(NOVA_LITE);
    }

    /** An approved per-feature override replaces the app-wide model. */
    @Test
    void completeJson_usesApprovedOverrideModel() throws Exception {
        final BedrockRuntimeClient client = mock(BedrockRuntimeClient.class);
        final BedrockSentimentService service = serviceReturning(client,
                "{\"output\":{\"message\":{\"content\":[{\"text\":\"{}\"}]}}}");

        service.completeJson("prompt", "amazon.nova-pro-v1:0", 400);

        final ArgumentCaptor<InvokeModelRequest> request = ArgumentCaptor.forClass(InvokeModelRequest.class);
        verify(client).invokeModel(request.capture());
        assertThat(request.getValue().modelId()).isEqualTo("amazon.nova-pro-v1:0");
    }

    /** A refusal or prose-only reply yields an empty string so the caller can retry. */
    @Test
    void completeJson_returnsEmptyWhenReplyHasNoJson() throws Exception {
        final BedrockRuntimeClient client = mock(BedrockRuntimeClient.class);
        final BedrockSentimentService service = serviceReturning(client,
                "{\"output\":{\"message\":{\"content\":[{\"text\":\"I cannot help with that.\"}]}}}");

        assertThat(service.completeJson("prompt", null, 400)).isEmpty();
    }

    /** With AWS disabled (local/test) the call is refused rather than silently faked. */
    @Test
    void completeJson_refusesWhenBedrockUnavailable() {
        final BedrockSentimentService service = new BedrockSentimentService(null, new ObjectMapper(), false);

        assertThat(service.canInvokeBedrock()).isFalse();
        assertThatThrownBy(() -> service.completeJson("prompt", null, 400))
                .isInstanceOf(IllegalStateException.class);
    }

    /** Without an anonymizer bean (unit fixtures) text passes through unchanged. */
    @Test
    void anonymizeForPrompt_passesThroughWithoutAnonymizer() {
        final BedrockSentimentService service = new BedrockSentimentService(null, new ObjectMapper(), false);

        assertThat(service.anonymizeForPrompt("plain text")).isEqualTo("plain text");
    }
}
