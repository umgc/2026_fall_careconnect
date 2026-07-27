package com.careconnect.service.ai.retrieval;

import com.careconnect.model.retrieval.RetrievalIndexChunk;
import com.careconnect.model.retrieval.RetrievalIndexSchema;
import com.careconnect.repository.retrieval.RetrievalIndexChunkRepository;
import com.careconnect.service.ai.embedding.EmbeddingVectorFormat;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.List;
import java.util.Set;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyCollection;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class VectorSimilaritySearchServiceTest {

    @Mock
    private RetrievalIndexChunkRepository chunkRepository;

    private VectorSimilaritySearchService service;

    @BeforeEach
    void setUp() {
        service = new VectorSimilaritySearchService(chunkRepository);
    }

    @Test
    @DisplayName("search returns empty when patientId is null")
    void search_nullPatient() {
        assertThat(service.search(null, new float[RetrievalIndexSchema.EMBEDDING_DIMENSION], 10))
                .isEmpty();
        verify(chunkRepository, never()).searchByPatientIdVector(anyLong(), anyString(), anyInt());
    }

    @Test
    @DisplayName("search returns empty for wrong-dimension embedding")
    void search_wrongDimension() {
        assertThat(service.search(42L, new float[8], 10)).isEmpty();
        verify(chunkRepository, never()).searchByPatientIdVector(anyLong(), anyString(), anyInt());
    }

    @Test
    @DisplayName("search delegates with pgvector literal and default limit")
    void search_defaultLimit() {
        final float[] embedding = new float[RetrievalIndexSchema.EMBEDDING_DIMENSION];
        embedding[0] = 0.25f;
        when(chunkRepository.searchByPatientIdVector(eq(42L), anyString(), eq(20)))
                .thenReturn(List.of(RetrievalIndexChunk.builder()
                        .patientId(42L)
                        .recordType("CALL_SUMMARY")
                        .chunkText("hit")
                        .build()));

        final List<RetrievalIndexChunk> hits = service.search(42L, embedding, 0);

        assertThat(hits).hasSize(1);
        final ArgumentCaptor<String> literal = ArgumentCaptor.forClass(String.class);
        verify(chunkRepository).searchByPatientIdVector(eq(42L), literal.capture(), eq(20));
        assertThat(literal.getValue()).isEqualTo(EmbeddingVectorFormat.toPgVectorLiteral(embedding));
    }

    @Test
    @DisplayName("search with record types uses typed repository method")
    void search_withRecordTypes() {
        final float[] embedding = new float[RetrievalIndexSchema.EMBEDDING_DIMENSION];
        when(chunkRepository.searchByPatientIdVectorAndRecordTypes(
                        eq(42L), anyString(), anyCollection(), eq(5)))
                .thenReturn(List.of());

        service.search(42L, embedding, Set.of("CALL_SUMMARY"), 5);

        verify(chunkRepository).searchByPatientIdVectorAndRecordTypes(
                eq(42L), anyString(), eq(Set.of("CALL_SUMMARY")), eq(5));
        verify(chunkRepository, never()).searchByPatientIdVector(anyLong(), anyString(), anyInt());
    }
}
