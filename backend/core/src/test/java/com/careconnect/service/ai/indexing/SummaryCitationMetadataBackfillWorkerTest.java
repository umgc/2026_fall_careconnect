package com.careconnect.service.ai.indexing;

import com.careconnect.repository.retrieval.RetrievalIndexChunkRepository;
import com.careconnect.repository.retrieval.RetrievalIndexChunkRepository.SummaryReplayCandidate;
import com.careconnect.service.ai.indexing.chunker.SummaryChunker;
import com.careconnect.service.ai.retrieval.RetrievalRecordType;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InOrder;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.List;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.inOrder;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class SummaryCitationMetadataBackfillWorkerTest {

    @Mock
    private RetrievalIndexChunkRepository chunkRepository;
    @Mock
    private RetrievalIndexService retrievalIndexService;

    private SummaryCitationMetadataBackfillWorker worker;

    @BeforeEach
    void setUp() {
        worker = new SummaryCitationMetadataBackfillWorker(
                chunkRepository, retrievalIndexService, 2, 60_000L);
    }

    @Test
    void pollAndBackfill_usesBoundedBatchAndContinuesAfterMalformedId() {
        when(chunkRepository.findStaleSummaryCitationSources(
                RetrievalRecordType.summaryTypeNames(),
                SummaryChunker.CITATION_METADATA_VERSION,
                2)).thenReturn(List.of(candidate(42L, "not-a-number"), candidate(42L, "42")));
        when(retrievalIndexService.replaySummaryCitationMetadata(42L, 42L))
                .thenReturn(SummaryCitationReplayOutcome.CURRENT);

        worker.pollAndBackfill();

        verify(retrievalIndexService).replaySummaryCitationMetadata(42L, 42L);
        verify(chunkRepository).markSummaryCitationReplayFailure(
                org.mockito.ArgumentMatchers.eq(42L),
                org.mockito.ArgumentMatchers.eq("not-a-number"),
                org.mockito.ArgumentMatchers.eq(RetrievalRecordType.summaryTypeNames()),
                any());
    }

    @Test
    void pollAndBackfill_failureDoesNotBlockRemainingSources() {
        when(chunkRepository.findStaleSummaryCitationSources(
                RetrievalRecordType.summaryTypeNames(),
                SummaryChunker.CITATION_METADATA_VERSION,
                2)).thenReturn(List.of(candidate(42L, "41"), candidate(42L, "call-summary:42")));
        when(retrievalIndexService.replaySummaryCitationMetadata(41L, 42L))
                .thenThrow(new IllegalStateException("failed"));
        when(retrievalIndexService.replaySummaryCitationMetadata(42L, 42L))
                .thenReturn(SummaryCitationReplayOutcome.CURRENT);

        worker.pollAndBackfill();

        final InOrder order = inOrder(retrievalIndexService);
        order.verify(retrievalIndexService).replaySummaryCitationMetadata(41L, 42L);
        order.verify(retrievalIndexService).replaySummaryCitationMetadata(42L, 42L);
        verify(chunkRepository).markSummaryCitationReplayFailure(
                org.mockito.ArgumentMatchers.eq(42L),
                org.mockito.ArgumentMatchers.eq("41"),
                org.mockito.ArgumentMatchers.eq(RetrievalRecordType.summaryTypeNames()),
                any());
    }

    @Test
    void pollAndBackfill_secondNoOpPassDoesNotReplayAgain() {
        when(chunkRepository.findStaleSummaryCitationSources(
                RetrievalRecordType.summaryTypeNames(),
                SummaryChunker.CITATION_METADATA_VERSION,
                2)).thenReturn(List.of(candidate(42L, "42")), List.of());
        when(retrievalIndexService.replaySummaryCitationMetadata(42L, 42L))
                .thenReturn(SummaryCitationReplayOutcome.UPDATED);

        worker.pollAndBackfill();
        worker.pollAndBackfill();

        verify(retrievalIndexService).replaySummaryCitationMetadata(42L, 42L);
        verify(retrievalIndexService, never()).replaySummaryCitationMetadata(43L, 42L);
    }

    @Test
    void pollAndBackfill_noDraftOutcomeIsBackedOff() {
        when(chunkRepository.findStaleSummaryCitationSources(
                RetrievalRecordType.summaryTypeNames(),
                SummaryChunker.CITATION_METADATA_VERSION,
                2)).thenReturn(List.of(candidate(42L, "call-summary:42")));
        when(retrievalIndexService.replaySummaryCitationMetadata(42L, 42L))
                .thenReturn(SummaryCitationReplayOutcome.NO_DRAFTS);

        worker.pollAndBackfill();

        verify(chunkRepository).markSummaryCitationReplayFailure(
                org.mockito.ArgumentMatchers.eq(42L),
                org.mockito.ArgumentMatchers.eq("call-summary:42"),
                org.mockito.ArgumentMatchers.eq(RetrievalRecordType.summaryTypeNames()),
                any());
    }

    @Test
    void pollAndBackfill_ownerMismatchIsQuarantined() {
        when(chunkRepository.findStaleSummaryCitationSources(
                RetrievalRecordType.summaryTypeNames(),
                SummaryChunker.CITATION_METADATA_VERSION,
                2)).thenReturn(List.of(candidate(99L, "42")));
        when(retrievalIndexService.replaySummaryCitationMetadata(42L, 99L))
                .thenReturn(SummaryCitationReplayOutcome.QUARANTINED);
        when(chunkRepository.quarantineSummarySource(
                99L, "42", RetrievalRecordType.summaryTypeNames())).thenReturn(2);

        worker.pollAndBackfill();

        verify(chunkRepository).quarantineSummarySource(
                99L, "42", RetrievalRecordType.summaryTypeNames());
    }

    private static SummaryReplayCandidate candidate(
            final Long patientId,
            final String sourceRecordId) {
        return new SummaryReplayCandidate() {
            @Override
            public Long getPatientId() {
                return patientId;
            }

            @Override
            public String getSourceRecordId() {
                return sourceRecordId;
            }
        };
    }
}
