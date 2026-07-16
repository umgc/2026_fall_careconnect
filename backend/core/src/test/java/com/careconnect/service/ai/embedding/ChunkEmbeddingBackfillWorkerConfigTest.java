package com.careconnect.service.ai.embedding;

import com.careconnect.repository.retrieval.RetrievalIndexChunkRepository;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;

/**
 * Verifies ChunkEmbeddingBackfillWorker enablement matches application-test.properties contract.
 */
class ChunkEmbeddingBackfillWorkerConfigTest {

    private final ApplicationContextRunner runner = new ApplicationContextRunner()
            .withBean(RetrievalIndexChunkRepository.class,
                    () -> mock(RetrievalIndexChunkRepository.class))
            .withBean(ChunkEmbeddingService.class, () -> mock(ChunkEmbeddingService.class))
            .withUserConfiguration(ChunkEmbeddingBackfillWorker.class);

    @Test
    @DisplayName("backfill worker is not created when careconnect.embedding.backfill.enabled=false")
    void workerDisabledWhenBackfillPropertyFalse() {
        runner.withPropertyValues("careconnect.embedding.backfill.enabled=false")
                .run(context -> assertThat(context).doesNotHaveBean(ChunkEmbeddingBackfillWorker.class));
    }

    @Test
    @DisplayName("backfill worker is not created when careconnect.embedding.enabled=false")
    void workerDisabledWhenEmbeddingPropertyFalse() {
        runner.withPropertyValues(
                        "careconnect.embedding.enabled=false",
                        "careconnect.embedding.backfill.enabled=true")
                .run(context -> assertThat(context).doesNotHaveBean(ChunkEmbeddingBackfillWorker.class));
    }

    @Test
    @DisplayName("backfill worker is created when both embedding flags are true")
    void workerEnabledWhenBothPropertiesTrue() {
        runner.withPropertyValues(
                        "careconnect.embedding.enabled=true",
                        "careconnect.embedding.backfill.enabled=true")
                .run(context -> assertThat(context).hasSingleBean(ChunkEmbeddingBackfillWorker.class));
    }

    @Test
    @DisplayName("backfill worker is created by default when properties are omitted (matchIfMissing)")
    void workerEnabledByDefault() {
        runner.run(context -> assertThat(context).hasSingleBean(ChunkEmbeddingBackfillWorker.class));
    }
}
