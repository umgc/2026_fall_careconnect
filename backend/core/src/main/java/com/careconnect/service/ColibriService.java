package com.careconnect.service;

import com.careconnect.ai.AIService;
import com.careconnect.dto.ChatConversationSummary;
import com.careconnect.dto.ChatMessageSummary;
import com.careconnect.dto.ChatRequest;
import com.careconnect.dto.ChatResponse;
import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.MediaType;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;
import org.springframework.web.client.RestClient;

import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.regex.Pattern;

/**
 * Service providing local MoE LLM inference via the Colibri engine.
 * Streams experts from NVMe storage with OpenAI-compatible HTTP interface.
 * Implements Tiered Hybrid Edge-Cloud AI Triage for clinical safety.
 */
@Slf4j
@Service
@ConditionalOnProperty(name = "careconnect.ai.provider", havingValue = "colibri")
public class ColibriService implements AIService {

    public static final String ESCALATE_TOKEN = "[ESCALATE_TO_CLINICAL_CLOUD]";

    private static final Pattern DOSAGE_PATTERN = Pattern.compile(
            "(?i).*(cut|split|break|halve|half|increase|decrease|double|stop|skip|adjust|change).*(dosage|dose|pill|pills|tablet|tablets|medication|medicine|capsule).*"
    );

    private static final Pattern HALF_PILL_PATTERN = Pattern.compile(
            "(?i).*(cut|split|halve|take|break).*(in half|half of).*"
    );

    private static final Pattern CLINICAL_SYMPTOMS_PATTERN = Pattern.compile(
            "(?i).*(chest pain|shortness of breath|diagnos(e|is)|symptom|severe rash|bleeding|emergency|drug interaction).*"
    );

    private static final Pattern DIRECTORY_PATTERN = Pattern.compile(
            "(?i).*(other|another|different|second|main|downtown)\\s+(office|clinic|branch|location|facility|building|campus).*"
    );

    private final String apiUrl;
    private final String defaultModel;
    private final double defaultTemperature;
    private final int maxTokens;
    private final RestClient restClient;
    private final ObjectMapper objectMapper;
    private final BedrockAIChatService cloudFallbackService;

    public ColibriService(
            @Value("${careconnect.colibri.api.url:http://127.0.0.1:8000/v1}") String apiUrl,
            @Value("${careconnect.colibri.model:olmoe-colibri}") String defaultModel,
            @Value("${careconnect.colibri.temperature:0.3}") double defaultTemperature,
            @Value("${careconnect.colibri.timeout-seconds:180}") int timeoutSeconds
    ) {
        this(apiUrl, defaultModel, defaultTemperature, timeoutSeconds, 128, new ObjectMapper(), (BedrockAIChatService) null);
    }

    public ColibriService(
            String apiUrl,
            String defaultModel,
            double defaultTemperature,
            int timeoutSeconds,
            int maxTokens,
            ObjectMapper objectMapper
    ) {
        this(apiUrl, defaultModel, defaultTemperature, timeoutSeconds, maxTokens, objectMapper, (BedrockAIChatService) null);
    }

    public ColibriService(
            String apiUrl,
            String defaultModel,
            double defaultTemperature,
            int timeoutSeconds,
            int maxTokens,
            ObjectMapper objectMapper,
            BedrockAIChatService cloudFallbackService
    ) {
        this.apiUrl = apiUrl != null && apiUrl.endsWith("/") ? apiUrl.substring(0, apiUrl.length() - 1) : (apiUrl != null ? apiUrl : "http://127.0.0.1:8000/v1");
        this.defaultModel = defaultModel;
        this.defaultTemperature = defaultTemperature;
        this.maxTokens = maxTokens > 0 ? maxTokens : 128;
        this.objectMapper = objectMapper != null ? objectMapper : new ObjectMapper();
        this.cloudFallbackService = cloudFallbackService;

        SimpleClientHttpRequestFactory requestFactory = new SimpleClientHttpRequestFactory();
        requestFactory.setConnectTimeout(Duration.ofSeconds(10));
        requestFactory.setReadTimeout(Duration.ofSeconds(timeoutSeconds));
        this.restClient = RestClient.builder()
                .requestFactory(requestFactory)
                .build();

        log.info("ColibriService initialized with endpoint: {}, default model: {}, maxTokens: {}, cloudFallback: {}",
                this.apiUrl, this.defaultModel, this.maxTokens, this.cloudFallbackService != null);
    }

