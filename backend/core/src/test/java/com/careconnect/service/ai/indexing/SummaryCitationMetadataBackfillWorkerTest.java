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
import java.util.UUID;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.inOrder;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class SummaryCitationMetadataBackfillWorkerTest {

    private static final UUID CLAIM_TOKEN =
            UUID.fromString("00000000-0000-0000-0000-000000000099");

    @Mock
    private RetrievalIndexChunkRepository chunkRepository;
    @Mock
    private RetrievalIndexService retrievalIndexService;

    private SummaryCitationMetadataBackfillWorker worker;

    @BeforeEach
    void setUp() {
        worker = new SummaryCitationMetadataBackfillWorker(
                chunkRepository, retrievalIndexService, 2, 60_000L, 300_000L);
    }

    @Test
    void pollAndBackfill_usesBoundedBatchAndContinuesAfterMalformedId() {
        when(chunkRepository.claimStaleSummaryCitationSources(
                eq(RetrievalRecordType.summaryTypeNames()),
                eq(SummaryChunker.CITATION_METADATA_VERSION),
                eq(2),
                any(),
                any())).thenReturn(List.of(
                        candidate(42L, "not-a-number"),
                        candidate(42L, "call-summary:42")));
        when(retrievalIndexService.replaySummaryCitationMetadata(42L, 42L))
                .thenReturn(SummaryCitationReplayOutcome.CURRENT);

        worker.pollAndBackfill();

        verify(retrievalIndexService).replaySummaryCitationMetadata(42L, 42L);
        verify(chunkRepository).markSummaryCitationReplayFailure(
                org.mockito.ArgumentMatchers.eq(42L),
                org.mockito.ArgumentMatchers.eq("not-a-number"),
                any(),
                any());
    }

    @Test
    void pollAndBackfill_failureDoesNotBlockRemainingSources() {
        when(chunkRepository.claimStaleSummaryCitationSources(
                eq(RetrievalRecordType.summaryTypeNames()),
                eq(SummaryChunker.CITATION_METADATA_VERSION),
                eq(2),
                any(),
                any())).thenReturn(List.of(
                        candidate(42L, "call-summary:41"),
                        candidate(42L, "call-summary:42")));
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
                org.mockito.ArgumentMatchers.eq("call-summary:41"),
                any(),
                any());
    }

    @Test
    void pollAndBackfill_secondNoOpPassDoesNotReplayAgain() {
        when(chunkRepository.claimStaleSummaryCitationSources(
                eq(RetrievalRecordType.summaryTypeNames()),
                eq(SummaryChunker.CITATION_METADATA_VERSION),
                eq(2),
                any(),
                any()))
                .thenReturn(List.of(candidate(42L, "call-summary:42")))
                .thenReturn(List.of());
        when(retrievalIndexService.replaySummaryCitationMetadata(42L, 42L))
                .thenReturn(SummaryCitationReplayOutcome.UPDATED);

        worker.pollAndBackfill();
        worker.pollAndBackfill();

        verify(retrievalIndexService).replaySummaryCitationMetadata(42L, 42L);
        verify(chunkRepository).releaseSummaryCitationReplayClaim(
                42L, "call-summary:42", CLAIM_TOKEN);
        verify(retrievalIndexService, never()).replaySummaryCitationMetadata(43L, 42L);
    }

    @Test
    void pollAndBackfill_currentCanonicalSourceOnlyReleasesClaim() {
        when(chunkRepository.claimStaleSummaryCitationSources(
                eq(RetrievalRecordType.summaryTypeNames()),
                eq(SummaryChunker.CITATION_METADATA_VERSION),
                eq(2),
                any(),
                any())).thenReturn(List.of(candidate(42L, "call-summary:42")));
        when(retrievalIndexService.replaySummaryCitationMetadata(42L, 42L))
                .thenReturn(SummaryCitationReplayOutcome.CURRENT);

        worker.pollAndBackfill();

        verify(chunkRepository).releaseSummaryCitationReplayClaim(
                42L, "call-summary:42", CLAIM_TOKEN);
        verify(chunkRepository, never()).markSummaryCitationReplayFailure(
                eq(42L), eq("call-summary:42"), any(), eq(CLAIM_TOKEN));
        verify(chunkRepository, never()).quarantineSummarySource(
                eq(42L), eq("call-summary:42"), any(), eq(CLAIM_TOKEN));
    }

    @Test
    void pollAndBackfill_noDraftOutcomeIsBackedOff() {
        when(chunkRepository.claimStaleSummaryCitationSources(
                eq(RetrievalRecordType.summaryTypeNames()),
                eq(SummaryChunker.CITATION_METADATA_VERSION),
                eq(2),
                any(),
                any())).thenReturn(List.of(candidate(42L, "call-summary:42")));
        when(retrievalIndexService.replaySummaryCitationMetadata(42L, 42L))
                .thenReturn(SummaryCitationReplayOutcome.NO_DRAFTS);

        worker.pollAndBackfill();

        verify(chunkRepository).markSummaryCitationReplayFailure(
                org.mockito.ArgumentMatchers.eq(42L),
                org.mockito.ArgumentMatchers.eq("call-summary:42"),
                any(),
                any());
    }

    @Test
    void pollAndBackfill_ownerMismatchIsQuarantined() {
        when(chunkRepository.claimStaleSummaryCitationSources(
                eq(RetrievalRecordType.summaryTypeNames()),
                eq(SummaryChunker.CITATION_METADATA_VERSION),
                eq(2),
                any(),
                any())).thenReturn(List.of(candidate(99L, "call-summary:42")));
        when(retrievalIndexService.replaySummaryCitationMetadata(42L, 99L))
                .thenReturn(SummaryCitationReplayOutcome.QUARANTINED);
        when(chunkRepository.quarantineSummarySource(
                99L, "call-summary:42", RetrievalRecordType.summaryTypeNames(), CLAIM_TOKEN)).thenReturn(2);

        worker.pollAndBackfill();

        verify(chunkRepository).quarantineSummarySource(
                99L, "call-summary:42", RetrievalRecordType.summaryTypeNames(), CLAIM_TOKEN);
    }

    @Test
    void pollAndBackfill_unexpectedUntypedSourceIsFencedAndQuarantined() {
        when(chunkRepository.claimStaleSummaryCitationSources(
                org.mockito.ArgumentMatchers.eq(RetrievalRecordType.summaryTypeNames()),
                org.mockito.ArgumentMatchers.eq(SummaryChunker.CITATION_METADATA_VERSION),
                org.mockito.ArgumentMatchers.eq(2),
                any(),
                any())).thenReturn(List.of(candidate(42L, "77", null)));

        worker.pollAndBackfill();

        verify(chunkRepository).quarantineSummarySource(
                42L, "77", RetrievalRecordType.summaryTypeNames(), CLAIM_TOKEN);
        verify(chunkRepository, never()).markSummaryCitationReplayFailure(
                eq(42L), eq("77"), any(), eq(CLAIM_TOKEN));
        verify(retrievalIndexService, never()).replaySummaryCitationMetadata(any(), any());
    }

    private static SummaryReplayCandidate candidate(
            final Long patientId,
            final String sourceRecordId) {
        return candidate(patientId, sourceRecordId, SummarySourceKey.CALL_KIND);
    }

    private static SummaryReplayCandidate candidate(
            final Long patientId,
            final String sourceRecordId,
            final String sourceKind) {
        return new SummaryReplayCandidate() {
            @Override
            public Long getPatientId() {
                return patientId;
            }

            @Override
            public String getSourceRecordId() {
                return sourceRecordId;
            }

            @Override
            public String getSourceKind() {
                return sourceKind;
            }

            @Override
            public UUID getClaimToken() {
                return CLAIM_TOKEN;
            }
        };
    }
}
