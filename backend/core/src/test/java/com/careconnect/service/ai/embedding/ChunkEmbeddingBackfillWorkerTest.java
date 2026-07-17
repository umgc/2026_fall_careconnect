package com.careconnect.service.ai.embedding;

import com.careconnect.model.retrieval.RetrievalIndexChunk;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

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
        worker = new ChunkEmbeddingBackfillWorker(chunkRepository, chunkEmbeddingService, 50);
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
        when(chunkRepository.countMissingEmbeddingsForBackfill()).thenReturn(0L);

        worker.pollAndBackfill();

        verify(chunkEmbeddingService).embedAndPersist(List.of(chunk));
        verify(chunkRepository).countMissingEmbeddingsForBackfill();
    }

    @Test
    @DisplayName("batch size is clamped to at least 1")
    void batchSizeClampedToMinimum() {
        final ChunkEmbeddingBackfillWorker smallBatchWorker =
                new ChunkEmbeddingBackfillWorker(chunkRepository, chunkEmbeddingService, 0);
        when(chunkRepository.findMissingEmbeddingsForBackfill(1)).thenReturn(List.of());

        smallBatchWorker.pollAndBackfill();

        verify(chunkRepository).findMissingEmbeddingsForBackfill(1);
    }
}
