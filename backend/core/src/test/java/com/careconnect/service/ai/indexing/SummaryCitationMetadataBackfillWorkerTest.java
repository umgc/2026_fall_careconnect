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
                chunkRepository, retrievalIndexService, 2);
    }

    @Test
    void pollAndBackfill_usesBoundedBatchAndContinuesAfterMalformedId() {
        when(chunkRepository.findStaleSummaryCitationSourceIds(
                RetrievalRecordType.summaryTypeNames(),
                SummaryChunker.CITATION_METADATA_VERSION,
                2)).thenReturn(List.of("not-a-number", "42"));

        worker.pollAndBackfill();

        verify(retrievalIndexService).replaySummaryCitationMetadata(42L);
    }

    @Test
    void pollAndBackfill_failureDoesNotBlockRemainingSources() {
        when(chunkRepository.findStaleSummaryCitationSourceIds(
                RetrievalRecordType.summaryTypeNames(),
                SummaryChunker.CITATION_METADATA_VERSION,
                2)).thenReturn(List.of("41", "42"));
        when(retrievalIndexService.replaySummaryCitationMetadata(41L))
                .thenThrow(new IllegalStateException("failed"));

        worker.pollAndBackfill();

        final InOrder order = inOrder(retrievalIndexService);
        order.verify(retrievalIndexService).replaySummaryCitationMetadata(41L);
        order.verify(retrievalIndexService).replaySummaryCitationMetadata(42L);
    }

    @Test
    void pollAndBackfill_secondNoOpPassDoesNotReplayAgain() {
        when(chunkRepository.findStaleSummaryCitationSourceIds(
                RetrievalRecordType.summaryTypeNames(),
                SummaryChunker.CITATION_METADATA_VERSION,
                2)).thenReturn(List.of("42"), List.of());

        worker.pollAndBackfill();
        worker.pollAndBackfill();

        verify(retrievalIndexService).replaySummaryCitationMetadata(42L);
        verify(retrievalIndexService, never()).replaySummaryCitationMetadata(43L);
    }
}
