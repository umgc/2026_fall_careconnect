package com.careconnect.service.ehr;

import com.careconnect.repository.ehr.EhrRawPayloadRepository;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.time.OffsetDateTime;

/**
 * Deletes {@code ehr_raw_payload} rows older than a configured retention period.
 * <p>
 * {@code ehr_raw_payload} holds retrieved clinical content verbatim, so it is PHI and must not
 * accumulate without limit (PR #209 and PR #216 reviews, issue #214). This is the mechanism.
 * <strong>The period is not decided here.</strong> {@code careconnect.ehr.raw-payload.retention-days}
 * defaults to {@code 0}, which means no purge: how long a verbatim payload may be kept is a HIPAA
 * policy decision belonging to the WBS 1.8 gate, and a number invented in a properties file would
 * read as if that decision had been made. Until it is set the worker says so at startup, once,
 * at WARN.
 * <p>
 * Age is measured from {@code retrieved_at}, when the source answered, not from when the row was
 * written; {@code idx_ehr_raw_payload_retrieved_at} exists for this query.
 * <p>
 * Three things done deliberately, each a defect already filed against the telemetry purge:
 * the period is constructor-injected and validated, so an unbound property cannot purge the table
 * (#102); the schedule is a cron expression rather than a delay from startup, so it does not fire
 * on every restart or drift with uptime (#104); and the delete is one bulk statement, not a
 * derived delete that loads the backlog first (#106). Two instances running it at the same moment
 * is harmless: the statement is idempotent.
 */
@Slf4j
@Component
public class EhrRawPayloadRetentionWorker {

    private final EhrRawPayloadRepository repository;
    private final int retentionDays;

    public EhrRawPayloadRetentionWorker(
            final EhrRawPayloadRepository repository,
            @Value("${careconnect.ehr.raw-payload.retention-days:0}") final int retentionDays) {
        this.repository = repository;
        this.retentionDays = retentionDays;
        if (retentionDays <= 0) {
            log.warn("EHR raw payload retention is not configured "
                    + "(careconnect.ehr.raw-payload.retention-days={}); ehr_raw_payload is PHI and "
                    + "nothing will be purged until a retention period is set (issue #214)",
                    retentionDays);
        }
    }

    @Scheduled(cron = "${careconnect.ehr.raw-payload.purge-cron:0 30 3 * * *}")
    public void purgeExpired() {
        purgeExpired(OffsetDateTime.now());
    }

    /**
     * @param now the moment to measure age from; a parameter so a test can fix it.
     * @return rows deleted, or 0 when no retention period is configured.
     */
    int purgeExpired(final OffsetDateTime now) {
        if (retentionDays <= 0) {
            return 0;
        }
        final OffsetDateTime cutoff = now.minusDays(retentionDays);
        final int deleted = repository.deleteRetrievedBefore(cutoff);
        if (deleted > 0) {
            // Count and cutoff only. Never log patient ids or anything from the payload.
            log.info("EHR raw payload retention purged {} row(s) retrieved before {}", deleted, cutoff);
        }
        return deleted;
    }
}
