package com.careconnect.service.ai.indexing;

import com.careconnect.repository.retrieval.RetrievalIndexChunkRepository;
import com.careconnect.repository.retrieval.RetrievalIndexChunkRepository.SummaryReplayCandidate;
import com.careconnect.service.ai.indexing.chunker.SummaryChunker;
import com.careconnect.service.ai.retrieval.RetrievalRecordType;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

import java.time.Duration;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.List;

/**
 * Bounded, idempotent replay worker for summary chunks with stale citation metadata.
 */
@Service
@ConditionalOnProperty(
        name = "careconnect.ai.citation.backfill.enabled",
        havingValue = "true")
@Slf4j
public class SummaryCitationMetadataBackfillWorker {

    static final int DEFAULT_MAX_ATTEMPTS = 8;

    private final RetrievalIndexChunkRepository chunkRepository;
    private final RetrievalIndexService retrievalIndexService;
    private final int batchSize;
    private final long failureBackoffMs;
    private final long claimLeaseMs;
    private final int maxAttempts;

    public SummaryCitationMetadataBackfillWorker(
            final RetrievalIndexChunkRepository chunkRepository,
            final RetrievalIndexService retrievalIndexService,
            @Value("${careconnect.ai.citation.backfill.batch-size:25}") final int batchSize,
            @Value("${careconnect.ai.citation.backfill.failure-backoff-ms:300000}") final long failureBackoffMs,
            @Value("${careconnect.ai.citation.backfill.claim-lease-ms:300000}") final long claimLeaseMs,
            @Value("${careconnect.ai.citation.backfill.max-attempts:8}") final int maxAttempts) {
        this.chunkRepository = chunkRepository;
        this.retrievalIndexService = retrievalIndexService;
        this.batchSize = Math.max(1, batchSize);
        this.failureBackoffMs = Math.min(
                Duration.ofDays(7).toMillis(),
                Math.max(1_000L, failureBackoffMs));
        this.claimLeaseMs = Math.min(
                Duration.ofHours(1).toMillis(),
                Math.max(10_000L, claimLeaseMs));
        this.maxAttempts = Math.max(1, maxAttempts);
    }

    @Scheduled(
            fixedDelayString =
                    "${careconnect.ai.citation.backfill.poll-interval-ms:60000}")
    public void pollAndBackfill() {
        final List<SummaryReplayCandidate> candidates =
                chunkRepository.claimStaleSummaryCitationSources(
                        RetrievalRecordType.summaryTypeNames(),
                        SummaryChunker.CITATION_METADATA_VERSION,
                        batchSize,
                        OffsetDateTime.now(ZoneOffset.UTC)
                                .plus(Duration.ofMillis(claimLeaseMs)),
                        maxAttempts);
        if (candidates.isEmpty()) {
            return;
        }

        int updated = 0;
        int failed = 0;
        int quarantined = 0;
        for (final SummaryReplayCandidate candidate : candidates) {
            final String sourceId = candidate.getSourceRecordId();
            try {
                if (!SummarySourceKey.CALL_KIND.equals(candidate.getSourceKind())
                        || SummarySourceKey.isLegacyNumeric(sourceId)) {
                    quarantined += quarantine(
                            candidate, "malformed_or_legacy_source_key");
                    continue;
                }
                final Long summaryId = SummarySourceKey.parseCallSummaryId(sourceId)
                        .orElse(null);
                if (summaryId == null) {
                    quarantined += quarantine(
                            candidate, "malformed_call_summary_source_key");
                    continue;
                }
                final SummaryCitationReplayOutcome outcome =
                        retrievalIndexService.replaySummaryCitationMetadata(
                                summaryId,
                                candidate.getPatientId(),
                                candidate.getClaimToken(),
                                claimLeaseMs);
                if (outcome == SummaryCitationReplayOutcome.UPDATED) {
                    updated++;
                    releaseClaim(candidate);
                } else if (outcome == SummaryCitationReplayOutcome.RETRYABLE) {
                    failed++;
                    markFailureOrQuarantine(candidate, "retryable_replay_failure");
                } else if (outcome == SummaryCitationReplayOutcome.TERMINAL_QUARANTINED) {
                    quarantined += quarantine(
                            candidate, "terminal_replay_failure");
                } else if (outcome == SummaryCitationReplayOutcome.BUSY) {
                    failed++;
                    markFailureBackoff(candidate);
                } else {
                    releaseClaim(candidate);
                }
            } catch (final RuntimeException ex) {
                failed++;
                markFailureOrQuarantine(candidate, "unexpected_replay_exception");
                log.warn(
                        "Summary citation metadata replay failed type={}",
                        ex.getClass().getSimpleName());
            }
        }
        log.info(
                "Summary citation metadata replay processed {} source(s), updated {}, quarantined {}, failed {}",
                candidates.size(),
                updated,
                quarantined,
                failed);
    }

    private void markFailureOrQuarantine(
            final SummaryReplayCandidate candidate, final String reason) {
        final int priorAttempts = candidate.getAttempts() == null ? 0 : candidate.getAttempts();
        if (priorAttempts + 1 >= maxAttempts) {
            quarantine(candidate, reason + "_max_attempts");
            return;
        }
        markFailureBackoff(candidate);
    }

    private int markFailureBackoff(final SummaryReplayCandidate candidate) {
        try {
            return chunkRepository.markSummaryCitationReplayFailure(
                    candidate.getPatientId(),
                    candidate.getSourceRecordId(),
                    OffsetDateTime.now(ZoneOffset.UTC)
                            .plus(Duration.ofMillis(failureBackoffMs)),
                    candidate.getClaimToken());
        } catch (final RuntimeException markFailure) {
            log.warn(
                    "Unable to persist summary citation replay backoff type={}",
                    markFailure.getClass().getSimpleName());
            return 0;
        }
    }

    private int quarantine(final SummaryReplayCandidate candidate, final String reason) {
        return chunkRepository.quarantineSummarySource(
                candidate.getPatientId(),
                candidate.getSourceRecordId(),
                RetrievalRecordType.summaryTypeNames(),
                candidate.getClaimToken(),
                reason);
    }

    private void releaseClaim(final SummaryReplayCandidate candidate) {
        chunkRepository.releaseSummaryCitationReplayClaim(
                candidate.getPatientId(),
                candidate.getSourceRecordId(),
                candidate.getClaimToken());
    }
}
