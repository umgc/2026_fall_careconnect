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
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

/**
 * Grounded Ask AI Bedrock completion — structured claim-level citations only.
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
        this.maxTokens = Math.min(4096, Math.max(256, maxTokens));
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
     * @return empty when AWS/Bedrock is unavailable
     * @throws GroundedOutputValidationException when Bedrock responds with invalid output
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
            final String text;
            try {
                final String raw = response.body().asUtf8String();
                text = BedrockModelSupport.parseTextResponse(modelId, raw, objectMapper);
            } catch (final RuntimeException ex) {
                throw new GroundedOutputValidationException(
                        "Bedrock response payload was malformed", ex);
            }
            return parseStructured(text, modelId);
        } catch (final BedrockRuntimeException ex) {
            final String code = ex.awsErrorDetails() != null
                    ? ex.awsErrorDetails().errorCode() : "UNKNOWN";
            log.warn("Grounded Ask AI Bedrock invoke failed code={}", code);
            if (log.isDebugEnabled()) {
                log.debug("Grounded Ask AI Bedrock diagnostic", ex);
            }
            return Optional.empty();
        } catch (final GroundedOutputValidationException ex) {
            throw ex;
        } catch (final RuntimeException ex) {
            log.warn("Grounded Ask AI inference failed");
            if (log.isDebugEnabled()) {
                log.debug("Grounded Ask AI inference diagnostic", ex);
            }
            return Optional.empty();
        }
    }

    public boolean isAvailable() {
        return awsEnabled && bedrockRuntimeClient != null;
    }

    private Optional<GroundedLlmResult> parseStructured(final String text, final String modelId) {
        if (text == null || text.isBlank()) {
            throw new GroundedOutputValidationException(
                    "Grounded model response was empty");
        }
        try {
            final String json = unwrapJson(text.trim());
            final JsonNode root = objectMapper.readTree(json);
            final JsonNode claimsNode = root.get("claims");
            if (claimsNode == null || !claimsNode.isArray() || claimsNode.isEmpty()) {
                throw new GroundedOutputValidationException(
                        "Grounded model response did not contain claims");
            }
            final List<GroundedClaim> claims = new ArrayList<>();
            final List<String> refs = new ArrayList<>();
            for (final JsonNode claimNode : claimsNode) {
                final String claimText =
                        AskAiTextPolicy.normalize(textOrEmpty(claimNode, "text")).trim();
                final JsonNode citationsNode = claimNode.get("citations");
                final List<String> claimRefs = new ArrayList<>();
                final Map<String, String> evidenceByRef = new LinkedHashMap<>();
                if (citationsNode != null && citationsNode.isArray()) {
                    for (final JsonNode citationNode : citationsNode) {
                        final String ref =
                                AskAiTextPolicy.normalize(textOrEmpty(citationNode, "ref")).trim();
                        final String evidence =
                                AskAiTextPolicy.normalize(
                                        textOrEmpty(citationNode, "evidence")).trim();
                        if (!ref.isBlank() && !evidence.isBlank()) {
                            claimRefs.add(ref);
                            evidenceByRef.put(ref, evidence);
                        }
                    }
                }
                if (claimText.isBlank() || claimRefs.isEmpty()) {
                    throw new GroundedOutputValidationException(
                            "Each grounded claim requires text and extractive evidence");
                }
                claims.add(new GroundedClaim(
                        claimText,
                        List.copyOf(claimRefs),
                        Map.copyOf(evidenceByRef)));
                refs.addAll(claimRefs);
            }
            final String answerText = claims.stream()
                    .map(GroundedClaim::text)
                    .reduce((left, right) -> left + " " + right)
                    .orElse("");
            return Optional.of(new GroundedLlmResult(
                    answerText, List.copyOf(refs), List.copyOf(claims), modelId));
        } catch (final GroundedOutputValidationException ex) {
            throw ex;
        } catch (final Exception ex) {
            log.warn("Unable to parse grounded Ask AI JSON");
            if (log.isDebugEnabled()) {
                log.debug("Grounded Ask AI parse diagnostic", ex);
            }
            throw new GroundedOutputValidationException(
                    "Grounded model response was malformed", ex);
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

    public record GroundedClaim(
            String text,
            List<String> citationRefs,
            Map<String, String> evidenceByRef) {

        public GroundedClaim(
                final String text,
                final List<String> citationRefs) {
            this(text, citationRefs, Map.of());
        }

        public GroundedClaim {
            citationRefs = citationRefs == null ? List.of() : List.copyOf(citationRefs);
            evidenceByRef = evidenceByRef == null ? Map.of() : Map.copyOf(evidenceByRef);
        }
    }

    public record GroundedLlmResult(
            String answerText,
            List<String> citationRefs,
            List<GroundedClaim> claims,
            String modelId) {

        public GroundedLlmResult(
                final String answerText,
                final List<String> citationRefs,
                final String modelId) {
            this(
                    answerText,
                    citationRefs,
                    List.of(new GroundedClaim(answerText, citationRefs)),
                    modelId);
        }

        public GroundedLlmResult {
            citationRefs = citationRefs == null ? List.of() : List.copyOf(citationRefs);
            claims = claims == null ? List.of() : List.copyOf(claims);
        }
    }
}
