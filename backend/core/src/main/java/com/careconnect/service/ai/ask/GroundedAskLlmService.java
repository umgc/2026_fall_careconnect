package com.careconnect.service.ai.ask;

import com.careconnect.ai.bedrock.BedrockModelSupport;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import software.amazon.awssdk.core.SdkBytes;
import software.amazon.awssdk.services.bedrockruntime.BedrockRuntimeClient;
import software.amazon.awssdk.services.bedrockruntime.model.BedrockRuntimeException;
import software.amazon.awssdk.services.bedrockruntime.model.InvokeModelRequest;
import software.amazon.awssdk.services.bedrockruntime.model.InvokeModelResponse;

import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

/**
 * Grounded Ask AI Bedrock completion — structured {@code {answerText, citationRefs[]}} only.
 *
 * <p>Does not reuse {@code BedrockAIChatService} (raw chat). Failures surface as empty
 * {@link Optional} so the gateway can return HTTP 503 instead of an ungrounded answer.
 */
@Service
public class GroundedAskLlmService {

    private static final Logger log = LoggerFactory.getLogger(GroundedAskLlmService.class);

    private final BedrockRuntimeClient bedrockRuntimeClient;
    private final ObjectMapper objectMapper;
    private final String defaultModelId;
    private final boolean awsEnabled;
    private final int maxTokens;
    private final double temperature;
    private final double topP;

    @Autowired
    public GroundedAskLlmService(
            @Autowired(required = false) final BedrockRuntimeClient bedrockRuntimeClient,
            final ObjectMapper objectMapper,
            @Value("${careconnect.ai.model:amazon.nova-lite-v1:0}") final String defaultModelId,
            @Value("${careconnect.aws.enabled:true}") final boolean awsEnabled,
            @Value("${careconnect.ai.ask.max-tokens:1024}") final int maxTokens,
            @Value("${careconnect.ai.ask.temperature:0.2}") final double temperature,
            @Value("${careconnect.ai.ask.top-p:0.9}") final double topP) {
        this.bedrockRuntimeClient = bedrockRuntimeClient;
        this.objectMapper = objectMapper;
        this.defaultModelId = defaultModelId;
        this.awsEnabled = awsEnabled;
        this.maxTokens = Math.max(256, maxTokens);
        this.temperature = temperature;
        this.topP = topP;
    }

    GroundedAskLlmService(
            final BedrockRuntimeClient bedrockRuntimeClient,
            final ObjectMapper objectMapper,
            final String defaultModelId,
            final boolean awsEnabled) {
        this(bedrockRuntimeClient, objectMapper, defaultModelId, awsEnabled, 1024, 0.2d, 0.9d);
    }

    /**
     * Invokes Bedrock with grounded system/user prompts and parses structured JSON.
     *
     * @return empty when AWS/Bedrock is unavailable or the response cannot be parsed
     */
    public Optional<GroundedLlmResult> generate(final String systemPrompt, final String userPrompt) {
        if (!isAvailable()) {
            log.warn("GroundedAskLlmService unavailable (AWS disabled or Bedrock client missing)");
            return Optional.empty();
        }
        try {
            final String modelId = BedrockModelSupport.resolveModelId(null, defaultModelId);
            final String payload = BedrockModelSupport.buildChatPayload(
                    modelId,
                    systemPrompt,
                    userPrompt,
                    maxTokens,
                    temperature,
                    topP,
                    objectMapper);

            final InvokeModelRequest request = InvokeModelRequest.builder()
                    .modelId(modelId)
                    .contentType("application/json")
                    .accept("application/json")
                    .body(SdkBytes.fromUtf8String(payload))
                    .build();

            final InvokeModelResponse response = bedrockRuntimeClient.invokeModel(request);
            final String raw = response.body().asUtf8String();
            final String text = BedrockModelSupport.parseTextResponse(modelId, raw, objectMapper);
            return parseStructured(text, modelId);
        } catch (final BedrockRuntimeException ex) {
            final String code = ex.awsErrorDetails() != null
                    ? ex.awsErrorDetails().errorCode() : "UNKNOWN";
            log.warn("Grounded Ask AI Bedrock invoke failed: {} - {}", code, ex.getMessage());
            return Optional.empty();
        } catch (final RuntimeException ex) {
            log.warn("Grounded Ask AI inference failed: {}", ex.getMessage());
            return Optional.empty();
        }
    }

    public String resolvedModelId() {
        try {
            return BedrockModelSupport.resolveModelId(null, defaultModelId);
        } catch (final RuntimeException ex) {
            return defaultModelId;
        }
    }

    public boolean isAvailable() {
        return awsEnabled && bedrockRuntimeClient != null;
    }

    private Optional<GroundedLlmResult> parseStructured(final String text, final String modelId) {
        if (text == null || text.isBlank()) {
            return Optional.empty();
        }
        try {
            final String json = unwrapJson(text.trim());
            final JsonNode root = objectMapper.readTree(json);
            final String answerText = textOrEmpty(root, "answerText");
            if (answerText.isBlank()) {
                return Optional.empty();
            }
            final List<String> refs = new ArrayList<>();
            final JsonNode refsNode = root.get("citationRefs");
            if (refsNode != null && refsNode.isArray()) {
                for (final JsonNode n : refsNode) {
                    if (n != null && n.isTextual() && !n.asText().isBlank()) {
                        refs.add(n.asText().trim());
                    }
                }
            }
            return Optional.of(new GroundedLlmResult(answerText.trim(), List.copyOf(refs), modelId));
        } catch (final Exception ex) {
            log.warn("Unable to parse grounded Ask AI JSON: {}", ex.getMessage());
            return Optional.empty();
        }
    }

    private static String unwrapJson(final String text) {
        String candidate = text;
        if (candidate.startsWith("```")) {
            final int firstNl = candidate.indexOf('\n');
            final int lastFence = candidate.lastIndexOf("```");
            if (firstNl > 0 && lastFence > firstNl) {
                candidate = candidate.substring(firstNl + 1, lastFence).trim();
            }
        }
        final int start = candidate.indexOf('{');
        final int end = candidate.lastIndexOf('}');
        if (start >= 0 && end > start) {
            return candidate.substring(start, end + 1);
        }
        return candidate;
    }

    private static String textOrEmpty(final JsonNode root, final String field) {
        final JsonNode node = root.get(field);
        if (node == null || node.isNull()) {
            return "";
        }
        return node.asText("");
    }

    public record GroundedLlmResult(String answerText, List<String> citationRefs, String modelId) {
    }
}
