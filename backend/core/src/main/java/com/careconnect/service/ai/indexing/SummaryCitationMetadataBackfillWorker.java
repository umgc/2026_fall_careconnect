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

/** Bounded, idempotent replay worker for summary chunks with stale citation metadata. */
@Service
@ConditionalOnProperty(
        name = "careconnect.ai.citation.backfill.enabled",
        havingValue = "true")
@Slf4j
public class SummaryCitationMetadataBackfillWorker {

    private final RetrievalIndexChunkRepository chunkRepository;
    private final RetrievalIndexService retrievalIndexService;
    private final int batchSize;
    private final long failureBackoffMs;

    public SummaryCitationMetadataBackfillWorker(
            final RetrievalIndexChunkRepository chunkRepository,
            final RetrievalIndexService retrievalIndexService,
            @Value("${careconnect.ai.citation.backfill.batch-size:25}") final int batchSize,
            @Value("${careconnect.ai.citation.backfill.failure-backoff-ms:300000}")
                    final long failureBackoffMs) {
        this.chunkRepository = chunkRepository;
        this.retrievalIndexService = retrievalIndexService;
        this.batchSize = Math.max(1, batchSize);
        this.failureBackoffMs = Math.min(
                Duration.ofDays(7).toMillis(),
                Math.max(1_000L, failureBackoffMs));
    }

    @Scheduled(
            fixedDelayString =
                    "${careconnect.ai.citation.backfill.poll-interval-ms:60000}")
    public void pollAndBackfill() {
        final List<SummaryReplayCandidate> candidates =
                chunkRepository.findStaleSummaryCitationSources(
                        RetrievalRecordType.summaryTypeNames(),
                        SummaryChunker.CITATION_METADATA_VERSION,
                        batchSize);
        if (candidates.isEmpty()) {
            return;
        }

        int updated = 0;
        int failed = 0;
        int quarantined = 0;
        for (final SummaryReplayCandidate candidate : candidates) {
            final String sourceId = candidate.getSourceRecordId();
            try {
                final Long summaryId = SummarySourceKey.parseCallSummaryId(sourceId)
                        .orElseThrow(() -> new IllegalArgumentException(
                                "Invalid call summary source key"));
                final SummaryCitationReplayOutcome outcome =
                        retrievalIndexService.replaySummaryCitationMetadata(
                                summaryId, candidate.getPatientId());
                if (outcome == SummaryCitationReplayOutcome.UPDATED) {
                    updated++;
                } else if (outcome == SummaryCitationReplayOutcome.NO_DRAFTS) {
                    failed++;
                    markFailureBackoff(candidate);
                } else if (outcome == SummaryCitationReplayOutcome.QUARANTINED) {
                    quarantined += chunkRepository.quarantineSummarySource(
                            candidate.getPatientId(),
                            sourceId,
                            RetrievalRecordType.summaryTypeNames());
                }
            } catch (final RuntimeException ex) {
                failed++;
                markFailureBackoff(candidate);
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

    private void markFailureBackoff(final SummaryReplayCandidate candidate) {
        try {
            chunkRepository.markSummaryCitationReplayFailure(
                    candidate.getPatientId(),
                    candidate.getSourceRecordId(),
                    RetrievalRecordType.summaryTypeNames(),
                    OffsetDateTime.now(ZoneOffset.UTC)
                            .plus(Duration.ofMillis(failureBackoffMs)));
        } catch (final RuntimeException markFailure) {
            log.warn(
                    "Unable to persist summary citation replay backoff type={}",
                    markFailure.getClass().getSimpleName());
        }
    }

}
