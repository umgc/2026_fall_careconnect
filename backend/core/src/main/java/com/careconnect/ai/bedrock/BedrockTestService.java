package com.careconnect.ai.bedrock;

import java.nio.charset.StandardCharsets;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import com.fasterxml.jackson.databind.ObjectMapper;

import software.amazon.awssdk.auth.credentials.DefaultCredentialsProvider;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.bedrockruntime.BedrockRuntimeClient;
import software.amazon.awssdk.services.bedrockruntime.model.BedrockRuntimeException;
import software.amazon.awssdk.services.bedrockruntime.model.InvokeModelRequest;
import software.amazon.awssdk.services.bedrockruntime.model.InvokeModelResponse;

/**
 * Service responsible for invoking approved Bedrock chat models.
 */
@Service
public class BedrockTestService {

    private final BedrockRuntimeClient client;
    private final ObjectMapper objectMapper;
    private final String defaultModelId;

    /**
     * Initialize Bedrock client using default AWS credentials
     * and the us-east-1 region.
     */
    @Autowired
    public BedrockTestService(@Value("${careconnect.ai.model:amazon.nova-lite-v1:0}") String defaultModelId) {
        this(
                BedrockRuntimeClient.builder()
                        .region(Region.US_EAST_1)
                    .credentialsProvider(DefaultCredentialsProvider.builder().build())
                        .build(),
                defaultModelId,
                new ObjectMapper()
        );
    }

    BedrockTestService(BedrockRuntimeClient client, String defaultModelId, ObjectMapper objectMapper) {
        this.client = client;
        this.defaultModelId = defaultModelId;
        this.objectMapper = objectMapper;
    }

        /**
         * Sends a prompt to configured Bedrock model and extracts generated text.
         *
         * @param prompt User input
         * @return Generated model response
         */
    public String testPrompt(String prompt) {
        try {
            String modelId = BedrockModelSupport.resolveModelId(null, defaultModelId);
            String safePrompt = prompt == null ? "" : prompt;
            String body = BedrockModelSupport.buildInvokePayload(
                    modelId,
                    safePrompt,
                    200,
                    0.5,
                    0.9,
                    objectMapper
            );

            System.out.println("Calling Bedrock model: " + modelId + " with prompt: " + prompt);

            InvokeModelRequest request = InvokeModelRequest.builder()
                    .modelId(modelId)
                    .contentType("application/json")
                    .accept("application/json")
                    .body(
                            software.amazon.awssdk.core.SdkBytes
                                    .fromString(body, StandardCharsets.UTF_8)
                    )
                    .build();

            InvokeModelResponse response = client.invokeModel(request);
            String json = response.body().asUtf8String();

            System.out.println("Raw Bedrock JSON response: " + json);

            try {
                return BedrockModelSupport.parseTextResponse(modelId, json, objectMapper);
            } catch (RuntimeException e) {
                return "Failed to parse model response for model " + modelId + ": " + e.getMessage();
            }
        } catch (BedrockRuntimeException e) {
            String code = e.awsErrorDetails() != null ? e.awsErrorDetails().errorCode() : "UNKNOWN";
            String message = e.awsErrorDetails() != null ? e.awsErrorDetails().errorMessage() : e.getMessage();
            return "Bedrock invocation failed: " + code + " - " + message;
        } catch (RuntimeException e) {
            return "Bedrock test failed: " + e.getMessage();
        }
    }
}