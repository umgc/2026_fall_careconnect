package com.careconnect.service.ai.embedding;

import com.careconnect.model.retrieval.RetrievalIndexChunk;
import com.careconnect.repository.retrieval.RetrievalIndexChunkRepository;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

import java.util.List;

/**
 * Scheduled worker for {@code retrieval_index_chunk} rows with {@code embedding IS NULL}
 * (failed Bedrock calls, or data indexed before Task 4.3). Reuses
 * {@link ChunkEmbeddingService#embedAndPersist(List)} so hybrid search (Task 5.1) has vectors.
 *
 * <p>Multiple ECS tasks may embed the same row concurrently until {@code embedding} is set;
 * writes are idempotent (same vector for the same {@code chunk_text}). Duplicate Bedrock
 * calls are acceptable for MVP — see Task 4.4 runbook if claim-based batching is needed later.
 */
@Service
@ConditionalOnProperty(
        name = {
                "careconnect.embedding.backfill.enabled",
                "careconnect.embedding.enabled"
        },
        havingValue = "true",
        matchIfMissing = true)
@Slf4j
public class ChunkEmbeddingBackfillWorker {

    private final RetrievalIndexChunkRepository chunkRepository;
    private final ChunkEmbeddingService chunkEmbeddingService;
    private final int batchSize;

    public ChunkEmbeddingBackfillWorker(
            final RetrievalIndexChunkRepository chunkRepository,
            final ChunkEmbeddingService chunkEmbeddingService,
            @Value("${careconnect.embedding.backfill.batch-size:50}") final int batchSize) {
        this.chunkRepository = chunkRepository;
        this.chunkEmbeddingService = chunkEmbeddingService;
        this.batchSize = Math.max(1, batchSize);
    }

    @Scheduled(fixedDelayString = "${careconnect.embedding.backfill.poll-interval-ms:60000}")
    public void pollAndBackfill() {
        final List<RetrievalIndexChunk> batch =
                chunkRepository.findMissingEmbeddingsForBackfill(batchSize);
        if (batch.isEmpty()) {
            return;
        }

        final int written = chunkEmbeddingService.embedAndPersist(batch);
        final long stillMissing = chunkRepository.countMissingEmbeddingsForBackfill();
        log.info(
                "Embedding backfill embedded {} of {} chunk(s); {} embeddable chunk(s) still missing",
                written,
                batch.size(),
                stillMissing);
    }
}
