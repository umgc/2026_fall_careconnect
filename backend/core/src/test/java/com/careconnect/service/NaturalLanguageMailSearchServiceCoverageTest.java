package com.careconnect.service;

import com.careconnect.dto.NaturalLanguageMailSearchResponse;
import com.careconnect.model.User;
import com.careconnect.model.UspsMailpiece;
import com.careconnect.model.retrieval.RetrievalIndexChunk;
import com.careconnect.repository.UspsMailpieceRepository;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.Role;
import com.careconnect.service.ai.embedding.ChunkEmbeddingService;
import com.careconnect.service.ai.retrieval.CaregiverVisibilityFilter;
import com.careconnect.service.ai.retrieval.FullTextSearchService;
import com.careconnect.service.ai.retrieval.RetrievalRecordType;
import com.careconnect.service.ai.retrieval.RetrievalScope;
import com.careconnect.service.ai.retrieval.RetrievalScopeService;
import com.careconnect.service.ai.retrieval.VectorSimilaritySearchService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.Set;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
class NaturalLanguageMailSearchServiceCoverageTest {

    @Mock private AuthorizationService authorizationService;
    @Mock private RetrievalScopeService retrievalScopeService;
    @Mock private FullTextSearchService fullTextSearchService;
    @Mock private VectorSimilaritySearchService vectorSimilaritySearchService;
    @Mock private ChunkEmbeddingService chunkEmbeddingService;
    @Mock private UspsMailpieceRepository mailpieceRepository;

    private NaturalLanguageMailSearchService service;
    private final User caller = User.builder().id(9L).role(Role.CAREGIVER).build();

    private static UspsMailpiece piece(Long id, String level, String summary) {
        UspsMailpiece p = new UspsMailpiece();
        p.setId(id);
        p.setPatientId(42L);
        p.setSender("Sender " + id);
        p.setSummary(summary);
        p.setImportanceLevel(level);
        p.setDigestDate(id % 2 == 0 ? LocalDate.of(2025, 3, 3) : null);
        return p;
    }

    private static RetrievalIndexChunk chunk(String sourceId, String text) {
        return RetrievalIndexChunk.builder().sourceRecordId(sourceId).chunkText(text).build();
    }

    @BeforeEach
    void setUp() throws Exception {
        service = new NaturalLanguageMailSearchService(authorizationService, retrievalScopeService,
                fullTextSearchService, vectorSimilaritySearchService, chunkEmbeddingService, mailpieceRepository);
        when(retrievalScopeService.resolveRetrievalScope(any(), eq(42L), any())).thenReturn(new RetrievalScope(
                9L, Role.CAREGIVER, Set.of(42L), Set.of(RetrievalRecordType.USPS_MAIL), Set.of(),
                new CaregiverVisibilityFilter(Role.CAREGIVER, true), true));
    }

    @Test
    void hybridSearchMergesTableFtsAndVectorLegs() throws Exception {
        List<UspsMailpiece> nullable = new ArrayList<>();
        nullable.add(null);
        nullable.add(piece(1L, "LOW", "Pharmacy bill"));
        when(mailpieceRepository.searchByPatientIdAndTerm(42L, "pharmacy")).thenReturn(nullable);
        when(mailpieceRepository.searchByPatientIdAndTerm(42L, "HIGH")).thenReturn(List.of(piece(2L, "HIGH", "Tax")));
        when(mailpieceRepository.searchByPatientIdAndTerm(42L, "MODERATE"))
                .thenReturn(List.of(piece(3L, "MODERATE", "Notice")));
        when(fullTextSearchService.search(eq(42L), anyString(), any(), anyInt())).thenReturn(List.of(
                chunk("1", "Pharmacy bill chunk"), chunk("not-a-number", "x"), chunk("4", "y".repeat(400))));
        when(chunkEmbeddingService.embedQuery(anyString())).thenReturn(Optional.of(new float[]{0.1f, 0.2f}));
        when(vectorSimilaritySearchService.search(eq(42L), any(float[].class), any(), anyInt())).thenReturn(List.of(
                chunk("2", "Tax chunk"), chunk(null, "z"), chunk("5", "vector only")));
        List<UspsMailpiece> idIn = new ArrayList<>();
        idIn.add(piece(1L, "LOW", "Pharmacy bill"));
        idIn.add(piece(4L, null, null));
        idIn.add(piece(2L, "HIGH", "Tax"));
        idIn.add(piece(5L, "unknown", "Vector"));
        idIn.add(null);
        when(mailpieceRepository.findByPatientIdAndIdIn(eq(42L), anyList())).thenReturn(idIn);

        NaturalLanguageMailSearchResponse resp = service.search(caller, 42L, "urgent pharmacy", 0);
        assertThat(resp.matches()).isNotEmpty();
        assertThat(service.search(caller, 42L, "   ", 5).matches()).isEmpty();
        assertThat(service.search(caller, 42L, "the of", 500)).isNotNull();
    }

    @Test
    void scopeDenialAndEmptyVectorResultsAreSkipped() throws Exception {
        when(retrievalScopeService.resolveRetrievalScope(any(), eq(42L), any())).thenReturn(new RetrievalScope(
                9L, Role.CAREGIVER, Set.of(42L), Set.of(), Set.of(),
                new CaregiverVisibilityFilter(Role.CAREGIVER, true), true));
        assertThat(service.search(caller, 42L, "pharmacy", 10).matches()).isEmpty();

        when(retrievalScopeService.resolveRetrievalScope(any(), eq(42L), any()))
                .thenThrow(new IllegalStateException("scope down"));
        assertThat(service.search(caller, 42L, "pharmacy", 10).matches()).isEmpty();
    }

    @Test
    void vectorLegHandlesEmptyEmbeddingsAndChunks() throws Exception {
        when(fullTextSearchService.search(eq(42L), anyString(), any(), anyInt()))
                .thenReturn(List.of(chunk("bad", "x")));
        when(chunkEmbeddingService.embedQuery(anyString())).thenReturn(Optional.empty());
        assertThat(service.search(caller, 42L, "pharmacy", 10).matches()).isEmpty();

        when(chunkEmbeddingService.embedQuery(anyString())).thenReturn(Optional.of(new float[]{1f}));
        when(vectorSimilaritySearchService.search(anyLong(), any(float[].class), any(), anyInt()))
                .thenReturn(List.of());
        assertThat(service.search(caller, 42L, "pharmacy", 10).matches()).isEmpty();

        when(vectorSimilaritySearchService.search(anyLong(), any(float[].class), any(), anyInt()))
                .thenReturn(List.of(chunk("bad", "x")));
        assertThat(service.search(caller, 42L, "pharmacy", 10).matches()).isEmpty();
    }
}
