package com.careconnect.service.ai.retrieval;

import com.careconnect.model.retrieval.RetrievalIndexChunk;
import com.careconnect.model.retrieval.RetrievalIndexSchema;
import com.careconnect.repository.retrieval.RetrievalIndexChunkRepository;
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
class FullTextSearchServiceTest {

    @Mock
    private RetrievalIndexChunkRepository chunkRepository;

    private FullTextSearchService service;

    @BeforeEach
    void setUp() {
        service = new FullTextSearchService(chunkRepository);
    }

    @Test
    @DisplayName("search returns empty when patientId is null")
    void search_nullPatient_returnsEmpty() {
        assertThat(service.search(null, "metformin", 10)).isEmpty();
        verify(chunkRepository, never()).searchByPatientIdFullText(anyLong(), anyString(), anyInt());
    }

    @Test
    @DisplayName("search returns empty when query is blank")
    void search_blankQuery_returnsEmpty() {
        assertThat(service.search(42L, "  ", 10)).isEmpty();
        verify(chunkRepository, never()).searchByPatientIdFullText(anyLong(), anyString(), anyInt());
    }

    @Test
    @DisplayName("search delegates to repository with default limit when limit <= 0")
    void search_defaultLimit() {
        when(chunkRepository.searchByPatientIdFullText(eq(42L), eq("metformin"), eq(20)))
                .thenReturn(List.of(chunk("CALL_SUMMARY", "Started metformin")));

        final List<RetrievalIndexChunk> hits = service.search(42L, "metformin", 0);

        assertThat(hits).hasSize(1);
        verify(chunkRepository).searchByPatientIdFullText(42L, "metformin", 20);
    }

    @Test
    @DisplayName("search clamps limit to max 100")
    void search_clampsLimit() {
        when(chunkRepository.searchByPatientIdFullText(eq(42L), eq("pain"), eq(100)))
                .thenReturn(List.of());

        service.search(42L, "pain", 500);

        verify(chunkRepository).searchByPatientIdFullText(42L, "pain", 100);
    }

    @Test
    @DisplayName("search truncates oversized queries")
    void search_truncatesLongQuery() {
        final String longQuery = "x".repeat(RetrievalIndexSchema.FTS_QUERY_MAX_LENGTH + 50);
        when(chunkRepository.searchByPatientIdFullText(anyLong(), anyString(), anyInt()))
                .thenReturn(List.of());

        service.search(7L, longQuery, 5);

        final ArgumentCaptor<String> queryCaptor = ArgumentCaptor.forClass(String.class);
        verify(chunkRepository).searchByPatientIdFullText(eq(7L), queryCaptor.capture(), eq(5));
        assertThat(queryCaptor.getValue()).hasSize(RetrievalIndexSchema.FTS_QUERY_MAX_LENGTH);
    }

    @Test
    @DisplayName("search pushes allowed record types into SQL before LIMIT")
    void search_filtersRecordTypesInSql() {
        when(chunkRepository.searchByPatientIdFullTextAndRecordTypes(
                        eq(42L), eq("dose"), anyCollection(), eq(10)))
                .thenReturn(List.of(
                        chunk("CALL_SUMMARY", "dose change"),
                        chunk("TRANSCRIPT_SEGMENT", "dose mentioned")));

        final List<RetrievalIndexChunk> hits = service.search(
                42L,
                "dose",
                Set.of("CALL_SUMMARY", "TRANSCRIPT_SEGMENT"),
                10);

        assertThat(hits).hasSize(2);
        @SuppressWarnings("unchecked")
        final ArgumentCaptor<java.util.Collection<String>> typesCaptor =
                ArgumentCaptor.forClass(java.util.Collection.class);
        verify(chunkRepository).searchByPatientIdFullTextAndRecordTypes(
                eq(42L), eq("dose"), typesCaptor.capture(), eq(10));
        assertThat(typesCaptor.getValue()).containsExactlyInAnyOrder(
                "CALL_SUMMARY", "TRANSCRIPT_SEGMENT");
        verify(chunkRepository, never()).searchByPatientIdFullText(anyLong(), anyString(), anyInt());
    }

    @Test
    @DisplayName("countChunksMissingSearchVector delegates to repository")
    void countMissing_delegates() {
        when(chunkRepository.countMissingSearchVector()).thenReturn(3L);
        assertThat(service.countChunksMissingSearchVector()).isEqualTo(3L);
    }

    private static RetrievalIndexChunk chunk(final String recordType, final String text) {
        return RetrievalIndexChunk.builder()
                .patientId(42L)
                .recordType(recordType)
                .sourceRecordId("src-1")
                .chunkText(text)
                .build();
    }
}
