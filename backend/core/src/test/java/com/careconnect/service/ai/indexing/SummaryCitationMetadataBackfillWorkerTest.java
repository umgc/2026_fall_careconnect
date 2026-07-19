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
import static org.mockito.ArgumentMatchers.anyLong;
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
                chunkRepository, retrievalIndexService, 2, 60_000L, 300_000L, 8);
    }

    @Test
    void pollAndBackfill_usesBoundedBatchAndQuarantinesMalformedId() {
        when(chunkRepository.claimStaleSummaryCitationSources(
                eq(RetrievalRecordType.summaryTypeNames()),
                eq(SummaryChunker.CITATION_METADATA_VERSION),
                eq(2),
                any(),
                eq(8))).thenReturn(List.of(
                        candidate(42L, "not-a-number", 0),
                        candidate(42L, "call-summary:42", 0)));
        when(retrievalIndexService.replaySummaryCitationMetadata(
                eq(42L), eq(42L), eq(CLAIM_TOKEN), eq(300_000L)))
                .thenReturn(SummaryCitationReplayOutcome.CURRENT);
        when(chunkRepository.quarantineSummarySource(
                eq(42L), eq("not-a-number"), any(), eq(CLAIM_TOKEN), any()))
                .thenReturn(1);

        worker.pollAndBackfill();

        verify(retrievalIndexService).replaySummaryCitationMetadata(
                42L, 42L, CLAIM_TOKEN, 300_000L);
        verify(chunkRepository).quarantineSummarySource(
                eq(42L),
                eq("not-a-number"),
                eq(RetrievalRecordType.summaryTypeNames()),
                eq(CLAIM_TOKEN),
                eq("malformed_call_summary_source_key"));
        verify(chunkRepository, never()).markSummaryCitationReplayFailure(
                eq(42L), eq("not-a-number"), any(), eq(CLAIM_TOKEN));
    }

    @Test
    void pollAndBackfill_failureDoesNotBlockRemainingSources() {
        when(chunkRepository.claimStaleSummaryCitationSources(
                eq(RetrievalRecordType.summaryTypeNames()),
                eq(SummaryChunker.CITATION_METADATA_VERSION),
                eq(2),
                any(),
                eq(8))).thenReturn(List.of(
                        candidate(42L, "call-summary:41", 0),
                        candidate(42L, "call-summary:42", 0)));
        when(retrievalIndexService.replaySummaryCitationMetadata(
                eq(41L), eq(42L), eq(CLAIM_TOKEN), eq(300_000L)))
                .thenThrow(new IllegalStateException("failed"));
        when(retrievalIndexService.replaySummaryCitationMetadata(
                eq(42L), eq(42L), eq(CLAIM_TOKEN), eq(300_000L)))
                .thenReturn(SummaryCitationReplayOutcome.CURRENT);

        worker.pollAndBackfill();

        final InOrder order = inOrder(retrievalIndexService);
        order.verify(retrievalIndexService).replaySummaryCitationMetadata(
                41L, 42L, CLAIM_TOKEN, 300_000L);
        order.verify(retrievalIndexService).replaySummaryCitationMetadata(
                42L, 42L, CLAIM_TOKEN, 300_000L);
        verify(chunkRepository).markSummaryCitationReplayFailure(
                eq(42L), eq("call-summary:41"), any(), eq(CLAIM_TOKEN));
    }

    @Test
    void pollAndBackfill_secondNoOpPassDoesNotReplayAgain() {
        when(chunkRepository.claimStaleSummaryCitationSources(
                eq(RetrievalRecordType.summaryTypeNames()),
                eq(SummaryChunker.CITATION_METADATA_VERSION),
                eq(2),
                any(),
                eq(8)))
                .thenReturn(List.of(candidate(42L, "call-summary:42", 0)))
                .thenReturn(List.of());
        when(retrievalIndexService.replaySummaryCitationMetadata(
                eq(42L), eq(42L), eq(CLAIM_TOKEN), eq(300_000L)))
                .thenReturn(SummaryCitationReplayOutcome.UPDATED);

        worker.pollAndBackfill();
        worker.pollAndBackfill();

        verify(retrievalIndexService).replaySummaryCitationMetadata(
                42L, 42L, CLAIM_TOKEN, 300_000L);
        verify(chunkRepository).releaseSummaryCitationReplayClaim(
                42L, "call-summary:42", CLAIM_TOKEN);
        verify(retrievalIndexService, never()).replaySummaryCitationMetadata(
                eq(43L), anyLong(), any(), anyLong());
    }

    @Test
    void pollAndBackfill_currentCanonicalSourceOnlyReleasesClaim() {
        when(chunkRepository.claimStaleSummaryCitationSources(
                eq(RetrievalRecordType.summaryTypeNames()),
                eq(SummaryChunker.CITATION_METADATA_VERSION),
                eq(2),
                any(),
                eq(8))).thenReturn(List.of(candidate(42L, "call-summary:42", 0)));
        when(retrievalIndexService.replaySummaryCitationMetadata(
                eq(42L), eq(42L), eq(CLAIM_TOKEN), eq(300_000L)))
                .thenReturn(SummaryCitationReplayOutcome.CURRENT);

        worker.pollAndBackfill();

        verify(chunkRepository).releaseSummaryCitationReplayClaim(
                42L, "call-summary:42", CLAIM_TOKEN);
        verify(chunkRepository, never()).markSummaryCitationReplayFailure(
                eq(42L), eq("call-summary:42"), any(), eq(CLAIM_TOKEN));
        verify(chunkRepository, never()).quarantineSummarySource(
                eq(42L), eq("call-summary:42"), any(), eq(CLAIM_TOKEN), any());
    }

    @Test
    void pollAndBackfill_retryableOutcomeIsBackedOff() {
        when(chunkRepository.claimStaleSummaryCitationSources(
                eq(RetrievalRecordType.summaryTypeNames()),
                eq(SummaryChunker.CITATION_METADATA_VERSION),
                eq(2),
                any(),
                eq(8))).thenReturn(List.of(candidate(42L, "call-summary:42", 0)));
        when(retrievalIndexService.replaySummaryCitationMetadata(
                eq(42L), eq(42L), eq(CLAIM_TOKEN), eq(300_000L)))
                .thenReturn(SummaryCitationReplayOutcome.RETRYABLE);

        worker.pollAndBackfill();

        verify(chunkRepository).markSummaryCitationReplayFailure(
                eq(42L), eq("call-summary:42"), any(), eq(CLAIM_TOKEN));
    }

    @Test
    void pollAndBackfill_maxAttemptsQuarantinesTerminal() {
        when(chunkRepository.claimStaleSummaryCitationSources(
                eq(RetrievalRecordType.summaryTypeNames()),
                eq(SummaryChunker.CITATION_METADATA_VERSION),
                eq(2),
                any(),
                eq(8))).thenReturn(List.of(candidate(42L, "call-summary:42", 7)));
        when(retrievalIndexService.replaySummaryCitationMetadata(
                eq(42L), eq(42L), eq(CLAIM_TOKEN), eq(300_000L)))
                .thenReturn(SummaryCitationReplayOutcome.RETRYABLE);
        when(chunkRepository.quarantineSummarySource(
                eq(42L), eq("call-summary:42"), any(), eq(CLAIM_TOKEN), any()))
                .thenReturn(1);

        worker.pollAndBackfill();

        verify(chunkRepository).quarantineSummarySource(
                eq(42L),
                eq("call-summary:42"),
                eq(RetrievalRecordType.summaryTypeNames()),
                eq(CLAIM_TOKEN),
                eq("retryable_replay_failure_max_attempts"));
        verify(chunkRepository, never()).markSummaryCitationReplayFailure(
                eq(42L), eq("call-summary:42"), any(), eq(CLAIM_TOKEN));
    }

    @Test
    void pollAndBackfill_ownerMismatchIsQuarantined() {
        when(chunkRepository.claimStaleSummaryCitationSources(
                eq(RetrievalRecordType.summaryTypeNames()),
                eq(SummaryChunker.CITATION_METADATA_VERSION),
                eq(2),
                any(),
                eq(8))).thenReturn(List.of(candidate(99L, "call-summary:42", 0)));
        when(retrievalIndexService.replaySummaryCitationMetadata(
                eq(42L), eq(99L), eq(CLAIM_TOKEN), eq(300_000L)))
                .thenReturn(SummaryCitationReplayOutcome.TERMINAL_QUARANTINED);
        when(chunkRepository.quarantineSummarySource(
                eq(99L),
                eq("call-summary:42"),
                eq(RetrievalRecordType.summaryTypeNames()),
                eq(CLAIM_TOKEN),
                eq("terminal_replay_failure"))).thenReturn(2);

        worker.pollAndBackfill();

        verify(chunkRepository).quarantineSummarySource(
                eq(99L),
                eq("call-summary:42"),
                eq(RetrievalRecordType.summaryTypeNames()),
                eq(CLAIM_TOKEN),
                eq("terminal_replay_failure"));
    }

    @Test
    void pollAndBackfill_unexpectedUntypedSourceIsFencedAndQuarantined() {
        when(chunkRepository.claimStaleSummaryCitationSources(
                eq(RetrievalRecordType.summaryTypeNames()),
                eq(SummaryChunker.CITATION_METADATA_VERSION),
                eq(2),
                any(),
                eq(8))).thenReturn(List.of(candidate(42L, "77", null, 0)));

        worker.pollAndBackfill();

        verify(chunkRepository).quarantineSummarySource(
                eq(42L),
                eq("77"),
                eq(RetrievalRecordType.summaryTypeNames()),
                eq(CLAIM_TOKEN),
                eq("malformed_or_legacy_source_key"));
        verify(chunkRepository, never()).markSummaryCitationReplayFailure(
                eq(42L), eq("77"), any(), eq(CLAIM_TOKEN));
        verify(retrievalIndexService, never()).replaySummaryCitationMetadata(
                any(), any(), any(), anyLong());
    }

    private static SummaryReplayCandidate candidate(
            final Long patientId,
            final String sourceRecordId,
            final int attempts) {
        return candidate(patientId, sourceRecordId, SummarySourceKey.CALL_KIND, attempts);
    }

    private static SummaryReplayCandidate candidate(
            final Long patientId,
            final String sourceRecordId,
            final String sourceKind,
            final int attempts) {
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

            @Override
            public Integer getAttempts() {
                return attempts;
            }
        };
    }
}
