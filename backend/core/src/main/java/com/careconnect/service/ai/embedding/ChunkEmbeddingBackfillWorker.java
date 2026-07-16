package com.careconnect.service.ai.embedding;

import com.careconnect.model.retrieval.RetrievalIndexChunk;
import com.careconnect.repository.retrieval.RetrievalIndexChunkRepository;
import lombok.RequiredArgsConstructor;
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
 */
@Service
@ConditionalOnProperty(
        name = "careconnect.embedding.backfill.enabled",
        havingValue = "true",
        matchIfMissing = true)
@RequiredArgsConstructor
@Slf4j
public class ChunkEmbeddingBackfillWorker {

    private final RetrievalIndexChunkRepository chunkRepository;
    private final ChunkEmbeddingService chunkEmbeddingService;

    @Value("${careconnect.embedding.enabled:true}")
    private boolean embeddingEnabled;

    @Value("${careconnect.embedding.backfill.batch-size:50}")
    private int batchSize;

    @Scheduled(fixedDelayString = "${careconnect.embedding.backfill.poll-interval-ms:60000}")
    public void pollAndBackfill() {
        if (!embeddingEnabled) {
            log.debug("Embedding backfill skipped — careconnect.embedding.enabled=false");
            return;
        }

        final List<RetrievalIndexChunk> batch = chunkRepository.findMissingEmbeddingsForBackfill(batchSize);
        if (batch.isEmpty()) {
            return;
        }

        final int written = chunkEmbeddingService.embedAndPersist(batch);
        final long stillMissing = chunkRepository.countMissingEmbedding();
        log.info(
                "Embedding backfill embedded {} of {} chunk(s); {} still missing",
                written,
                batch.size(),
                stillMissing);
    }
}
