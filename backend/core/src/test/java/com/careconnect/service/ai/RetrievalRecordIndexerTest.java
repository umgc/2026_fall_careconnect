package com.careconnect.service.ai;

import com.careconnect.model.retrieval.RetrievalIndexChunk;
import com.careconnect.service.ai.RetrievalRecordChangeListener.RetrievalRecordChanged;
import com.careconnect.service.ai.embedding.ChunkEmbeddingService;
import com.careconnect.service.ai.retrieval.RetrievalRecordType;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class RetrievalRecordIndexerTest {

    @Mock
    private RetrievalIndexingService retrievalIndexingService;
    @Mock
    private ChunkEmbeddingService chunkEmbeddingService;

    private RetrievalRecordIndexer indexer;

    @BeforeEach
    void setUp() {
        indexer = new RetrievalRecordIndexer(retrievalIndexingService, chunkEmbeddingService);
    }

    @Test
    void onRecordChanged_reindexesMedicationAndEmbedsTheChunk() {
        // Arrange
        final RetrievalIndexChunk chunk = RetrievalIndexChunk.builder().sourceRecordId("medication-10").build();
        when(retrievalIndexingService.reindexMedication(10L, 5L)).thenReturn(Optional.of(chunk));

        // Act
        indexer.onRecordChanged(new RetrievalRecordChanged(RetrievalRecordType.MEDICATION, 10L, 5L));

        // Assert
        verify(chunkEmbeddingService).embedAndPersist(List.of(chunk));
    }

    @Test
    void onRecordChanged_skipsEmbeddingWhenRecordHasNoChunk() {
        when(retrievalIndexingService.reindexMedication(10L, 5L)).thenReturn(Optional.empty());

        indexer.onRecordChanged(new RetrievalRecordChanged(RetrievalRecordType.MEDICATION, 10L, 5L));

        verifyNoInteractions(chunkEmbeddingService);
    }

    @Test
    void onRecordChanged_reindexesTask() {
        indexer.onRecordChanged(new RetrievalRecordChanged(RetrievalRecordType.TASK, 20L, 5L));

        verify(retrievalIndexingService).reindexTask(20L, 5L);
        verifyNoInteractions(chunkEmbeddingService);
    }

    @Test
    void onRecordChanged_ignoresRecordTypesWithoutPerRecordIndexer() {
        indexer.onRecordChanged(new RetrievalRecordChanged(RetrievalRecordType.CLINICAL_NOTE, 30L, 5L));

        verifyNoInteractions(retrievalIndexingService, chunkEmbeddingService);
    }

    @Test
    void onRecordChanged_swallowsIndexingFailure() {
        // Arrange: the user's write already committed, so an indexing error must not reach them
        doThrow(new IllegalStateException("db unavailable"))
                .when(retrievalIndexingService).reindexMedication(10L, 5L);

        // Act / Assert
        assertThatCode(() -> indexer.onRecordChanged(
                new RetrievalRecordChanged(RetrievalRecordType.MEDICATION, 10L, 5L)))
                .doesNotThrowAnyException();
    }
}
