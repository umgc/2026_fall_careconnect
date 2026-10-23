package com.careconnect.service;

import com.careconnect.ai.AIService;
import com.careconnect.dto.ChatConversationSummary;
import com.careconnect.dto.ChatMessageSummary;
import com.careconnect.dto.ChatRequest;
import com.careconnect.dto.ChatResponse;
import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.MediaType;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientResponseException;

import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;

/**
 * Service providing local LLM inference via Ollama.
 * Used for on-premise, HIPAA-safe, and offline-capable clinical AI chat.
 */
@Slf4j
@Service
@ConditionalOnProperty(name = "careconnect.ai.provider", havingValue = "ollama")
public class OllamaService implements AIService {

    private final String apiUrl;
    private final String defaultModel;
    private final double defaultTemperature;
    private final RestClient restClient;

    public OllamaService(
            @Value("${careconnect.ollama.api.url:http://localhost:11434}") String apiUrl,
            @Value("${careconnect.ollama.model:llama3.2:1b}") String defaultModel,
            @Value("${careconnect.ollama.temperature:0.3}") double defaultTemperature,
            @Value("${careconnect.ollama.timeout-seconds:60}") int timeoutSeconds
    ) {
        this.apiUrl = apiUrl.endsWith("/") ? apiUrl.substring(0, apiUrl.length() - 1) : apiUrl;
        this.defaultModel = defaultModel;
        this.defaultTemperature = defaultTemperature;

        SimpleClientHttpRequestFactory requestFactory = new SimpleClientHttpRequestFactory();
        requestFactory.setConnectTimeout(Duration.ofSeconds(10));
        requestFactory.setReadTimeout(Duration.ofSeconds(timeoutSeconds));

        this.restClient = RestClient.builder()
                .requestFactory(requestFactory)
                .baseUrl(this.apiUrl)
                .defaultHeader("Accept", MediaType.APPLICATION_JSON_VALUE)
                .defaultHeader("User-Agent", "CareConnect-Ollama/1.0")
                .build();

        log.info("OllamaService initialized with endpoint: {}, default model: {}", this.apiUrl, this.defaultModel);
    }

    @Override
    public ChatResponse processChat(ChatRequest request) {
        String modelToUse = StringUtils.hasText(request.getPreferredModel())
                ? request.getPreferredModel()
                : defaultModel;

        log.info("Ollama processing chat request. Model: {}, User: {}, Patient: {}",
                modelToUse, request.getUserId(), request.getPatientId());

        OllamaChatRequest ollamaRequest = buildChatRequest(
                "You are an empathetic, clinical AI assistant for CareConnect. Provide concise and accurate health assistance. Always advise patients to seek professional medical advice.",
                request.getMessage(),
                modelToUse
        );

        try {
            OllamaChatResponse ollamaResponse = sendChatRequest(ollamaRequest);

            String aiText = "";
            if (ollamaResponse != null && ollamaResponse.getMessage() != null) {
                aiText = ollamaResponse.getMessage().getContent();
            }

            ChatResponse response = new ChatResponse();
            response.setAiResponse(aiText);
            response.setSuccess(true);
            response.setAiProvider("ollama");
            response.setModelUsed(modelToUse);
            response.setConversationId(request.getConversationId());
            return response;

        } catch (Exception e) {
            log.error("Failed to get response from Ollama at {}: {}", apiUrl, e.getMessage(), e);
            ChatResponse errorResponse = new ChatResponse();
            errorResponse.setSuccess(false);
            errorResponse.setErrorCode("OLLAMA_CONNECTION_ERROR");
            errorResponse.setErrorMessage("Could not connect to local Ollama service: " + e.getMessage());
            errorResponse.setAiProvider("ollama");
            return errorResponse;
        }
    }

    public OllamaChatResponse sendChatRequest(OllamaChatRequest request) {
        try {
            log.info("Sending prompt to Ollama POST {}/api/chat with model={}", apiUrl, request.getModel());

            return restClient.post()
                    .uri("/api/chat")
                    .contentType(MediaType.APPLICATION_JSON)
                    .body(request)
                    .retrieve()
                    .body(OllamaChatResponse.class);

        } catch (RestClientResponseException e) {
            final int code = e.getStatusCode().value();
            final String body = e.getResponseBodyAsString(StandardCharsets.UTF_8);
            log.error("Ollama HTTP {}: {}", code, body);
            throw new RuntimeException("Ollama inference call failed with HTTP " + code + ": " + body, e);
        }
    }

    private OllamaChatRequest buildChatRequest(String systemPrompt, String userPrompt, String model) {
        List<Message> messages = new ArrayList<>();
        if (StringUtils.hasText(systemPrompt)) {
            messages.add(new Message("system", systemPrompt));
        }
        messages.add(new Message("user", userPrompt != null ? userPrompt : ""));

        return OllamaChatRequest.builder()
                .model(model)
                .messages(messages)
                .stream(false)
                .options(new OllamaOptions(defaultTemperature))
                .build();
    }

    // ===== DTOs =====

    @Data
    @Builder
    @NoArgsConstructor
    @AllArgsConstructor
    public static class OllamaChatRequest {
        private String model;
        private List<Message> messages;
        private Boolean stream;
        private OllamaOptions options;
    }

    @Data
    @NoArgsConstructor
    @AllArgsConstructor
    public static class Message {
        private String role;
        private String content;
    }

    @Data
    @NoArgsConstructor
    @AllArgsConstructor
    public static class OllamaOptions {
        private Double temperature;
    }

    @Data
    @NoArgsConstructor
    @JsonIgnoreProperties(ignoreUnknown = true)
    public static class OllamaChatResponse {
        private String model;
        @JsonProperty("created_at")
        private String createdAt;
        private Message message;
        private Boolean done;
        @JsonProperty("total_duration")
        private Long totalDuration;
        @JsonProperty("eval_count")
        private Integer evalCount;
    }

    // ===== Stubs for interface compliance =====

    @Override
    public List<ChatConversationSummary> getPatientConversations(Long patientId) {
        return List.of();
    }

    @Override
    public List<ChatMessageSummary> getConversationMessages(String conversationId) {
        return List.of();
    }

    @Override
    public List<ChatMessageSummary> getRecentMessagesForUser(Long userId, int limit) {
        return List.of();
    }

    @Override
    public void deactivateConversation(String conversationId) {
        // No-op for local provider
    }
}

