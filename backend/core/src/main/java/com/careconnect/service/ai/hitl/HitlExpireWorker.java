package com.careconnect.service.ai.hitl;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * Periodically expires past-due PENDING_REVIEW holds that nobody has polled.
 */
@Component
@ConditionalOnProperty(
        name = "careconnect.ai.hitl.enabled",
        havingValue = "true",
        matchIfMissing = true)
public class HitlExpireWorker {

    private static final Logger log = LoggerFactory.getLogger(HitlExpireWorker.class);
    private static final int MAX_DRAIN_PASSES = 10;

    private final HitlService hitlService;
    private final int batchSize;

    public HitlExpireWorker(
            final HitlService hitlService,
            @Value("${careconnect.ai.hitl.expire-batch-size:100}") final int batchSize) {
        this.hitlService = hitlService;
        this.batchSize = Math.max(1, batchSize);
    }

    @Scheduled(fixedDelayString = "${careconnect.ai.hitl.expire-scan-ms:300000}")
    public void expireDueHolds() {
        int total = 0;
        for (int pass = 0; pass < MAX_DRAIN_PASSES; pass++) {
            final int expired = hitlService.expireDueHolds(batchSize);
            total += expired;
            if (expired < batchSize) {
                break;
            }
        }
        if (total > 0) {
            log.info("HITL expire scan transitioned {} held item(s) to EXPIRED", total);
        }
    }
}
