package com.careconnect.service.ai;

import com.careconnect.ai.bedrock.BedrockModelSupport;
import com.careconnect.model.User;
import com.careconnect.model.retrieval.RetrievalIndexChunk;
import com.careconnect.service.ai.retrieval.ForbiddenScopeException;
import com.careconnect.service.ai.retrieval.HybridRetrievalService;
import com.careconnect.service.ai.retrieval.RetrievalScope;
import com.careconnect.service.ai.retrieval.RetrievalScopeService;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.nio.charset.StandardCharsets;
import java.util.List;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import software.amazon.awssdk.auth.credentials.DefaultCredentialsProvider;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.bedrockruntime.BedrockRuntimeClient;
import software.amazon.awssdk.services.bedrockruntime.model.BedrockRuntimeException;
import software.amazon.awssdk.services.bedrockruntime.model.InvokeModelRequest;
import software.amazon.awssdk.services.bedrockruntime.model.InvokeModelResponse;
import com.careconnect.security.UnauthorizedException;

@Slf4j
@Service
public class AiAskOrchestrator {

    private static final int MAX_TOKENS = 1024;
    private static final double TEMPERATURE = 0.3;
    private static final double TOP_P = 0.9;

    private static final String SYSTEM_PROMPT = """
            You are a helpful medical assistant for CareConnect.
            Answer the patient's question using ONLY the medical records provided below.
            Be concise, factual, and empathetic.
            If the records do not contain enough information to answer the question, say so clearly.
            Never speculate or invent medical information.
            """;

    private final RetrievalScopeService retrievalScopeService;
    private final HybridRetrievalService hybridRetrievalService;
    private final BedrockRuntimeClient bedrockClient;
    private final ObjectMapper objectMapper;
    private final String defaultModelId;

    public AiAskOrchestrator(
            RetrievalScopeService retrievalScopeService,
            HybridRetrievalService hybridRetrievalService,
            ObjectMapper objectMapper,
            @Value("${careconnect.ai.model:amazon.nova-lite-v1:0}") String defaultModelId) {
        this.retrievalScopeService = retrievalScopeService;
        this.hybridRetrievalService = hybridRetrievalService;
        this.objectMapper = objectMapper;
        this.defaultModelId = defaultModelId;
        this.bedrockClient = BedrockRuntimeClient.builder()
                .region(Region.US_EAST_1)
                .credentialsProvider(DefaultCredentialsProvider.builder().build())
                .build();
    }

    public AiAskResult ask(User caller, Long patientId, String question)
        throws ForbiddenScopeException, UnauthorizedException {

        log.info("Ask AI request — caller={} patientId={} questionLength={}",
                caller.getId(), patientId, question.length());

        RetrievalScope scope = retrievalScopeService.resolveRetrievalScope(caller, patientId);
        List<RetrievalIndexChunk> chunks = hybridRetrievalService.retrieve(question, scope);
        log.info("Retrieved {} chunks for patientId={}", chunks.size(), patientId);

        if (chunks.isEmpty()) {
            return new AiAskResult(
                    "I could not find relevant information in your medical records to answer that question.",
                    0);
        }

        String userPrompt = buildUserPrompt(question, chunks);
        String answer = invokeBedrock(userPrompt);
        return new AiAskResult(answer, chunks.size());
    }

    private String buildUserPrompt(String question, List<RetrievalIndexChunk> chunks) {
        StringBuilder sb = new StringBuilder();
        sb.append("MEDICAL RECORDS:\n");
        for (int i = 0; i < chunks.size(); i++) {
            RetrievalIndexChunk chunk = chunks.get(i);
            sb.append("\n[Record ").append(i + 1).append("]");
            sb.append(" Type: ").append(chunk.getRecordType());
            sb.append(" | Source: ").append(chunk.getSourceRecordId());
            sb.append("\n").append(chunk.getChunkText()).append("\n");
        }
        sb.append("\nPATIENT QUESTION:\n").append(question);
        return sb.toString();
    }

    private String invokeBedrock(String userPrompt) {
        String modelId = BedrockModelSupport.resolveModelId(null, defaultModelId);
        String payload = BedrockModelSupport.buildChatPayload(
                modelId, SYSTEM_PROMPT, userPrompt,
                MAX_TOKENS, TEMPERATURE, TOP_P, objectMapper);
        try {
            InvokeModelRequest request = InvokeModelRequest.builder()
                    .modelId(modelId)
                    .contentType("application/json")
                    .accept("application/json")
                    .body(software.amazon.awssdk.core.SdkBytes
                            .fromString(payload, StandardCharsets.UTF_8))
                    .build();
            InvokeModelResponse response = bedrockClient.invokeModel(request);
            return BedrockModelSupport.parseTextResponse(
                    modelId, response.body().asUtf8String(), objectMapper);
        } catch (BedrockRuntimeException e) {
            String code = e.awsErrorDetails() != null
                    ? e.awsErrorDetails().errorCode() : "UNKNOWN";
            log.error("Bedrock invocation failed: {} — {}", code, e.getMessage());
            throw new RuntimeException("AI service temporarily unavailable. Please try again.", e);
        }
    }

    public record AiAskResult(String answer, int chunksUsed) {}
}