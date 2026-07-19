package com.careconnect.service.ai.indexing;

import com.careconnect.repository.retrieval.RetrievalIndexChunkRepository;
import com.careconnect.service.ai.indexing.chunker.SummaryChunker;
import com.careconnect.service.ai.retrieval.RetrievalRecordType;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

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

    public SummaryCitationMetadataBackfillWorker(
            final RetrievalIndexChunkRepository chunkRepository,
            final RetrievalIndexService retrievalIndexService,
            @Value("${careconnect.ai.citation.backfill.batch-size:25}") final int batchSize) {
        this.chunkRepository = chunkRepository;
        this.retrievalIndexService = retrievalIndexService;
        this.batchSize = Math.max(1, batchSize);
    }

    @Scheduled(
            fixedDelayString =
                    "${careconnect.ai.citation.backfill.poll-interval-ms:60000}")
    public void pollAndBackfill() {
        final List<String> sourceIds =
                chunkRepository.findStaleSummaryCitationSourceIds(
                        RetrievalRecordType.summaryTypeNames(),
                        SummaryChunker.CITATION_METADATA_VERSION,
                        batchSize);
        if (sourceIds.isEmpty()) {
            return;
        }

        int rebuilt = 0;
        int failed = 0;
        for (final String sourceId : sourceIds) {
            try {
                rebuilt += retrievalIndexService.replaySummaryCitationMetadata(
                        Long.valueOf(sourceId));
            } catch (final RuntimeException ex) {
                failed++;
                log.warn(
                        "Summary citation metadata replay failed type={}",
                        ex.getClass().getSimpleName());
            }
        }
        log.info(
                "Summary citation metadata replay processed {} source(s), wrote {} chunk(s), failed {}",
                sourceIds.size(),
                rebuilt,
                failed);
    }
}
