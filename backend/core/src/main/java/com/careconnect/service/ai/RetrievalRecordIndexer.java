package com.careconnect.service.ai;

import com.careconnect.config.AskAiAsyncConfig;
import com.careconnect.model.retrieval.RetrievalIndexChunk;
import com.careconnect.service.ai.RetrievalRecordChangeListener.RetrievalRecordChanged;
import com.careconnect.service.ai.embedding.ChunkEmbeddingService;

import java.util.List;
import java.util.Optional;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Component;
import org.springframework.transaction.event.TransactionalEventListener;

/**
 * Rebuilds a medication or task's Ask AI chunk once the write that changed it
 * has committed.
 *
 * <p>Runs on {@link AskAiAsyncConfig#RETRIEVAL_INDEX_EXECUTOR} so the save request
 * does not wait for indexing and Titan embedding; a daily recurring task fans out to
 * dozens of records in one request.
 *
 * <p>Failures are logged and swallowed: the user's save already succeeded, and
 * a missed chunk can be recovered with {@code POST /v1/api/ai/index/{patientId}}.
 * This method deliberately has no {@code @Transactional}: the indexing methods
 * open their own transaction, so a failure rolls back only the index write, and
 * embedding then starts a fresh transaction rather than joining a committed one.
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class RetrievalRecordIndexer {

    private final RetrievalIndexingService retrievalIndexingService;
    private final ChunkEmbeddingService chunkEmbeddingService;

    // fallbackExecution covers a write made outside any transaction, where
    // there is no commit to wait for.
    @Async(AskAiAsyncConfig.RETRIEVAL_INDEX_EXECUTOR)
    @TransactionalEventListener(fallbackExecution = true)
    public void onRecordChanged(final RetrievalRecordChanged event) {
        try {
            final Optional<RetrievalIndexChunk> chunk = switch (event.recordType()) {
                case MEDICATION -> retrievalIndexingService.reindexMedication(event.recordId(), event.patientId());
                case TASK -> retrievalIndexingService.reindexTask(event.recordId(), event.patientId());
                default -> {
                    log.warn("No per-record indexer for recordType={}", event.recordType());
                    yield Optional.empty();
                }
            };
            // Embedded here, after the chunk's own transaction has committed, so the
            // vector arm finds a new record now instead of after the backfill worker.
            // embedAndPersist logs and skips failures, leaving them for the backfill.
            chunk.ifPresent(saved -> chunkEmbeddingService.embedAndPersist(List.of(saved)));
        } catch (RuntimeException e) {
            log.warn("Ask AI re-index failed for {} id={} patientId={}: {}",
                    event.recordType(), event.recordId(), event.patientId(), e.getMessage());
        }
    }
}