    @Autowired
    public ColibriService(
            @Value("${careconnect.colibri.api.url:http://127.0.0.1:8000/v1}") String apiUrl,
            @Value("${careconnect.colibri.model:olmoe-colibri}") String defaultModel,
            @Value("${careconnect.colibri.temperature:0.3}") double defaultTemperature,
            @Value("${careconnect.colibri.timeout-seconds:180}") int timeoutSeconds,
            @Value("${careconnect.colibri.max-tokens:128}") int maxTokens,
            @Autowired(required = false) ObjectMapper objectMapper,
            ObjectProvider<BedrockAIChatService> bedrockServiceProvider
    ) {
        this(apiUrl, defaultModel, defaultTemperature, timeoutSeconds, maxTokens, objectMapper,
                bedrockServiceProvider != null ? bedrockServiceProvider.getIfAvailable() : null);
    }

    /**
     * Determines whether a patient query must escalate to Cloud AI (Claude/Bedrock)
     * due to clinical safety (dosage alterations, diagnosis) or multi-facility directory requests.
     */
    public boolean shouldEscalateToCloud(String message) {
        if (!StringUtils.hasText(message)) {
            return false;
        }
        return DOSAGE_PATTERN.matcher(message).matches()
                || HALF_PILL_PATTERN.matcher(message).matches()
                || CLINICAL_SYMPTOMS_PATTERN.matcher(message).matches()
                || DIRECTORY_PATTERN.matcher(message).matches();
    }

    private ChatResponse buildEscalationResponse(ChatRequest request) {
        ChatResponse response = new ChatResponse();
        response.setSuccess(true);
        response.setAiProvider("colibri-cloud-triage");
        response.setModelUsed("clinical-cloud-escalation");
        response.setConversationId(request != null ? request.getConversationId() : null);
        response.setAiResponse(
                ESCALATE_TOKEN + " This inquiry involves pharmacological dosage alterations, acute clinical evaluation, or external clinic facilities. " +
                "These require CareConnect Cloud Clinical Specialist reasoning or direct consultation with your healthcare provider. " +
                "Never alter your medication dosage (e.g. cutting pills in half) without explicit physician instructions."
        );
        return response;
    }

    @Override
    public ChatResponse processChat(ChatRequest request) {
        String userMsg = request != null && request.getMessage() != null ? request.getMessage() : "";

        // Check deterministic clinical triage guardrails
        if (shouldEscalateToCloud(userMsg)) {
            log.warn("Edge clinical triage triggered for query: '{}'. Routing to Cloud Clinical Tier.", userMsg);
            if (cloudFallbackService != null) {
                return cloudFallbackService.processChat(request);
            }
            return buildEscalationResponse(request);
        }

        String modelToUse = (request != null && StringUtils.hasText(request.getPreferredModel()))
                ? request.getPreferredModel()
                : defaultModel;

        log.info("Colibri processing local query. Model: {}, User: {}, Patient: {}",
                modelToUse, request != null ? request.getUserId() : null, request != null ? request.getPatientId() : null);

        String prompt = compactPromptForLocalMoE(userMsg);
        ColibriChatRequest colibriRequest = buildChatRequest(
                "You are CareConnect Edge Assistant. Provide concise and accurate health assistance based on patient data in 1 to 2 sentences. Always advise patients to consult their care team for clinical decisions.",
                prompt,
                modelToUse
        );

        try {
            ColibriChatResponse colibriResponse = sendChatRequest(colibriRequest);

            String aiText = "";
            if (colibriResponse != null && colibriResponse.getChoices() != null && !colibriResponse.getChoices().isEmpty()) {
                Choice firstChoice = colibriResponse.getChoices().get(0);
                if (firstChoice.getMessage() != null) {
                    aiText = firstChoice.getMessage().getContent();
                }
            }

            // If the local SLM emitted the escalation token, route to cloud
            if (aiText != null && aiText.contains(ESCALATE_TOKEN)) {
                log.info("Local SLM outputted {}. Escalating to Cloud Clinical Specialist.", ESCALATE_TOKEN);
                if (cloudFallbackService != null) {
                    return cloudFallbackService.processChat(request);
                }
                return buildEscalationResponse(request);
            }

            ChatResponse response = new ChatResponse();
            response.setAiResponse(aiText);
            response.setSuccess(true);
            response.setAiProvider("colibri");
            response.setModelUsed(modelToUse);
            response.setConversationId(request != null ? request.getConversationId() : null);
            return response;

        } catch (Exception e) {
            log.error("Failed to get response from Colibri at {}: {}", apiUrl, e.getMessage(), e);
            ChatResponse errorResponse = new ChatResponse();
            errorResponse.setSuccess(false);
            errorResponse.setErrorCode("COLIBRI_CONNECTION_ERROR");
            errorResponse.setErrorMessage("Could not connect to local Colibri service: " + e.getMessage());
            errorResponse.setAiProvider("colibri");
            return errorResponse;
        }
    }

