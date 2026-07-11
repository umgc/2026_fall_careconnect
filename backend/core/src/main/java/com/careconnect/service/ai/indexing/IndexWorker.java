package com.careconnect.service.ai.indexing;

import com.careconnect.indexing.IndexingEventType;
import com.careconnect.indexing.SummaryCreatedPayload;
import com.careconnect.indexing.TranscriptIndexedPayload;
import com.careconnect.model.indexing.IndexingOutboxRow;
import com.careconnect.repository.indexing.IndexingOutboxRepository;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.List;

/**
 * Polls {@code indexing_outbox} and drives {@link RetrievalIndexService} (Task 4.1).
 *
 * <p>MVP transport: process outbox rows in-process (same pattern as {@code EvvOutboxProcessor}).
 * Rows are claimed with {@code FOR UPDATE SKIP LOCKED} so multiple ECS tasks do not process
 * the same outbox row concurrently. A later change can publish to SNS/SQS and keep this
 * service as the message handler.
 */
@Service
@ConditionalOnProperty(
        name = "careconnect.indexing.worker.enabled",
        havingValue = "true",
        matchIfMissing = true)
public class IndexWorker {

    private static final Logger log = LoggerFactory.getLogger(IndexWorker.class);

    private final IndexingOutboxRepository outboxRepository;
    private final RetrievalIndexService retrievalIndexService;
    private final ObjectMapper objectMapper;

    private final int batchSize;
    private final int maxAttempts;

    public IndexWorker(
            final IndexingOutboxRepository outboxRepository,
            final RetrievalIndexService retrievalIndexService,
            final ObjectMapper objectMapper,
            @Value("${careconnect.indexing.outbox.batch-size:25}") final int batchSize,
            @Value("${careconnect.indexing.outbox.max-attempts:5}") final int maxAttempts) {
        this.outboxRepository = outboxRepository;
        this.retrievalIndexService = retrievalIndexService;
        this.objectMapper = objectMapper;
        this.batchSize = Math.max(1, batchSize);
        this.maxAttempts = Math.max(1, maxAttempts);
    }

    /**
     * Claims a batch of unprocessed rows and processes each. Runs in one transaction so
     * {@code FOR UPDATE SKIP LOCKED} holds until the poll cycle completes.
     */
    @Scheduled(fixedDelayString = "${careconnect.indexing.outbox.poll-interval-ms:15000}")
    @Transactional
    public void pollAndProcess() {
        final List<IndexingOutboxRow> pending =
                outboxRepository.claimUnprocessedForPolling(batchSize);
        if (pending.isEmpty()) {
            return;
        }
        log.info("IndexWorker processing {} outbox row(s)", pending.size());
        for (final IndexingOutboxRow row : pending) {
            processRow(row);
        }
    }

    void processRow(final IndexingOutboxRow row) {
        if (row == null || row.getId() == null) {
            return;
        }
        final int attempts = row.getAttemptCount() == null ? 0 : row.getAttemptCount();
        if (attempts >= maxAttempts) {
            row.setProcessedAt(LocalDateTime.now());
            row.setLastError(truncate(
                    "Exceeded max attempts (" + maxAttempts + "); lastError=" + row.getLastError()));
            outboxRepository.save(row);
            log.error("IndexWorker dead-lettered outboxId={} eventType={} after {} attempts",
                    row.getId(), row.getEventType(), attempts);
            return;
        }

        try {
            final int written = dispatch(row);
            row.setAttemptCount(attempts + 1);
            row.setProcessedAt(LocalDateTime.now());
            row.setLastError(null);
            outboxRepository.save(row);
            log.info("IndexWorker processed outboxId={} eventType={} chunksWritten={}",
                    row.getId(), row.getEventType(), written);
        } catch (final IndexingDeferredException ex) {
            // Leave unprocessed and do not burn attempt budget (e.g. waiting for patientId).
            log.warn("IndexWorker deferring outboxId={} eventType={}: {}",
                    row.getId(), row.getEventType(), ex.getMessage());
        } catch (final Exception ex) {
            final int nextAttempts = attempts + 1;
            row.setAttemptCount(nextAttempts);
            row.setLastError(truncate(ex.getMessage()));
            if (nextAttempts >= maxAttempts) {
                row.setProcessedAt(LocalDateTime.now());
                log.error("IndexWorker dead-lettered outboxId={} eventType={} after {} attempts: {}",
                        row.getId(), row.getEventType(), nextAttempts, ex.getMessage());
            } else {
                log.error("IndexWorker failed outboxId={} eventType={} attempt={}: {}",
                        row.getId(), row.getEventType(), nextAttempts, ex.getMessage());
            }
            outboxRepository.save(row);
        }
    }

    private int dispatch(final IndexingOutboxRow row) throws Exception {
        final JsonNode envelope = objectMapper.readTree(row.getPayloadJson());
        final String eventType = firstNonBlank(
                textOrNull(envelope, "eventType"),
                row.getEventType());
        final JsonNode payloadNode = envelope.path("payload");
        if (payloadNode.isMissingNode() || payloadNode.isNull()) {
            throw new IllegalArgumentException("Outbox envelope missing payload for id=" + row.getId());
        }

        if (IndexingEventType.SUMMARY_CREATED.equals(eventType)) {
            final SummaryCreatedPayload payload =
                    objectMapper.treeToValue(payloadNode, SummaryCreatedPayload.class);
            return retrievalIndexService.ingestSummaryCreated(payload);
        }
        if (IndexingEventType.TRANSCRIPT_INDEXED.equals(eventType)) {
            final TranscriptIndexedPayload payload =
                    objectMapper.treeToValue(payloadNode, TranscriptIndexedPayload.class);
            return retrievalIndexService.ingestTranscriptIndexed(payload);
        }

        // Unknown types: mark processed so the poller does not spin forever.
        log.warn("IndexWorker ignoring unsupported eventType={} outboxId={}",
                eventType, row.getId());
        return 0;
    }

    private static String textOrNull(final JsonNode node, final String field) {
        if (node == null) {
            return null;
        }
        final JsonNode child = node.get(field);
        return child == null || child.isNull() ? null : child.asText(null);
    }

    private static String firstNonBlank(final String a, final String b) {
        if (a != null && !a.isBlank()) {
            return a;
        }
        return b;
    }

    private static String truncate(final String message) {
        if (message == null) {
            return null;
        }
        return message.length() > 500 ? message.substring(0, 500) : message;
    }
}
