package com.careconnect.service.security;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import lombok.extern.slf4j.Slf4j;

import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;
import java.time.LocalDateTime;
import java.time.temporal.ChronoUnit;

@Service
@Slf4j
public class LangChainGovernanceService {

    // Request limits
    private static final int MAX_REQUESTS_PER_MINUTE = 10;
    private static final int MAX_REQUESTS_PER_HOUR = 60;
    private static final int MAX_MESSAGE_LENGTH = 4000;
    // Rate limiting - track requests per user
    private final ConcurrentHashMap<Long, UserRequestTracker> userRequestTrackers = new ConcurrentHashMap<>();
    @Autowired
    private SecurityAuditService securityAuditService;

    public GovernanceResult validateRequest(Long userId, String conversationId, String message) {
        // Message length check
        if (message != null && message.length() > MAX_MESSAGE_LENGTH) {
            securityAuditService.logGovernanceAction(userId, conversationId, "MESSAGE_TOO_LONG",
                    "Message length: " + message.length() + " exceeds limit: " + MAX_MESSAGE_LENGTH);
            return new GovernanceResult(false, "Message too long", "REJECT_MESSAGE_LENGTH");
        }

        // Rate limiting check
        UserRequestTracker tracker = userRequestTrackers.computeIfAbsent(userId, k -> new UserRequestTracker());

        if (!tracker.allowRequest()) {
            securityAuditService.logGovernanceAction(userId, conversationId, "RATE_LIMIT_EXCEEDED",
                    "Requests this minute: " + tracker.getRequestsThisMinute() + ", this hour: " + tracker.getRequestsThisHour());
            return new GovernanceResult(false, "Rate limit exceeded", "RATE_LIMIT");
        }

        // Log successful validation
        securityAuditService.logGovernanceAction(userId, conversationId, "REQUEST_VALIDATED",
                "Message length: " + (message != null ? message.length() : 0) + ", requests this minute: " + tracker.getRequestsThisMinute());

        return new GovernanceResult(true, "Request approved", "ALLOW");
    }

    public GovernanceResult validateModelUsage(Long userId, String conversationId, String modelName) {
        // Model-specific governance rules
        if (modelName != null && modelName.toLowerCase().contains("gpt-4")) {
            // More restrictive for advanced models
            UserRequestTracker tracker = userRequestTrackers.get(userId);
            if (tracker != null && tracker.getRequestsThisHour() > 20) {
                securityAuditService.logGovernanceAction(userId, conversationId, "ADVANCED_MODEL_LIMIT",
                        "GPT-4 usage limited to 20 requests per hour");
                return new GovernanceResult(false, "Advanced model usage limit reached", "LIMIT_ADVANCED_MODEL");
            }
        }

        return new GovernanceResult(true, "Model usage approved", "ALLOW_MODEL");
    }

    public void cleanupOldTrackers() {
        // Clean up trackers older than 2 hours to prevent memory leaks
        LocalDateTime cutoff = LocalDateTime.now().minusHours(2);
        userRequestTrackers.entrySet().removeIf(entry -> {
            UserRequestTracker tracker = entry.getValue();
            LocalDateTime lastActivity = tracker.lastMinuteReset.isAfter(tracker.lastHourReset)
                    ? tracker.lastMinuteReset : tracker.lastHourReset;
            return lastActivity.isBefore(cutoff);
        });
    }

    @Scheduled(fixedRateString = "${careconnect.security.governance.cleanup-interval-ms:900000}")
    public void scheduledTrackerCleanup() {
        int before = userRequestTrackers.size();
        cleanupOldTrackers();
        int after = userRequestTrackers.size();
        if (after < before) {
            log.debug("Governance tracker cleanup: {} -> {}", before, after);
        }
    }

    private static class UserRequestTracker {
        private final AtomicInteger requestsThisMinute = new AtomicInteger(0);
        private final AtomicInteger requestsThisHour = new AtomicInteger(0);
        private LocalDateTime lastMinuteReset = LocalDateTime.now();
        private LocalDateTime lastHourReset = LocalDateTime.now();

        public synchronized boolean allowRequest() {
            LocalDateTime now = LocalDateTime.now();

            // Reset minute counter if needed
            if (ChronoUnit.MINUTES.between(lastMinuteReset, now) >= 1) {
                requestsThisMinute.set(0);
                lastMinuteReset = now;
            }

            // Reset hour counter if needed
            if (ChronoUnit.HOURS.between(lastHourReset, now) >= 1) {
                requestsThisHour.set(0);
                lastHourReset = now;
            }

            // Check limits
            if (requestsThisMinute.get() >= MAX_REQUESTS_PER_MINUTE) {
                return false;
            }

            if (requestsThisHour.get() >= MAX_REQUESTS_PER_HOUR) {
                return false;
            }

            // Increment counters
            requestsThisMinute.incrementAndGet();
            requestsThisHour.incrementAndGet();

            return true;
        }

        public int getRequestsThisMinute() {
            return requestsThisMinute.get();
        }

        public int getRequestsThisHour() {
            return requestsThisHour.get();
        }
    }

    public static class GovernanceResult {
        private final boolean allowed;
        private final String reason;
        private final String action;

        public GovernanceResult(boolean allowed, String reason, String action) {
            this.allowed = allowed;
            this.reason = reason;
            this.action = action;
        }

        public boolean isAllowed() {
            return allowed;
        }

        public String getReason() {
            return reason;
        }

        public String getAction() {
            return action;
        }
    }
}
