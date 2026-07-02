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

    private static final Logger LOG = LoggerFactory.getLogger(BedrockModelSupport.class);

    public static final Set<String> APPROVED_MODEL_IDS = Set.of(
            "amazon.nova-lite-v1:0",
            "amazon.nova-pro-v1:0",
            "anthropic.claude-3-haiku-20240307-v1:0",
            "anthropic.claude-3-5-sonnet-20240620-v1:0",
            "anthropic.claude-sonnet-4-20250514-v1:0",
            "anthropic.claude-sonnet-4-5-20250929-v1:0",
            "anthropic.claude-sonnet-4-6"
    );

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

    private static boolean isApprovedModelId(String modelId) {
        return APPROVED_MODEL_IDS.contains(modelId)
                || isApprovedClaudeInferenceProfileId(modelId)
                || isApprovedClaudeInferenceProfileArn(modelId);
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

    private static boolean isApprovedClaudeInferenceProfileId(String modelId) {
        return modelId != null
                && modelId.contains(CLAUDE_PROFILE_SEGMENT)
                && !modelId.startsWith("arn:");
    }

    private static boolean isApprovedClaudeInferenceProfileArn(String modelId) {
        return modelId != null
                && modelId.startsWith("arn:aws:bedrock:")
                && modelId.contains(":inference-profile/")
                && modelId.contains("anthropic.claude");
    }

    public static String buildInvokePayload(
            String modelId,
            String prompt,
            int maxTokens,
            double temperature,
            double topP,
            ObjectMapper objectMapper
    ) {
        try {
            if (isNovaModel(modelId)) {
                Map<String, Object> payload = Map.of(
                        "messages", List.of(
                                Map.of(
                                        "role", "user",
                                        "content", List.of(
                                                Map.of("text", prompt)
                                        )
                                )
                        ),
                        "inferenceConfig", Map.of(
                                "maxTokens", maxTokens,
                                "temperature", temperature,
                                "topP", topP
                        )
                );
                return objectMapper.writeValueAsString(payload);
            }

            if (isClaudeModel(modelId)) {
                Map<String, Object> payload = Map.of(
                        "anthropic_version", "bedrock-2023-05-31",
                        "max_tokens", maxTokens,
                        "temperature", temperature,
                        "messages", List.of(
                                Map.of(
                                        "role", "user",
                                        "content", List.of(
                                                Map.of(
                                                        "type", "text",
                                                        "text", prompt
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