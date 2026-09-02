package com.careconnect.service;

import com.careconnect.websocket.CallNotificationHandler;

import java.util.Map;

import lombok.RequiredArgsConstructor;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * Reclaims expired call-cleanup leases so Chime meetings cannot be orphaned.
 */
@Component
@RequiredArgsConstructor
public class CallTerminationReconciler {

    private static final Logger log =
            LoggerFactory.getLogger(CallTerminationReconciler.class);
    private static final int BATCH_SIZE = 25;

    private final CallSessionService callSessionService;
    private final CallTerminationExecutor callTerminationExecutor;
    private final CallNotificationHandler callNotificationHandler;

    @Scheduled(
            fixedDelayString =
                    "${careconnect.call.termination-reconcile-interval-ms:30000}")
    public void reconcileDueTerminations() {
        for (final Long sessionId : callSessionService.findDueTerminationIds(BATCH_SIZE)) {
            try {
                reconcile(sessionId);
            } catch (RuntimeException failure) {
                log.error(
                        "Scheduled call termination item failed for sessionId={}",
                        sessionId,
                        failure);
            }
        }
    }

    void reconcile(final Long sessionId) {
        final CallSessionService.TerminationClaim claim =
                callSessionService.claimDueTermination(sessionId);
        if (claim == null) {
            return;
        }
        if (!callTerminationExecutor.execute(claim.callId(), null, claim.claimId())) {
            return;
        }
        claim.notifyUserIds().stream()
                .map(String::valueOf)
                .forEach(userId -> callNotificationHandler.sendNotificationToUser(
                        userId,
                        Map.of(
                                "type", "call-ended",
                                "callId", claim.callId(),
                                "endedBy", "SYSTEM",
                                "status", "ended")));
    }
}
