package com.careconnect.service.evv;

import com.careconnect.model.evv.EvvRecord;
import com.careconnect.repository.evv.EvvRecordRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.Map;

/**
 * Scheduled outbox processor that drives the transactional outbox pattern for EVV submissions.
 * <p>
 * Every {@code careconnect.evv.outbox.poll-interval-ms} milliseconds (default 30 s) this service
 * queries {@code evv_outbox} for rows in {@code READY} status with fewer than 3 attempts and
 * passes each corresponding {@link EvvRecord} through
 * {@link EvvSubmissionService#submitRecord(EvvRecord, Long)}.
 * <p>
 * On success the outbox row is marked {@code SENT}; on failure it is marked {@code FAILED} and the
 * attempt counter is incremented. Rows that reach 3 failed attempts are excluded from future polls.
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class EvvOutboxProcessor {

    /**
     * Actor ID used in audit log entries created by automated submissions.
     */
    private static final Long SYSTEM_ACTOR_ID = 0L;
    /**
     * Maximum outbox rows processed in a single poll cycle.
     */
    private static final int BATCH_SIZE = 50;
    private final EvvOutboxService outboxService;
    private final EvvSubmissionService submissionService;
    private final EvvRecordRepository evvRecordRepository;

    private static String truncate(String msg) {
        return (msg != null && msg.length() > 500) ? msg.substring(0, 500) : msg;
    }

    @Scheduled(fixedDelayString = "${careconnect.evv.outbox.poll-interval-ms:30000}")
    public void processOutbox() {
        List<Map<String, Object>> pending = outboxService.fetchPending(BATCH_SIZE);
        if (pending.isEmpty()) {
            return;
        }

        log.info("[EVV-Outbox] Processing {} pending outbox row(s)", pending.size());

        for (Map<String, Object> row : pending) {
            Long outboxId = ((Number) row.get("id")).longValue();
            Long recordId = ((Number) row.get("evv_record_id")).longValue();

            try {
                EvvRecord record = evvRecordRepository.findByIdWithPatient(recordId)
                        .orElseThrow(() -> new IllegalArgumentException(
                                "EVV record not found: " + recordId));

                submissionService.submitRecord(record, SYSTEM_ACTOR_ID);
                outboxService.markSent(outboxId);
                log.info("[EVV-Outbox] Successfully submitted outbox row {} (record {})",
                        outboxId, recordId);

            } catch (Exception e) {
                log.error("[EVV-Outbox] Failed to process outbox row {} (record {}): {}",
                        outboxId, recordId, e.getMessage());
                outboxService.markFailed(outboxId, truncate(e.getMessage()));
            }
        }
    }
}
