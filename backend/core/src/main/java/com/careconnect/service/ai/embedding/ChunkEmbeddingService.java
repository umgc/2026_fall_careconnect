package com.careconnect.service.ai.embedding;

import com.careconnect.model.retrieval.RetrievalIndexChunk;
import com.careconnect.model.retrieval.RetrievalIndexSchema;
import com.careconnect.repository.retrieval.RetrievalIndexChunkRepository;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import software.amazon.awssdk.core.SdkBytes;
import software.amazon.awssdk.services.bedrockruntime.BedrockRuntimeClient;
import software.amazon.awssdk.services.bedrockruntime.model.BedrockRuntimeException;
import software.amazon.awssdk.services.bedrockruntime.model.InvokeModelRequest;
import software.amazon.awssdk.services.bedrockruntime.model.InvokeModelResponse;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

/**
 * Task 4.3 — batch-embeds {@code retrieval_index_chunk.chunk_text} via Bedrock Titan
 * and writes {@code embedding} through native SQL.
 *
 * <p>Default model is {@code amazon.titan-embed-text-v1} (1536-d) to match
 * {@link RetrievalIndexSchema#EMBEDDING_DIMENSION}. Callers should invoke
 * {@link #embedAndPersist} <em>after</em> the ingest transaction commits.
 * Failures are logged and left as {@code NULL} so FTS indexing still succeeds;
 * Task 4.4 backfills gaps.
 */
@Service
public class ChunkEmbeddingService {

    private static final Logger log = LoggerFactory.getLogger(ChunkEmbeddingService.class);
    private static final int MAX_INVOKE_ATTEMPTS = 3;

    private final RetrievalIndexChunkRepository chunkRepository;
    private final ObjectMapper objectMapper;
    private final BedrockRuntimeClient bedrockRuntimeClient;

    private final boolean enabled;
    private final String modelId;
    private final int batchSize;
    private final int maxInputChars;

    public ChunkEmbeddingService(
            final RetrievalIndexChunkRepository chunkRepository,
            final ObjectMapper objectMapper,
            @Autowired(required = false) final BedrockRuntimeClient bedrockRuntimeClient,
            @Value("${careconnect.embedding.enabled:true}") final boolean enabled,
            @Value("${careconnect.embedding.model-id:amazon.titan-embed-text-v1}")
                    final String modelId,
            @Value("${careconnect.embedding.batch-size:25}") final int batchSize,
            @Value("${careconnect.embedding.max-input-chars:8000}") final int maxInputChars) {
        this.chunkRepository = chunkRepository;
        this.objectMapper = objectMapper;
        this.bedrockRuntimeClient = bedrockRuntimeClient;
        this.enabled = enabled;
        this.modelId = modelId == null || modelId.isBlank()
                ? "amazon.titan-embed-text-v1"
                : modelId.trim();
        rejectUnsupportedModel(this.modelId);
        this.batchSize = Math.max(1, batchSize);
        this.maxInputChars = Math.max(256, maxInputChars);
    }

    /**
     * Embeds each saved chunk and updates {@code embedding}. No-ops when disabled
     * or when {@link BedrockRuntimeClient} is unavailable (local/test without AWS).
     *
     * <p>Runs in its own transaction so {@code @Modifying} updates succeed when
     * invoked from an after-commit callback (no ambient ingest TX).
     *
     * @param chunks entities returned from {@code saveAll} (must have ids)
     * @return number of chunks successfully embedded
     */
    @Transactional
    public int embedAndPersist(final List<RetrievalIndexChunk> chunks) {
        if (!enabled) {
            log.debug("Chunk embedding skipped — careconnect.embedding.enabled=false");
            return 0;
        }
        if (bedrockRuntimeClient == null) {
            log.debug("Chunk embedding skipped — BedrockRuntimeClient not configured");
            return 0;
        }
        if (chunks == null || chunks.isEmpty()) {
            return 0;
        }

        int written = 0;
        final List<RetrievalIndexChunk> pending = new ArrayList<>(chunks.size());
        for (final RetrievalIndexChunk chunk : chunks) {
            if (chunk != null && chunk.getId() != null
                    && chunk.getChunkText() != null
                    && !chunk.getChunkText().isBlank()) {
                pending.add(chunk);
            }
        }

        for (int offset = 0; offset < pending.size(); offset += batchSize) {
            final int end = Math.min(offset + batchSize, pending.size());
            final List<RetrievalIndexChunk> batch = pending.subList(offset, end);
            for (final RetrievalIndexChunk chunk : batch) {
                try {
                    final float[] vector = invokeTitanEmbed(chunk.getChunkText());
                    chunkRepository.updateEmbedding(
                            chunk.getId(), EmbeddingVectorFormat.toPgVectorLiteral(vector));
                    written++;
                } catch (final Exception ex) {
                    log.warn(
                            "Failed to embed chunk id={} sourceRecordId={}: {}",
                            chunk.getId(),
                            chunk.getSourceRecordId(),
                            ex.getMessage());
                }
            }
        }

        if (written > 0) {
            log.info("Embedded {}/{} retrieval chunk(s) via {}", written, pending.size(), modelId);
        }
        return written;
    }

