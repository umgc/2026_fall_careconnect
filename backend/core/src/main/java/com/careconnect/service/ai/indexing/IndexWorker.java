package com.careconnect.service.ai.indexing;

import com.careconnect.indexing.ClinicalNoteIndexedPayload;
import com.careconnect.indexing.DocumentIndexedPayload;
import com.careconnect.indexing.IndexingEventType;
import com.careconnect.indexing.MailpieceIndexedPayload;
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
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

import java.time.LocalDateTime;
import java.util.List;

/**
 * Polls {@code indexing_outbox} and drives {@link RetrievalIndexService} (Task 4.1).
 * This is the canonical, production indexing path — covers CALL_SUMMARY /
 * VISIT_SUMMARY, TRANSCRIPT_SEGMENT, and USPS_MAIL as their source events
 * land in the outbox. See {@link com.careconnect.service.ai.RetrievalIndexingService}
 * for the separate, synchronous MEDICATION/TASK/VITAL_SIGN indexer — the two
 * cover disjoint record types and both write {@code retrieval_index_chunk};
 * do not add a record type to both paths.
 *
 * <p>MVP transport: process outbox rows in-process (same pattern as {@code EvvOutboxProcessor}).
 * Claim and per-row work run in <em>separate</em> transactions so a deferred/failed ingest
 * cannot mark the batch rollback-only and undo earlier successes. Rows are claimed with
 * {@code FOR UPDATE SKIP LOCKED} and a durable {@code claimed_at} lease so multiple ECS
 * tasks do not process the same outbox row after the claim transaction commits. Default
 * lease is 10 minutes to cover Titan embedding latency after ingest commits. A later
 * change can publish to SNS/SQS and keep this service as the message handler.
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
    private final TransactionTemplate transactionTemplate;

    private final int batchSize;
    private final int maxAttempts;
    private final int claimLeaseMinutes;
    private final int noBurnParkHours;

    public IndexWorker(
            final IndexingOutboxRepository outboxRepository,
            final RetrievalIndexService retrievalIndexService,
            final ObjectMapper objectMapper,
            final PlatformTransactionManager transactionManager,
            @Value("${careconnect.indexing.outbox.batch-size:25}") final int batchSize,
            @Value("${careconnect.indexing.outbox.max-attempts:5}") final int maxAttempts,
            @Value("${careconnect.indexing.outbox.claim-lease-minutes:10}") final int claimLeaseMinutes,
            @Value("${careconnect.indexing.outbox.no-burn-park-hours:6}") final int noBurnParkHours) {
        this.outboxRepository = outboxRepository;
        this.retrievalIndexService = retrievalIndexService;
        this.objectMapper = objectMapper;
        this.transactionTemplate = new TransactionTemplate(transactionManager);
        this.batchSize = Math.max(1, batchSize);
        this.maxAttempts = Math.max(1, maxAttempts);
        this.claimLeaseMinutes = Math.max(1, claimLeaseMinutes);
        this.noBurnParkHours = Math.max(1, noBurnParkHours);
    }

    /**
     * Claims a batch of unprocessed rows in one short transaction (lock + lease), then
     * processes each row with ingest and outbox status updates in separate transactions.
     */
    @Scheduled(fixedDelayString = "${careconnect.indexing.outbox.poll-interval-ms:15000}")
    public void pollAndProcess() {
        final List<IndexingOutboxRow> pending = transactionTemplate.execute(status -> {
            final List<IndexingOutboxRow> rows =
                    outboxRepository.claimUnprocessedForPolling(batchSize, claimLeaseMinutes);
            final LocalDateTime claimedAt = LocalDateTime.now();
            for (final IndexingOutboxRow row : rows) {
                row.setClaimedAt(claimedAt);
            }
            return outboxRepository.saveAll(rows);
        });
        if (pending == null || pending.isEmpty()) {
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
            transactionTemplate.executeWithoutResult(status -> deadLetterExceededMax(row, attempts));
            return;
        }

        try {
            final int written = transactionTemplate.execute(status -> dispatch(row));
            transactionTemplate.executeWithoutResult(status -> markProcessed(row, attempts, written));
        } catch (final RuntimeException ex) {
            final Throwable root = rootCause(ex);
            transactionTemplate.executeWithoutResult(status -> {
                if (root instanceof IndexingDeferredException deferred && !deferred.burnsAttempt()) {
                    releaseClaimWithoutBurn(row, deferred.getMessage());
                } else if (root instanceof IndexingDeferredException) {
                    recordDeferOrDeadLetter(row, attempts, root.getMessage());
                } else {
                    recordFailureOrDeadLetter(row, attempts, root.getMessage());
                }
            });
        }
    }

    private void markProcessed(
            final IndexingOutboxRow row, final int attempts, final Integer written) {
        row.setAttemptCount(attempts + 1);
        row.setProcessedAt(LocalDateTime.now());
        row.setClaimedAt(null);
        row.setLastError(null);
        outboxRepository.save(row);
        log.info("IndexWorker processed outboxId={} eventType={} chunksWritten={}",
                row.getId(), row.getEventType(), written == null ? 0 : written);
    }

    private void deadLetterExceededMax(final IndexingOutboxRow row, final int attempts) {
        row.setProcessedAt(LocalDateTime.now());
        row.setClaimedAt(null);
        row.setLastError(truncate(
                "Exceeded max attempts (" + maxAttempts + "); lastError=" + row.getLastError()));
        outboxRepository.save(row);
        log.error("IndexWorker dead-lettered outboxId={} eventType={} after {} attempts",
                row.getId(), row.getEventType(), attempts);
    }

    /**
     * Known-unimplemented or temporarily unblockable work: leave unprocessed without burning
     * attempt budget. Sets {@code claimed_at} into the future so the claim query skips the row
     * for {@code no-burn-park-hours} (default 6h) instead of reclaiming every poll (~15s) or
     * every short lease window. Examples: missing authoritative patient scope / hash mismatch
     * that should wait for a republish rather than dead-letter immediately.
     */
    private void releaseClaimWithoutBurn(final IndexingOutboxRow row, final String message) {
        row.setClaimedAt(LocalDateTime.now().plusHours(noBurnParkHours));
        row.setLastError(truncate(message));
        outboxRepository.save(row);
        log.warn(
                "IndexWorker parking outboxId={} eventType={} for {}h (no attempt burn): {}",
                row.getId(), row.getEventType(), noBurnParkHours, message);
    }

    /**
     * Deferred rows stay unprocessed but burn attempt budget so they eventually dead-letter.
     * Intermediate deferrals call {@link #refreshSoftLease} — not the no-burn park —
     * so retries wait the normal claim-lease window (default 10m), not ~15s polls.
     * Dead-letter clears the lease.
     */
    private void recordDeferOrDeadLetter(
            final IndexingOutboxRow row, final int attempts, final String message) {
        final int nextAttempts = attempts + 1;
        row.setAttemptCount(nextAttempts);
        row.setLastError(truncate(message));
        if (nextAttempts >= maxAttempts) {
            row.setClaimedAt(null);
            row.setProcessedAt(LocalDateTime.now());
            log.error("IndexWorker dead-lettered deferred outboxId={} eventType={} after {} attempts: {}",
                    row.getId(), row.getEventType(), nextAttempts, message);
        } else {
            refreshSoftLease(row);
            log.warn("IndexWorker deferring outboxId={} eventType={} attempt={}/{} (lease ~{}m): {}",
                    row.getId(), row.getEventType(), nextAttempts, maxAttempts,
                    claimLeaseMinutes, message);
        }
        outboxRepository.save(row);
    }

    private void recordFailureOrDeadLetter(
            final IndexingOutboxRow row, final int attempts, final String message) {
        final int nextAttempts = attempts + 1;
        row.setAttemptCount(nextAttempts);
        row.setLastError(truncate(message));
        if (nextAttempts >= maxAttempts) {
            row.setClaimedAt(null);
            row.setProcessedAt(LocalDateTime.now());
            log.error("IndexWorker dead-lettered outboxId={} eventType={} after {} attempts: {}",
                    row.getId(), row.getEventType(), nextAttempts, message);
        } else {
            refreshSoftLease(row);
            log.error("IndexWorker failed outboxId={} eventType={} attempt={} (lease ~{}m): {}",
                    row.getId(), row.getEventType(), nextAttempts, claimLeaseMinutes, message);
        }
        outboxRepository.save(row);
    }

    /**
     * Soft lease: stamp {@code claimed_at = now()}. The claim query only reclaims when
     * {@code claimed_at < NOW() - make_interval(mins => claimLeaseMinutes)}, so setting
     * {@code now()} (not null) starts a fresh lease window — typically 10 minutes — and
     * does <em>not</em> allow reclaim on the next 15s poll. This is intentionally shorter
     * than {@link #releaseClaimWithoutBurn}'s multi-hour park.
     */
    private void refreshSoftLease(final IndexingOutboxRow row) {
        row.setClaimedAt(LocalDateTime.now());
    }

    private int dispatch(final IndexingOutboxRow row) {
        final JsonNode envelope;
        try {
            envelope = objectMapper.readTree(row.getPayloadJson());
        } catch (final Exception ex) {
            throw new IllegalArgumentException(
                    "Invalid outbox payload JSON for id=" + row.getId() + ": " + ex.getMessage(), ex);
        }
        final String eventType = firstNonBlank(
                textOrNull(envelope, "eventType"),
                row.getEventType());
        final JsonNode payloadNode = envelope.path("payload");
        if (payloadNode.isMissingNode() || payloadNode.isNull()) {
            throw new IllegalArgumentException("Outbox envelope missing payload for id=" + row.getId());
        }

        try {
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
            if (IndexingEventType.MAILPIECE_INDEXED.equals(eventType)) {
                final MailpieceIndexedPayload payload =
                        objectMapper.treeToValue(payloadNode, MailpieceIndexedPayload.class);
                return retrievalIndexService.ingestMailpieceIndexed(payload);
            }
            if (IndexingEventType.CLINICAL_NOTE_INDEXED.equals(eventType)) {
                final ClinicalNoteIndexedPayload payload =
                        objectMapper.treeToValue(payloadNode, ClinicalNoteIndexedPayload.class);
                return retrievalIndexService.ingestClinicalNoteIndexed(payload);
            }
            if (IndexingEventType.DOCUMENT_INDEXED.equals(eventType)) {
                final DocumentIndexedPayload payload =
                        objectMapper.treeToValue(payloadNode, DocumentIndexedPayload.class);
                return retrievalIndexService.ingestDocumentIndexed(payload);
            }
        } catch (final IndexingDeferredException | IllegalArgumentException | IllegalStateException ex) {
            throw ex;
        } catch (final Exception ex) {
            throw new IllegalStateException(
                    "Failed to dispatch outboxId=" + row.getId() + " eventType=" + eventType
                            + ": " + ex.getMessage(),
                    ex);
        }

        // Unknown types: mark processed so the poller does not spin forever.
        log.warn("IndexWorker ignoring unsupported eventType={} outboxId={}",
                eventType, row.getId());
        return 0;
    }

    private static Throwable rootCause(final Throwable ex) {
        for (Throwable current = ex; current != null; current = current.getCause()) {
            if (current instanceof IndexingDeferredException) {
                return current;
            }
            if (current.getCause() == current) {
                break;
            }
        }
        Throwable current = ex;
        while (current.getCause() != null && current.getCause() != current) {
            current = current.getCause();
        }
        return current;
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
