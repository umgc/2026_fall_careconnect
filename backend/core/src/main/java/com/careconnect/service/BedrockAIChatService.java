package com.careconnect.service;

import java.nio.charset.StandardCharsets;
import java.time.LocalDateTime;
import java.util.List;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Service;

import com.careconnect.ai.AIService;
import com.careconnect.ai.bedrock.BedrockModelSupport;
import com.careconnect.dto.ChatConversationSummary;
import com.careconnect.dto.ChatMessageSummary;
import com.careconnect.dto.ChatRequest;
import com.careconnect.dto.ChatResponse;
import com.fasterxml.jackson.databind.ObjectMapper;

import software.amazon.awssdk.core.SdkBytes;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.bedrockruntime.BedrockRuntimeClient;
import software.amazon.awssdk.services.bedrockruntime.model.InvokeModelRequest;
import software.amazon.awssdk.services.bedrockruntime.model.InvokeModelResponse;

@Service
@ConditionalOnProperty(name = "careconnect.ai.provider", havingValue = "bedrock")
public class BedrockAIChatService implements AIService {

    private static final Logger log = LoggerFactory.getLogger(BedrockAIChatService.class);

    private final BedrockRuntimeClient client;
        private final ObjectMapper objectMapper;
        private final String defaultModelId;

        @Autowired
        public BedrockAIChatService(@Value("${careconnect.ai.model:amazon.nova-lite-v1:0}") String defaultModelId) {
                this(
                                BedrockRuntimeClient.builder().region(Region.US_EAST_1).build(),
                                defaultModelId,
                                new ObjectMapper()
                );
        }

        BedrockAIChatService(BedrockRuntimeClient client, String defaultModelId, ObjectMapper objectMapper) {
                this.client = client;
                this.defaultModelId = defaultModelId;
                this.objectMapper = objectMapper;
    }

    @Override
    public ChatResponse processChat(ChatRequest request) {

        log.info("Using Bedrock AI provider");

                String modelId = BedrockModelSupport.resolveModelId(request.getPreferredModel(), defaultModelId);
                String safePrompt = request.getMessage() == null ? "" : request.getMessage();
                String payload = BedrockModelSupport.buildInvokePayload(
                                modelId,
                                safePrompt,
                                500,
                                0.5,
                                0.9,
                                objectMapper
                );

        InvokeModelRequest invokeRequest = InvokeModelRequest.builder()
                                .modelId(modelId)
                .contentType("application/json")
                .accept("application/json")
                .body(SdkBytes.fromString(payload, StandardCharsets.UTF_8))
                .build();

        InvokeModelResponse response = client.invokeModel(invokeRequest);

        String raw = response.body().asUtf8String();
                String aiText = BedrockModelSupport.parseTextResponse(modelId, raw, objectMapper);

        ChatResponse chatResponse = new ChatResponse();
        chatResponse.setAiResponse(aiText);
                chatResponse.setAiProvider("bedrock");
                chatResponse.setModelUsed(modelId);
        chatResponse.setSuccess(true);
        chatResponse.setTimestamp(LocalDateTime.now());

        return chatResponse;
    }

    // ===== Stubbed methods =====

    @Override
    public List<ChatConversationSummary> getPatientConversations(Long patientId) {
        throw new UnsupportedOperationException();
    }

    @Override
    public List<ChatMessageSummary> getConversationMessages(String conversationId) {
        throw new UnsupportedOperationException();
    }

    @Override
    public List<ChatMessageSummary> getRecentMessagesForUser(Long userId, int limit) {
        throw new UnsupportedOperationException();
    }

    @Override
    public void deactivateConversation(String conversationId) {
        throw new UnsupportedOperationException();
    }
}