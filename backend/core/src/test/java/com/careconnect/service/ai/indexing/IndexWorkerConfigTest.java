package com.careconnect.service.ai.indexing;

import com.careconnect.repository.CallSummaryRepository;
import com.careconnect.repository.CallSessionRepository;
import com.careconnect.repository.CallTranscriptSegmentRepository;
import com.careconnect.repository.UspsMailpieceRepository;
import com.careconnect.repository.indexing.IndexingOutboxRepository;
import com.careconnect.repository.retrieval.RetrievalIndexChunkRepository;
import com.careconnect.service.CallTranscriptService;
import com.careconnect.service.ai.embedding.ChunkEmbeddingService;
import com.careconnect.service.ai.indexing.chunker.MailpieceChunker;
import com.careconnect.service.ai.indexing.chunker.SummaryChunker;
import com.careconnect.service.ai.indexing.chunker.TranscriptSegmentChunker;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.TransactionException;
import org.springframework.transaction.TransactionStatus;
import org.springframework.transaction.support.SimpleTransactionStatus;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;

/**
 * Verifies IndexWorker enablement matches the PR test-plan / application-test.properties contract.
 */
class IndexWorkerConfigTest {

    private final ApplicationContextRunner runner = new ApplicationContextRunner()
            .withBean(IndexingOutboxRepository.class, () -> mock(IndexingOutboxRepository.class))
            .withBean(CallSummaryRepository.class, () -> mock(CallSummaryRepository.class))
            .withBean(CallSessionRepository.class, () -> mock(CallSessionRepository.class))
            .withBean(CallTranscriptService.class, () -> mock(CallTranscriptService.class))
            .withBean(CallTranscriptSegmentRepository.class,
                    () -> mock(CallTranscriptSegmentRepository.class))
            .withBean(UspsMailpieceRepository.class, () -> mock(UspsMailpieceRepository.class))
            .withBean(RetrievalIndexChunkRepository.class,
                    () -> mock(RetrievalIndexChunkRepository.class))
            .withBean(ChunkEmbeddingService.class, () -> mock(ChunkEmbeddingService.class))
            .withBean(ObjectMapper.class, ObjectMapper::new)
            .withBean(SummaryChunker.class, () -> new SummaryChunker(new ObjectMapper()))
            .withBean(TranscriptSegmentChunker.class, TranscriptSegmentChunker::new)
            .withBean(MailpieceChunker.class, MailpieceChunker::new)
            .withBean(PlatformTransactionManager.class, ImmediateTransactionManager::new)
            .withUserConfiguration(
                    RetrievalIndexService.class,
                    IndexWorker.class);

    @Test
    @DisplayName("IndexWorker is not created when careconnect.indexing.worker.enabled=false (test profile)")
    void workerDisabledWhenPropertyFalse() {
        runner.withPropertyValues("careconnect.indexing.worker.enabled=false")
                .run(context -> {
                    assertThat(context).doesNotHaveBean(IndexWorker.class);
                    assertThat(context).hasSingleBean(RetrievalIndexService.class);
                });
    }

    @Test
    @DisplayName("IndexWorker is created when careconnect.indexing.worker.enabled=true")
    void workerEnabledWhenPropertyTrue() {
        runner.withPropertyValues(
                        "careconnect.indexing.worker.enabled=true",
                        "careconnect.indexing.outbox.batch-size=10",
                        "careconnect.indexing.outbox.max-attempts=5")
                .run(context -> assertThat(context).hasSingleBean(IndexWorker.class));
    }

    @Test
    @DisplayName("IndexWorker is created by default when property is omitted (matchIfMissing)")
    void workerEnabledByDefault() {
        runner.withPropertyValues(
                        "careconnect.indexing.outbox.batch-size=10",
                        "careconnect.indexing.outbox.max-attempts=5")
                .run(context -> assertThat(context).hasSingleBean(IndexWorker.class));
    }

    private static final class ImmediateTransactionManager implements PlatformTransactionManager {
        @Override
        public TransactionStatus getTransaction(final TransactionDefinition definition)
                throws TransactionException {
            return new SimpleTransactionStatus();
        }

        @Override
        public void commit(final TransactionStatus status) throws TransactionException {
            // no-op
        }

        @Override
        public void rollback(final TransactionStatus status) throws TransactionException {
            // no-op
        }
    }
}
