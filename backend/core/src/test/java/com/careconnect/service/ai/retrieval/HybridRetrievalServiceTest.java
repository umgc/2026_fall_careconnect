package com.careconnect.service.ai.retrieval;

import com.careconnect.model.retrieval.RetrievalIndexChunk;
import com.careconnect.security.Role;
import com.careconnect.service.ai.embedding.ChunkEmbeddingService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anySet;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class HybridRetrievalServiceTest {

    @Mock
    private FullTextSearchService fullTextSearchService;
    @Mock
    private VectorSimilaritySearchService vectorSimilaritySearchService;
    @Mock
    private ChunkEmbeddingService chunkEmbeddingService;

    private HybridRetrievalService service;

    @BeforeEach
    void setUp() {
        service = new HybridRetrievalService(
                fullTextSearchService,
                vectorSimilaritySearchService,
                chunkEmbeddingService,
                20,
                20,
                10,
                60,
                3,
                2);
    }

    @Test
    @DisplayName("search returns empty when query blank")
    void search_blankQuery() {
        final HybridRetrievalResult result = service.search(scope(42L), 42L, "  ");
        assertThat(result.isEmpty()).isTrue();
        verify(fullTextSearchService, never()).search(anyLong(), any(), anySet(), anyInt());
    }

    @Test
    @DisplayName("search returns empty when patient not in scope")
    void search_patientNotInScope() {
        final HybridRetrievalResult result = service.search(scope(99L), 42L, "metformin");
        assertThat(result.isEmpty()).isTrue();
        verify(fullTextSearchService, never()).search(anyLong(), any(), anySet(), anyInt());
    }

    @Test
    @DisplayName("search merges FTS and vector hits with citation refs")
    void search_mergesArmsAndAssignsCitations() {
        final UUID shared = UUID.randomUUID();
        final UUID ftsOnly = UUID.randomUUID();
        final float[] embedding = new float[1536];

        when(fullTextSearchService.search(eq(42L), eq("metformin"), anySet(), eq(20)))
                .thenReturn(List.of(chunk(shared, "CALL_SUMMARY", "auto"), chunk(ftsOnly, "CALL_SUMMARY", "auto")));
        when(chunkEmbeddingService.embedQuery("metformin")).thenReturn(Optional.of(embedding));
        when(vectorSimilaritySearchService.search(eq(42L), eq(embedding), anySet(), eq(20)))
                .thenReturn(List.of(chunk(shared, "CALL_SUMMARY", "auto")));

        final HybridRetrievalResult result = service.search(scope(42L), 42L, "metformin");

        assertThat(result.vectorDegraded()).isFalse();
        assertThat(result.ftsHitCount()).isEqualTo(2);
        assertThat(result.vectorHitCount()).isEqualTo(1);
        assertThat(result.chunks()).isNotEmpty();
        assertThat(result.chunks().get(0).chunkId()).isEqualTo(shared);
        assertThat(result.chunks().get(0).citationRef()).isEqualTo("C1");
        assertThat(result.chunks().get(0).ftsRank()).isEqualTo(1);
        assertThat(result.chunks().get(0).vectorRank()).isEqualTo(1);
        assertThat(result.chunks()).allSatisfy(c -> assertThat(c.citationRef()).startsWith("C"));
    }

    @Test
    @DisplayName("search degrades to FTS-only when query embedding unavailable")
    void search_vectorDegraded() {
        final UUID id = UUID.randomUUID();
        when(fullTextSearchService.search(eq(42L), eq("pain"), anySet(), eq(20)))
                .thenReturn(List.of(chunk(id, "CALL_SUMMARY", "auto")));
        when(chunkEmbeddingService.embedQuery("pain")).thenReturn(Optional.empty());

        final HybridRetrievalResult result = service.search(scope(42L), 42L, "pain");

        assertThat(result.vectorDegraded()).isTrue();
        assertThat(result.chunks()).hasSize(1);
        assertThat(result.chunks().get(0).citationRef()).isEqualTo("C1");
        assertThat(result.chunks().get(0).vectorRank()).isNull();
        verify(vectorSimilaritySearchService, never()).search(anyLong(), any(), anySet(), anyInt());
    }

    @Test
    @DisplayName("search filters chunks denied by caregiver visibility")
    void search_appliesVisibilityFilter() {
        final UUID allowed = UUID.randomUUID();
        final UUID hidden = UUID.randomUUID();
        when(fullTextSearchService.search(eq(42L), eq("note"), anySet(), eq(60)))
                .thenReturn(List.of(
                        chunk(allowed, "CALL_SUMMARY", "auto"),
                        chunk(hidden, "CALL_SUMMARY", "hidden")));
        when(chunkEmbeddingService.embedQuery("note")).thenReturn(Optional.empty());

        final RetrievalScope caregiverScope = new RetrievalScope(
                7L,
                Role.CAREGIVER,
                Set.of(42L),
                Set.of(RetrievalRecordType.CALL_SUMMARY),
                Set.of(),
                new CaregiverVisibilityFilter(Role.CAREGIVER, false),
                false);

        final HybridRetrievalResult result = service.search(caregiverScope, 42L, "note");

        assertThat(result.chunks()).hasSize(1);
        assertThat(result.chunks().get(0).chunkId()).isEqualTo(allowed);
        assertThat(result.ftsHitCount()).isEqualTo(1);
        verify(fullTextSearchService).search(eq(42L), eq("note"), anySet(), eq(60));
    }

    private static RetrievalScope scope(final Long patientId) {
        return new RetrievalScope(
                1L,
                Role.PATIENT,
                Set.of(patientId),
                Set.of(RetrievalRecordType.CALL_SUMMARY, RetrievalRecordType.TRANSCRIPT_SEGMENT),
                Set.of(),
                new CaregiverVisibilityFilter(Role.PATIENT, true),
                true);
    }

    private static RetrievalIndexChunk chunk(
            final UUID id, final String recordType, final String consentScope) {
        return RetrievalIndexChunk.builder()
                .id(id)
                .patientId(42L)
                .recordType(recordType)
                .sourceRecordId("src-1")
                .chunkText("Started metformin 500mg")
                .consentScope(consentScope)
                .build();
    }
}
