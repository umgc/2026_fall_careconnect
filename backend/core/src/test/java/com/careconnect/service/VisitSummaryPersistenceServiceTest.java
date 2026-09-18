package com.careconnect.service;

import com.careconnect.indexing.IndexingEventEmitter;
import com.careconnect.indexing.SummaryCreatedPayload;
import com.careconnect.model.VisitSummary;
import com.careconnect.repository.VisitSummaryRepository;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.LocalDateTime;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class VisitSummaryPersistenceServiceTest {

    @Mock
    private VisitSummaryRepository visitSummaryRepository;
    @Mock
    private IndexingEventEmitter indexingEventEmitter;

    @InjectMocks
    private VisitSummaryPersistenceService persistenceService;

    private static VisitSummary sample(final String status) {
        final VisitSummary summary = new VisitSummary();
        summary.setVisitId("visit-1");
        summary.setPatientId(42L);
        summary.setSummaryJson("{\"overview\":\"ok\"}");
        summary.setStatus(status);
        summary.setTranscriptSegmentCount(3);
        summary.setGeneratedAt(LocalDateTime.of(2026, 7, 23, 12, 0));
        summary.setCaregiverVisibility("on_consent");
        summary.setSummarizationEngine("test-engine");
        return summary;
    }

    @Test
    void persist_emitsSummaryCreatedForSuccessfulVisit() {
        final VisitSummary incoming = sample("SUCCESS");
        when(visitSummaryRepository.save(any())).thenAnswer(invocation -> {
            final VisitSummary saved = invocation.getArgument(0);
            saved.setId(55L);
            return saved;
        });

        persistenceService.persist(incoming);

        final ArgumentCaptor<SummaryCreatedPayload> captor =
                ArgumentCaptor.forClass(SummaryCreatedPayload.class);
        verify(indexingEventEmitter).emitSummaryCreated(captor.capture());
        final SummaryCreatedPayload payload = captor.getValue();
        assertThat(payload.episodeType()).isEqualTo("visit");
        assertThat(payload.sourceTable()).isEqualTo("visit_summaries");
        assertThat(payload.summaryId()).isEqualTo(55L);
        assertThat(payload.callId()).isNull();
        assertThat(payload.patientId()).isEqualTo(42L);
        assertThat(payload.status()).isEqualTo("SUCCESS");
        assertThat(payload.contentHash()).isNotBlank();
    }

    @Test
    void persist_skipsEmitWhenNotSuccessful() {
        when(visitSummaryRepository.save(any())).thenAnswer(invocation -> {
            final VisitSummary saved = invocation.getArgument(0);
            saved.setId(56L);
            return saved;
        });

        persistenceService.persist(sample("ERROR"));

        verify(indexingEventEmitter, never()).emitSummaryCreated(any());
    }

    @Test
    void persist_requiresPatientIdForSuccessfulRows() {
        final VisitSummary missingPatient = sample("SUCCESS");
        missingPatient.setPatientId(null);
        when(visitSummaryRepository.save(any())).thenAnswer(invocation -> {
            final VisitSummary saved = invocation.getArgument(0);
            saved.setId(57L);
            return saved;
        });

        assertThatThrownBy(() -> persistenceService.persist(missingPatient))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("patient ownership");
        verify(indexingEventEmitter, never()).emitSummaryCreated(any());
    }
}
