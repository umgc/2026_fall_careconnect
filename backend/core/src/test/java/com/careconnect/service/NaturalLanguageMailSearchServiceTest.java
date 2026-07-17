package com.careconnect.service;

import com.careconnect.dto.NaturalLanguageMailSearchResponse;
import com.careconnect.model.UspsMailpiece;
import com.careconnect.model.User;
import com.careconnect.model.retrieval.RetrievalIndexChunk;
import com.careconnect.repository.UspsMailpieceRepository;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.Role;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.ai.retrieval.CaregiverVisibilityFilter;
import com.careconnect.service.ai.retrieval.FullTextSearchService;
import com.careconnect.service.ai.retrieval.RetrievalRecordType;
import com.careconnect.service.ai.retrieval.RetrievalScope;
import com.careconnect.service.ai.retrieval.RetrievalScopeService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.LocalDate;
import java.util.List;
import java.util.Set;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doNothing;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class NaturalLanguageMailSearchServiceTest {

    @Mock private AuthorizationService authorizationService;
    @Mock private RetrievalScopeService retrievalScopeService;
    @Mock private FullTextSearchService fullTextSearchService;
    @Mock private UspsMailpieceRepository mailpieceRepository;

    private NaturalLanguageMailSearchService service;
    private User caregiver;

    @BeforeEach
    void setUp() throws Exception {
        service = new NaturalLanguageMailSearchService(
                authorizationService,
                retrievalScopeService,
                fullTextSearchService,
                mailpieceRepository);
        caregiver = new User();
        caregiver.setId(9L);
        caregiver.setRole(Role.CAREGIVER);
        lenient().doNothing().when(authorizationService).requirePatientAccess(any(), anyLong());
    }

    @Test
    @DisplayName("tokenize strips stop words and keeps domain terms")
    void tokenize_stripsStopWords() {
        assertThat(NaturalLanguageMailSearchService.tokenize("Show me pharmacy mail bills"))
                .containsExactly("pharmacy", "bills");
    }

    @Test
    @DisplayName("blank query returns empty matches")
    void search_blankQuery_returnsEmpty() throws Exception {
        final NaturalLanguageMailSearchResponse response =
                service.search(caregiver, 42L, "   ", 10);

        assertThat(response.matches()).isEmpty();
        assertThat(response.totalMatches()).isZero();
        verify(mailpieceRepository, never()).searchByPatientIdAndTerm(anyLong(), anyString());
    }

    @Test
    @DisplayName("table matches are ranked and include importance fields")
    void search_tableHits_ranked() throws Exception {
        final UspsMailpiece high = mailpiece(1L, "CVS Pharmacy", "Prescription ready", "HIGH");
        final UspsMailpiece low = mailpiece(2L, "Retail", "Pharmacy coupon sale", "LOW");
        when(mailpieceRepository.searchByPatientIdAndTerm(42L, "pharmacy"))
                .thenReturn(List.of(high, low));
        lenient().when(mailpieceRepository.searchByPatientIdAndTerm(42L, "bills"))
                .thenReturn(List.of());
        when(retrievalScopeService.resolveRetrievalScope(any(), eq(42L), any()))
                .thenThrow(new UnauthorizedException("no AI"));

        final NaturalLanguageMailSearchResponse response =
                service.search(caregiver, 42L, "pharmacy bills", 10);

        assertThat(response.tokens()).contains("pharmacy", "bills");
        assertThat(response.matches()).hasSize(2);
        assertThat(response.matches().get(0).mailpieceId()).isEqualTo(1L);
        assertThat(response.matches().get(0).importanceLevel()).isEqualTo("HIGH");
        assertThat(response.matches().get(0).matchSources()).contains("TABLE");
        assertThat(response.matches().get(0).score())
                .isGreaterThan(response.matches().get(1).score());
    }

    @Test
    @DisplayName("FTS USPS_MAIL hits merge with durable rows")
    void search_ftsHits_mergeWithTable() throws Exception {
        lenient().when(mailpieceRepository.searchByPatientIdAndTerm(anyLong(), anyString()))
                .thenReturn(List.of());
        when(retrievalScopeService.resolveRetrievalScope(eq(caregiver), eq(42L), any()))
                .thenReturn(new RetrievalScope(
                        9L, Role.CAREGIVER, Set.of(42L),
                        Set.of(RetrievalRecordType.USPS_MAIL), Set.of(),
                        new CaregiverVisibilityFilter(Role.CAREGIVER, true), true));
        final RetrievalIndexChunk chunk = RetrievalIndexChunk.builder()
                .sourceRecordId("77")
                .recordType("USPS_MAIL")
                .chunkText("From: Hospital\nLab results")
                .build();
        when(fullTextSearchService.search(eq(42L), anyString(), any(), anyInt()))
                .thenReturn(List.of(chunk));
        final UspsMailpiece piece = mailpiece(77L, "Hospital", "Lab results", "HIGH");
        when(mailpieceRepository.findByPatientIdAndIdIn(eq(42L), any()))
                .thenReturn(List.of(piece));

        final NaturalLanguageMailSearchResponse response =
                service.search(caregiver, 42L, "hospital lab results", 10);

        assertThat(response.matches()).hasSize(1);
        assertThat(response.matches().get(0).mailpieceId()).isEqualTo(77L);
        assertThat(response.matches().get(0).matchSources()).contains("FTS", "TABLE");
        assertThat(response.matches().get(0).snippet()).contains("Hospital");
    }

    private static UspsMailpiece mailpiece(
            final Long id, final String sender, final String summary, final String level) {
        final UspsMailpiece piece = new UspsMailpiece();
        piece.setId(id);
        piece.setPatientId(42L);
        piece.setSender(sender);
        piece.setSummary(summary);
        piece.setImportanceLevel(level);
        piece.setImportanceReasoning("test reasoning");
        piece.setDigestDate(LocalDate.of(2025, 3, 3));
        return piece;
    }
}
