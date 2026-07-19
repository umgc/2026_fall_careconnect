package com.careconnect.service.ai.indexing;

import com.careconnect.repository.retrieval.RetrievalIndexChunkRepository;
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
        when(chunkRepository.findStaleSummaryCitationSourceIds(
                RetrievalRecordType.summaryTypeNames(),
                SummaryChunker.CITATION_METADATA_VERSION,
                2)).thenReturn(List.of("not-a-number", "42"));
        when(retrievalIndexService.replaySummaryCitationMetadata(42L))
                .thenReturn(SummaryCitationReplayOutcome.CURRENT);

        worker.pollAndBackfill();

        verify(retrievalIndexService).replaySummaryCitationMetadata(42L);
        verify(chunkRepository).markSummaryCitationReplayFailure(
                org.mockito.ArgumentMatchers.eq("not-a-number"),
                org.mockito.ArgumentMatchers.eq(RetrievalRecordType.summaryTypeNames()),
                any());
    }

    @Test
    void pollAndBackfill_failureDoesNotBlockRemainingSources() {
        when(chunkRepository.findStaleSummaryCitationSourceIds(
                RetrievalRecordType.summaryTypeNames(),
                SummaryChunker.CITATION_METADATA_VERSION,
                2)).thenReturn(List.of("41", "call-summary:42"));
        when(retrievalIndexService.replaySummaryCitationMetadata(41L))
                .thenThrow(new IllegalStateException("failed"));
        when(retrievalIndexService.replaySummaryCitationMetadata(42L))
                .thenReturn(SummaryCitationReplayOutcome.CURRENT);

        worker.pollAndBackfill();

        final InOrder order = inOrder(retrievalIndexService);
        order.verify(retrievalIndexService).replaySummaryCitationMetadata(41L);
        order.verify(retrievalIndexService).replaySummaryCitationMetadata(42L);
        verify(chunkRepository).markSummaryCitationReplayFailure(
                org.mockito.ArgumentMatchers.eq("41"),
                org.mockito.ArgumentMatchers.eq(RetrievalRecordType.summaryTypeNames()),
                any());
    }

    @Test
    void pollAndBackfill_secondNoOpPassDoesNotReplayAgain() {
        when(chunkRepository.findStaleSummaryCitationSourceIds(
                RetrievalRecordType.summaryTypeNames(),
                SummaryChunker.CITATION_METADATA_VERSION,
                2)).thenReturn(List.of("42"), List.of());
        when(retrievalIndexService.replaySummaryCitationMetadata(42L))
                .thenReturn(SummaryCitationReplayOutcome.UPDATED);

        worker.pollAndBackfill();
        worker.pollAndBackfill();

        verify(retrievalIndexService).replaySummaryCitationMetadata(42L);
        verify(retrievalIndexService, never()).replaySummaryCitationMetadata(43L);
    }

    @Test
    void pollAndBackfill_noDraftOutcomeIsBackedOff() {
        when(chunkRepository.findStaleSummaryCitationSourceIds(
                RetrievalRecordType.summaryTypeNames(),
                SummaryChunker.CITATION_METADATA_VERSION,
                2)).thenReturn(List.of("call-summary:42"));
        when(retrievalIndexService.replaySummaryCitationMetadata(42L))
                .thenReturn(SummaryCitationReplayOutcome.NO_DRAFTS);

        worker.pollAndBackfill();

        verify(chunkRepository).markSummaryCitationReplayFailure(
                org.mockito.ArgumentMatchers.eq("call-summary:42"),
                org.mockito.ArgumentMatchers.eq(RetrievalRecordType.summaryTypeNames()),
                any());
    }
}