    float[] invokeTitanEmbed(final String chunkText) throws Exception {
        final String inputText = truncate(chunkText, maxInputChars);
        // Titan Embed Text v1 returns 1536-d vectors matching retrieval_index_chunk.embedding.
        final Map<String, Object> body = new LinkedHashMap<>();
        body.put("inputText", inputText);

        final String requestJson = objectMapper.writeValueAsString(body);
        final InvokeModelRequest request = InvokeModelRequest.builder()
                .modelId(modelId)
                .contentType("application/json")
                .accept("application/json")
                .body(SdkBytes.fromUtf8String(requestJson))
                .build();

        Exception last = null;
        for (int attempt = 1; attempt <= MAX_INVOKE_ATTEMPTS; attempt++) {
            try {
                final InvokeModelResponse response = bedrockRuntimeClient.invokeModel(request);
                return parseEmbedding(response.body().asUtf8String());
            } catch (final BedrockRuntimeException ex) {
                last = ex;
                if (!isRetryableThrottle(ex) || attempt == MAX_INVOKE_ATTEMPTS) {
                    throw ex;
                }
                log.warn(
                        "Bedrock embedding throttled (attempt {}/{}): {}",
                        attempt, MAX_INVOKE_ATTEMPTS, ex.getMessage());
                Thread.sleep(150L * attempt);
            }
        }
        throw last == null ? new IllegalStateException("Bedrock invoke failed") : last;
    }

    private float[] parseEmbedding(final String responseJson) throws Exception {
        final JsonNode root = objectMapper.readTree(responseJson);
        final JsonNode embeddingNode = root.get("embedding");
        if (embeddingNode == null || !embeddingNode.isArray() || embeddingNode.isEmpty()) {
            throw new IllegalStateException("Bedrock embedding response missing embedding array");
        }
        final float[] values = new float[embeddingNode.size()];
        for (int i = 0; i < embeddingNode.size(); i++) {
            values[i] = (float) embeddingNode.get(i).asDouble();
        }
        if (values.length != RetrievalIndexSchema.EMBEDDING_DIMENSION) {
            throw new IllegalStateException(
                    "Bedrock returned embedding length "
                            + values.length
                            + "; expected "
                            + RetrievalIndexSchema.EMBEDDING_DIMENSION
                            + " for model "
                            + modelId);
        }
        return values;
    }

    private static void rejectUnsupportedModel(final String modelId) {
        final String lower = modelId.toLowerCase(Locale.ROOT);
        if (lower.contains("titan-embed-text-v2")
                && RetrievalIndexSchema.EMBEDDING_DIMENSION > 1024) {
            throw new IllegalStateException(
                    "Titan Embed Text v2 maxes at 1024-d; schema requires "
                            + RetrievalIndexSchema.EMBEDDING_DIMENSION
                            + ". Use amazon.titan-embed-text-v1 or migrate the embedding column.");
        }
    }

    private static boolean isRetryableThrottle(final BedrockRuntimeException ex) {
        final String code = ex.awsErrorDetails() == null ? "" : ex.awsErrorDetails().errorCode();
        final String message = ex.getMessage() == null ? "" : ex.getMessage();
        return "ThrottlingException".equalsIgnoreCase(code)
                || message.toLowerCase(Locale.ROOT).contains("throttl");
    }

    private static String truncate(final String text, final int maxChars) {
        final String trimmed = text.trim();
        if (trimmed.length() <= maxChars) {
            return trimmed;
        }
        return trimmed.substring(0, maxChars);
    }
}
