package com.careconnect.service.ai.embedding;

import com.careconnect.model.retrieval.RetrievalIndexChunk;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.List;
import java.util.UUID;

import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class ChunkEmbeddingBackfillWorkerTest {

    @Mock
    private com.careconnect.repository.retrieval.RetrievalIndexChunkRepository chunkRepository;

    @Mock
    private ChunkEmbeddingService chunkEmbeddingService;

    private ChunkEmbeddingBackfillWorker worker;

    @BeforeEach
    void setUp() {
        worker = new ChunkEmbeddingBackfillWorker(chunkRepository, chunkEmbeddingService);
        ReflectionTestUtils.setField(worker, "embeddingEnabled", true);
        ReflectionTestUtils.setField(worker, "batchSize", 50);
    }

    @Test
    @DisplayName("pollAndBackfill no-ops when embedding is disabled")
    void skipsWhenEmbeddingDisabled() {
        ReflectionTestUtils.setField(worker, "embeddingEnabled", false);

        worker.pollAndBackfill();

        verify(chunkRepository, never()).findMissingEmbeddingsForBackfill(anyInt());
        verify(chunkEmbeddingService, never()).embedAndPersist(org.mockito.ArgumentMatchers.anyList());
    }

    @Test
    @DisplayName("pollAndBackfill no-ops when no chunks are missing embeddings")
    void skipsWhenBatchEmpty() {
        when(chunkRepository.findMissingEmbeddingsForBackfill(50)).thenReturn(List.of());

        worker.pollAndBackfill();

        verify(chunkEmbeddingService, never()).embedAndPersist(org.mockito.ArgumentMatchers.anyList());
    }

    @Test
    @DisplayName("pollAndBackfill embeds oldest NULL-embedding batch")
    void embedsMissingBatch() {
        final RetrievalIndexChunk chunk = RetrievalIndexChunk.builder()
                .id(UUID.randomUUID())
                .patientId(1L)
                .recordType("CALL_SUMMARY")
                .chunkText("vitals stable")
                .build();
        when(chunkRepository.findMissingEmbeddingsForBackfill(50)).thenReturn(List.of(chunk));
        when(chunkEmbeddingService.embedAndPersist(List.of(chunk))).thenReturn(1);
        when(chunkRepository.countMissingEmbedding()).thenReturn(0L);

        worker.pollAndBackfill();

        verify(chunkEmbeddingService).embedAndPersist(List.of(chunk));
        verify(chunkRepository).countMissingEmbedding();
    }
}
