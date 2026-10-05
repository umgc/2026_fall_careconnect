package com.careconnect.ai.bedrock;

import java.util.List;
import java.util.Map;
import java.util.Set;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * Shared Bedrock model routing, payload creation, and response parsing logic.
 */
public final class BedrockModelSupport {

    public static final Set<String> APPROVED_MODEL_IDS = Set.of(
            "amazon.nova-lite-v1:0",
            "amazon.nova-pro-v1:0",
            "anthropic.claude-3-haiku-20240307-v1:0",
            "anthropic.claude-3-5-sonnet-20240620-v1:0",
            "anthropic.claude-sonnet-4-20250514-v1:0",
            "anthropic.claude-sonnet-4-5-20250929-v1:0"
    );
    public static final Set<String> APPROVED_INFERENCE_PROFILE_IDS = Set.of(
            "us.anthropic.claude-sonnet-4-20250514-v1:0",
            "us.anthropic.claude-sonnet-4-5-20250929-v1:0"
    );
    private static final Logger LOG = LoggerFactory.getLogger(BedrockModelSupport.class);
    private static final String NOVA_PREFIX = "amazon.nova";
    private static final String CLAUDE_PREFIX = "anthropic.claude";
    private static final String CLAUDE_PROFILE_SEGMENT = ".anthropic.claude";

    private static final Map<String, String> CLAUDE_MODEL_TO_PROFILE_ID = Map.of(
            "anthropic.claude-sonnet-4-20250514-v1:0", "us.anthropic.claude-sonnet-4-20250514-v1:0",
            "anthropic.claude-sonnet-4-5-20250929-v1:0", "us.anthropic.claude-sonnet-4-5-20250929-v1:0"
    );

    private BedrockModelSupport() {
    }

    public static String resolveModelId(String requestedModelId, String defaultModelId) {
        String normalizedDefaultModelId = normalizeKnownClaudeModelToProfile(defaultModelId);
        if (normalizedDefaultModelId == null || normalizedDefaultModelId.isBlank()) {
            throw new IllegalArgumentException("No Bedrock model ID configured");
        }

        String modelId = (requestedModelId == null || requestedModelId.isBlank())
                ? normalizedDefaultModelId
                : normalizeKnownClaudeModelToProfile(requestedModelId.trim());

        if (modelId == null || modelId.isBlank()) {
            throw new IllegalArgumentException("No Bedrock model ID configured");
        }

        if (!isApprovedModelId(modelId)) {
            LOG.warn("Requested Bedrock model '{}' is not approved. Falling back to default model '{}'.",
                    modelId, normalizedDefaultModelId);
            modelId = normalizedDefaultModelId;
        }

        if (!isApprovedModelId(modelId)) {
            throw new IllegalArgumentException("Model ID is not approved: " + modelId);
        }

        return modelId;
    }

    public static boolean isApprovedModelId(String modelId) {
        return APPROVED_MODEL_IDS.contains(modelId)
                || APPROVED_INFERENCE_PROFILE_IDS.contains(modelId);
    }

    private static String normalizeKnownClaudeModelToProfile(String modelId) {
        if (modelId == null || modelId.isBlank()) {
            return modelId;
        }
        return CLAUDE_MODEL_TO_PROFILE_ID.getOrDefault(modelId, modelId);
    }

    public static boolean isNovaModel(String modelId) {
        return modelId != null && modelId.startsWith(NOVA_PREFIX);
    }

    public static boolean isClaudeModel(String modelId) {
        return modelId != null
                && (modelId.startsWith(CLAUDE_PREFIX)
                || modelId.contains(CLAUDE_PROFILE_SEGMENT)
                || modelId.contains("anthropic.claude"));
    }

    public static String buildInvokePayload(
            String modelId,
            String prompt,
            int maxTokens,
            double temperature,
            double topP,
            ObjectMapper objectMapper
    ) {
        return buildChatPayload(modelId, null, prompt, maxTokens, temperature, topP, objectMapper);
    }

    /**
     * Builds a Bedrock invoke payload with optional system instructions and a user message.
     * Claude and Nova models use native system fields so policy remains separate
     * from untrusted user/retrieval data in the final provider payload.
     */
    public static String buildChatPayload(
            String modelId,
            String systemPrompt,
            String userPrompt,
            int maxTokens,
            double temperature,
            double topP,
            ObjectMapper objectMapper
    ) {
        try {
            String safeUser = userPrompt == null ? "" : userPrompt;
            String safeSystem = systemPrompt == null ? "" : systemPrompt.trim();

            if (isNovaModel(modelId)) {
                Map<String, Object> payload = new java.util.LinkedHashMap<>();
                if (!safeSystem.isBlank()) {
                    payload.put("system", List.of(Map.of("text", safeSystem)));
                }
                payload.put("messages", List.of(
                        Map.of(
                                "role", "user",
                                "content", List.of(Map.of("text", safeUser)))));
                payload.put("inferenceConfig", Map.of(
                        "maxTokens", maxTokens,
                        "temperature", temperature,
                        "topP", topP));
                return objectMapper.writeValueAsString(payload);
            }

            if (isClaudeModel(modelId)) {
                Map<String, Object> payload = new java.util.LinkedHashMap<>();
                payload.put("anthropic_version", "bedrock-2023-05-31");
                payload.put("max_tokens", maxTokens);
                payload.put("temperature", temperature);
                if (!safeSystem.isBlank()) {
                    payload.put("system", safeSystem);
                }
                payload.put(
                        "messages",
                        List.of(
                                Map.of(
                                        "role", "user",
                                        "content", List.of(
                                                Map.of(
                                                        "type", "text",
                                                        "text", safeUser
                                                )
                                        )
                                )
                        )
                );
                return objectMapper.writeValueAsString(payload);
            }

            throw new IllegalArgumentException("Unsupported Bedrock model family: " + modelId);
        } catch (JsonProcessingException e) {
            throw new RuntimeException("Failed to build Bedrock request payload", e);
        }
    }

    public static String parseTextResponse(String modelId, String rawResponse, ObjectMapper objectMapper) {
        try {
            JsonNode root = objectMapper.readTree(rawResponse);

            if (isNovaModel(modelId)) {
                JsonNode content = root.path("output").path("message").path("content");
                if (content.isArray() && !content.isEmpty()) {
                    return content.get(0).path("text").asText("").trim();
                }
                throw new IllegalStateException("Nova response did not contain output.message.content[0].text");
            }

            if (isClaudeModel(modelId)) {
                JsonNode content = root.path("content");
                if (content.isArray() && !content.isEmpty()) {
                    return content.get(0).path("text").asText("").trim();
                }
                throw new IllegalStateException("Claude response did not contain content[0].text");
            }

            throw new IllegalArgumentException("Unsupported Bedrock model family: " + modelId);
        } catch (JsonProcessingException e) {
            throw new RuntimeException("Failed to parse Bedrock response", e);
        }
    }
}