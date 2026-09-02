package com.careconnect.service;

import com.careconnect.ai.AIService;
import com.careconnect.dto.ChatConversationSummary;
import com.careconnect.dto.ChatMessageSummary;
import com.careconnect.dto.ChatRequest;
import com.careconnect.dto.ChatResponse;
import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import lombok.Data;
import lombok.NoArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientResponseException;

import java.nio.charset.StandardCharsets;
import java.util.List;

@Slf4j
@Service
@ConditionalOnProperty(name = "careconnect.ai.provider", havingValue = "deepseek")
public class DeepSeekService implements AIService {

    private final RestClient restClient;
    @Value("${deepseek.api.key:}")
    private String apiKey;
    @Value("${deepseek.api.url:https://api.deepseek.com/v1}")
    private String apiUrl;

    public DeepSeekService(
            @Value("${deepseek.api.key:}") String apiKey,
            @Value("${deepseek.api.url:https://api.deepseek.com/v1}") String apiUrl
    ) {
        this.apiKey = apiKey;
        this.apiUrl = apiUrl;
        this.restClient = RestClient.builder()
                .baseUrl(apiUrl)
                .defaultHeader("Authorization", "Bearer " + (apiKey == null ? "" : apiKey))
                .defaultHeader("Accept", MediaType.APPLICATION_JSON_VALUE)
                .defaultHeader("User-Agent", "CareConnect/1.0")
                .build();
    }

    @Override
    public ChatResponse processChat(ChatRequest request) {

        DeepSeekChatRequest dsRequest = buildChatRequest(
                "You are a helpful medical assistant.",
                request.getMessage()
        );

        DeepSeekResponse dsResponse = sendChatRequest(dsRequest);

        String aiText = dsResponse.getChoices()
                .get(0)
                .getMessage()
                .getContent();

        ChatResponse response = new ChatResponse();
        response.setAiResponse(aiText);
        response.setSuccess(true);

        return response;
    }

    public DeepSeekResponse sendChatRequest(DeepSeekChatRequest request) {
        if (apiKey == null || apiKey.trim().isEmpty()) {
            throw new IllegalStateException("DeepSeek API key is not configured");
        }

        try {
            log.info("DeepSeek: POST {}/chat/completions model={}", apiUrl, request.getModel());

            return restClient.post()
                    .uri("/chat/completions")
                    .contentType(MediaType.APPLICATION_JSON)
                    .body(request)
                    .retrieve()
                    .body(DeepSeekResponse.class);

        } catch (RestClientResponseException e) {
            final int code = e.getStatusCode().value();
            final String body = e.getResponseBodyAsString(StandardCharsets.UTF_8);
            log.error("DeepSeek HTTP {}: {}", code, body);
            throw new RuntimeException("DeepSeek call failed: " + code, e);
        } catch (Exception e) {
            log.error("DeepSeek call error", e);
            throw new RuntimeException("DeepSeek call error", e);
        }
    }

    public DeepSeekChatRequest buildChatRequest(String systemPrompt, String userPrompt) {
        DeepSeekChatRequest chat = new DeepSeekChatRequest();
        chat.setModel("deepseek-chat");
        chat.setTemperature(0.2);
        chat.setMaxTokens(256);
        chat.setStream(false);
        chat.setMessages(List.of(
                new Message("system", systemPrompt),
                new Message("user", userPrompt)
        ));
        return chat;
    }

    @Override
    public List<ChatConversationSummary> getPatientConversations(Long patientId) {
        throw new UnsupportedOperationException();
    }

    @Override
    public List<ChatMessageSummary> getConversationMessages(String conversationId) {
        throw new UnsupportedOperationException();
    }

    // ===== Stubbed methods =====

    @Override
    public List<ChatMessageSummary> getRecentMessagesForUser(Long userId, int limit) {
        throw new UnsupportedOperationException();
    }

    @Override
    public void deactivateConversation(String conversationId) {
        throw new UnsupportedOperationException();
    }

    @Data
    @NoArgsConstructor
    public static class DeepSeekChatRequest {
        private String model;
        private List<Message> messages;
        private Double temperature;
        private Integer maxTokens;
        private Boolean stream = false;
    }

    @Data
    @NoArgsConstructor
    public static class Message {
        private String role;
        private String content;

        public Message(String role, String content) {
            this.role = role;
            this.content = content;
        }
    }

    // ===== DTOs =====

    @Data
    @NoArgsConstructor
    @JsonIgnoreProperties(ignoreUnknown = true)
    public static class DeepSeekResponse {
        private String id;
        private String object;
        private Long created;
        private String model;
        private List<Choice> choices;
        private Usage usage;
    }

    @Data
    @NoArgsConstructor
    @JsonIgnoreProperties(ignoreUnknown = true)
    public static class Choice {
        private Integer index;
        private Message message;
        private String finishReason;
    }

    @Data
    @NoArgsConstructor
    @JsonIgnoreProperties(ignoreUnknown = true)
    public static class Usage {
        private Integer promptTokens;
        private Integer completionTokens;
        private Integer totalTokens;
    }

    public static class DeepSeekException extends RuntimeException {
        public DeepSeekException(String message, Throwable cause) {
            super(message, cause);
        }
    }
}