    private ColibriChatResponse sendChatRequest(ColibriChatRequest request) throws Exception {
        byte[] bodyBytes = objectMapper.writeValueAsBytes(request);
        log.debug("Sending chat request to Colibri ({} bytes) at {}/chat/completions", bodyBytes.length, apiUrl);

        return restClient.post()
                .uri(apiUrl + "/chat/completions")
                .contentType(MediaType.APPLICATION_JSON)
                .contentLength(bodyBytes.length)
                .body(bodyBytes)
                .exchange((clientRequest, clientResponse) -> {
                    byte[] raw = clientResponse.getBody().readAllBytes();
                    if (!clientResponse.getStatusCode().is2xxSuccessful()) {
                        String err = new String(raw, StandardCharsets.UTF_8);
                        log.error("Colibri returned error status {}: {}", clientResponse.getStatusCode(), err);
                        throw new RuntimeException("Colibri error (" + clientResponse.getStatusCode() + "): " + err);
                    }
                    return objectMapper.readValue(raw, ColibriChatResponse.class);
                });
    }

    private ColibriChatRequest buildChatRequest(String systemPrompt, String userPrompt, String model) {
        List<Message> messages = new ArrayList<>();
        if (StringUtils.hasText(systemPrompt)) {
            messages.add(new Message("system", systemPrompt));
        }
        messages.add(new Message("user", userPrompt != null ? userPrompt : ""));

        return ColibriChatRequest.builder()
                .model(model)
                .messages(messages)
                .temperature(defaultTemperature)
                .maxTokens(maxTokens)
                .stream(false)
                .build();
    }

    private String compactPromptForLocalMoE(String message) {
        if (message == null || message.length() <= 800) {
            return message;
        }
        int userQIdx = message.indexOf("USER QUESTION:\n");
        if (userQIdx != -1) {
            String medicalContext = message.substring(0, userQIdx);
            String questionPart = message.substring(userQIdx);

            StringBuilder compact = new StringBuilder();
            String[] sections = medicalContext.split("\n\n");
            for (String sec : sections) {
                String trimmed = sec.trim();
                if (trimmed.startsWith("PATIENT INFORMATION:") ||
                    trimmed.startsWith("UPCOMING APPOINTMENTS") ||
                    trimmed.startsWith("CURRENT MEDICATIONS:") ||
                    trimmed.startsWith("RECENT CLINICAL NOTES:") ||
                    trimmed.startsWith("RECENT VITALS:")) {
                    String[] lines = trimmed.split("\n");
                    int maxLines = Math.min(lines.length, 3);
                    for (int i = 0; i < maxLines; i++) {
                        compact.append(lines[i]).append("\n");
                    }
                    compact.append("\n");
                }
            }
            return compact.toString().trim() + "\n\n" + questionPart;
        }
        return message.substring(0, Math.min(message.length(), 800));
    }

    // ===== OpenAI-Compatible DTOs for Colibri =====

    @Data
    @Builder
    @NoArgsConstructor
    @AllArgsConstructor
    public static class ColibriChatRequest {
        private String model;
        private List<Message> messages;
        private Double temperature;
        private Boolean stream;
        @JsonProperty("max_tokens")
        private Integer maxTokens;
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
    @JsonIgnoreProperties(ignoreUnknown = true)
    public static class ColibriChatResponse {
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
        @JsonProperty("finish_reason")
        private String finishReason;
    }

    @Data
    @NoArgsConstructor
    @JsonIgnoreProperties(ignoreUnknown = true)
    public static class Usage {
        @JsonProperty("prompt_tokens")
        private Integer promptTokens;
        @JsonProperty("completion_tokens")
        private Integer completionTokens;
        @JsonProperty("total_tokens")
        private Integer totalTokens;
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
