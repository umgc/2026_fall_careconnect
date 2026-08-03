package com.careconnect.service;

import com.careconnect.ai.bedrock.BedrockModelSupport;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Service;
import software.amazon.awssdk.core.SdkBytes;
import software.amazon.awssdk.services.bedrockruntime.BedrockRuntimeClient;
import software.amazon.awssdk.services.bedrockruntime.model.BedrockRuntimeException;
import software.amazon.awssdk.services.bedrockruntime.model.InvokeModelRequest;
import software.amazon.awssdk.services.bedrockruntime.model.InvokeModelResponse;

/**
 * Invokes Bedrock (Claude/Nova) for structured JSON extraction used by symptom and allergy analysis.
 */
@Slf4j
@Service
@ConditionalOnProperty(name = "careconnect.ai.provider", havingValue = "bedrock")
public class BedrockStructuredAnalysisService {

    private static final int DEFAULT_MAX_TOKENS = 300;
    private static final double DEFAULT_TEMPERATURE = 0.2;
    private static final double DEFAULT_TOP_P = 0.9;

    private final BedrockRuntimeClient bedrockRuntimeClient;
    private final ObjectMapper objectMapper;
    private final String defaultModelId;
    private final boolean awsEnabled;

    @Autowired
    public BedrockStructuredAnalysisService(
            @Autowired(required = false) BedrockRuntimeClient bedrockRuntimeClient,
            ObjectMapper objectMapper,
            @Value("${careconnect.ai.model:amazon.nova-lite-v1:0}") String defaultModelId,
            @Value("${careconnect.aws.enabled:true}") boolean awsEnabled) {
        this.bedrockRuntimeClient = bedrockRuntimeClient;
        this.objectMapper = objectMapper;
        this.defaultModelId = defaultModelId;
        this.awsEnabled = awsEnabled;
    }

    BedrockStructuredAnalysisService(
            BedrockRuntimeClient bedrockRuntimeClient,
            ObjectMapper objectMapper,
            String defaultModelId) {
        this(bedrockRuntimeClient, objectMapper, defaultModelId, true);
    }

    /**
     * Sends system + user prompts to Bedrock and returns the model text response.
     * Returns an empty string when Bedrock is unavailable or the invocation fails.
     */
    public String complete(String systemPrompt, String userPrompt) {
        if (!isAvailable()) {
            log.warn("Bedrock structured analysis unavailable (AWS disabled or client missing)");
            return "";
        }

        try {
            String modelId = BedrockModelSupport.resolveModelId(null, defaultModelId);
            String payload = BedrockModelSupport.buildChatPayload(
                    modelId,
                    systemPrompt,
                    userPrompt,
                    DEFAULT_MAX_TOKENS,
                    DEFAULT_TEMPERATURE,
                    DEFAULT_TOP_P,
                    objectMapper
            );

            InvokeModelRequest request = InvokeModelRequest.builder()
                    .modelId(modelId)
                    .contentType("application/json")
                    .accept("application/json")
                    .body(SdkBytes.fromUtf8String(payload))
                    .build();

            InvokeModelResponse response = bedrockRuntimeClient.invokeModel(request);
            String raw = response.body().asUtf8String();
            return BedrockModelSupport.parseTextResponse(modelId, raw, objectMapper);
        } catch (BedrockRuntimeException e) {
            String code = e.awsErrorDetails() != null ? e.awsErrorDetails().errorCode() : "UNKNOWN";
            String message = e.awsErrorDetails() != null ? e.awsErrorDetails().errorMessage() : e.getMessage();
            log.warn("Bedrock structured analysis failed: {} - {}", code, message);
            return "";
        } catch (RuntimeException e) {
            log.warn("Bedrock structured analysis failed: {}", e.getMessage());
            return "";
        }
    }

    private boolean isAvailable() {
        return awsEnabled && bedrockRuntimeClient != null;
    }
}
