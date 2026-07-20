package com.careconnect.service.security;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.lang.reflect.Field;
import java.time.LocalDateTime;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.mockito.Mockito.verify;

@ExtendWith(MockitoExtension.class)
class LangChainGovernanceServiceTest {

    @Mock
    private SecurityAuditService securityAuditService;

    @InjectMocks
    private LangChainGovernanceService langChainGovernanceService;

    @Test
    void validateRequest_nullMessage_isAllowed() throws Exception {
        final LangChainGovernanceService.GovernanceResult result =
                langChainGovernanceService.validateRequest(1L, "conv-1", null);
        assertThat(result.isAllowed()).isTrue();
        assertThat(result.getAction()).isEqualTo("ALLOW");
    }

    @Test
    void validateRequest_shortMessage_isAllowed() throws Exception {
        final LangChainGovernanceService.GovernanceResult result =
                langChainGovernanceService.validateRequest(2L, "conv-2", "Hello!");
        assertThat(result.isAllowed()).isTrue();
        assertThat(result.getReason()).isEqualTo("Request approved");
    }

    @Test
    void validateRequest_tooLongMessage_rejected() throws Exception {
        final String longMsg = "x".repeat(4001);
        final LangChainGovernanceService.GovernanceResult result =
                langChainGovernanceService.validateRequest(3L, "conv-3", longMsg);
        assertThat(result.isAllowed()).isFalse();
        assertThat(result.getAction()).isEqualTo("REJECT_MESSAGE_LENGTH");
        verify(securityAuditService).logGovernanceAction(3L, "conv-3", "MESSAGE_TOO_LONG",
                "Message length: 4001 exceeds limit: 4000");
    }

    @Test
    void validateRequest_exactlyAtLimit_isAllowed() throws Exception {
        final String maxMsg = "x".repeat(4000);
        final LangChainGovernanceService.GovernanceResult result =
                langChainGovernanceService.validateRequest(4L, "conv-4", maxMsg);
        assertThat(result.isAllowed()).isTrue();
    }

    @Test
    void validateRequest_rateLimitExceeded_perMinute_rejected() throws Exception {
        final Long userId = 5L;
        // Make 10 allowed requests (rate limit per minute = 10)
        for (int i = 0; i < 10; i++) {
            final LangChainGovernanceService.GovernanceResult r =
                    langChainGovernanceService.validateRequest(userId, "conv-5", "msg");
            assertThat(r.isAllowed()).isTrue();
        }
        // 11th should be rate-limited
        final LangChainGovernanceService.GovernanceResult result =
                langChainGovernanceService.validateRequest(userId, "conv-5", "msg");
        assertThat(result.isAllowed()).isFalse();
        assertThat(result.getAction()).isEqualTo("RATE_LIMIT");
    }

    @Test
    void validateModelUsage_nonGpt4_isAllowed() throws Exception {
        final LangChainGovernanceService.GovernanceResult result =
                langChainGovernanceService.validateModelUsage(1L, "conv-1", "claude-3-opus");
        assertThat(result.isAllowed()).isTrue();
        assertThat(result.getAction()).isEqualTo("ALLOW_MODEL");
    }

    @Test
    void validateModelUsage_nullModelName_isAllowed() throws Exception {
        final LangChainGovernanceService.GovernanceResult result =
                langChainGovernanceService.validateModelUsage(1L, "conv-1", null);
        assertThat(result.isAllowed()).isTrue();
    }

    @Test
    void validateModelUsage_gpt4_noTracker_isAllowed() throws Exception {
        // No prior requests for this user, so no tracker exists
        final LangChainGovernanceService.GovernanceResult result =
                langChainGovernanceService.validateModelUsage(10L, "conv-10", "gpt-4-turbo");
        assertThat(result.isAllowed()).isTrue();
    }

    @Test
    @SuppressWarnings("unchecked")
    void validateModelUsage_gpt4_exceedsHourlyLimit_rejected() throws Exception {
        final Long userId = 20L;
        // Create a tracker by making one request
        langChainGovernanceService.validateRequest(userId, "conv-20", "msg");

        // Use reflection to set requestsThisHour to 21 on the tracker
        final Field trackersField = LangChainGovernanceService.class.getDeclaredField("userRequestTrackers");
        trackersField.setAccessible(true);
        final ConcurrentHashMap<Long, Object> trackers =
                (ConcurrentHashMap<Long, Object>) trackersField.get(langChainGovernanceService);
        final Object tracker = trackers.get(userId);

        final Field hourField = tracker.getClass().getDeclaredField("requestsThisHour");
        hourField.setAccessible(true);
        ((AtomicInteger) hourField.get(tracker)).set(21);

        final LangChainGovernanceService.GovernanceResult result =
                langChainGovernanceService.validateModelUsage(userId, "conv-20", "gpt-4");
        assertThat(result.isAllowed()).isFalse();
        assertThat(result.getAction()).isEqualTo("LIMIT_ADVANCED_MODEL");
    }

    @Test
    void cleanupOldTrackers_doesNotThrow() throws Exception {
        // Ensure at least one tracker exists before cleanup
        langChainGovernanceService.validateRequest(100L, "conv-100", "msg");
        assertThatCode(() -> langChainGovernanceService.cleanupOldTrackers())
                .doesNotThrowAnyException();
    }

    @Test
    void cleanupOldTrackers_emptyMap_doesNotThrow() throws Exception {
        assertThatCode(() -> langChainGovernanceService.cleanupOldTrackers())
                .doesNotThrowAnyException();
    }

    // ----- GovernanceResult inner class -----

    @Test
    void governanceResult_getters_allowed() throws Exception {
        final LangChainGovernanceService.GovernanceResult result =
                new LangChainGovernanceService.GovernanceResult(true, "Request approved", "ALLOW");
        assertThat(result.isAllowed()).isTrue();
        assertThat(result.getReason()).isEqualTo("Request approved");
        assertThat(result.getAction()).isEqualTo("ALLOW");
    }

    @Test
    void governanceResult_getters_rejected() throws Exception {
        final LangChainGovernanceService.GovernanceResult result =
                new LangChainGovernanceService.GovernanceResult(false, "Rate limit exceeded", "RATE_LIMIT");
        assertThat(result.isAllowed()).isFalse();
        assertThat(result.getReason()).isEqualTo("Rate limit exceeded");
        assertThat(result.getAction()).isEqualTo("RATE_LIMIT");
    }

    // ----- Reflection helpers for the private UserRequestTracker -----

    @SuppressWarnings("unchecked")
    private ConcurrentHashMap<Long, Object> trackers() throws Exception {
        final Field f = LangChainGovernanceService.class.getDeclaredField("userRequestTrackers");
        f.setAccessible(true);
        return (ConcurrentHashMap<Long, Object>) f.get(langChainGovernanceService);
    }

    private Object trackerFor(Long id) throws Exception {
        return trackers().get(id);
    }

    private void setField(Object target, String name, Object value) throws Exception {
        final Field f = target.getClass().getDeclaredField(name);
        f.setAccessible(true);
        f.set(target, value);
    }

    private AtomicInteger counter(Object tracker, String name) throws Exception {
        final Field f = tracker.getClass().getDeclaredField(name);
        f.setAccessible(true);
        return (AtomicInteger) f.get(tracker);
    }

    // ----- Additional branch coverage -----

    @Test
    void validateRequest_resetsCountersAfterTimeWindow() throws Exception {
        final Long userId = 30L;
        langChainGovernanceService.validateRequest(userId, "conv-30", "msg");
        final Object tracker = trackerFor(userId);
        // Age both reset timestamps so the next call takes the minute & hour reset branches.
        setField(tracker, "lastMinuteReset", LocalDateTime.now().minusMinutes(2));
        setField(tracker, "lastHourReset", LocalDateTime.now().minusHours(2));
        counter(tracker, "requestsThisMinute").set(5);
        counter(tracker, "requestsThisHour").set(5);

        final LangChainGovernanceService.GovernanceResult result =
                langChainGovernanceService.validateRequest(userId, "conv-30", "msg");

        assertThat(result.isAllowed()).isTrue();
        // Counters were reset to 0 then incremented to 1.
        assertThat(counter(tracker, "requestsThisMinute").get()).isEqualTo(1);
    }

    @Test
    void validateModelUsage_gpt4_withLowUsageTracker_isAllowed() throws Exception {
        final Long userId = 32L;
        langChainGovernanceService.validateRequest(userId, "conv-32", "msg"); // tracker with 1 request

        final LangChainGovernanceService.GovernanceResult result =
                langChainGovernanceService.validateModelUsage(userId, "conv-32", "gpt-4");

        assertThat(result.isAllowed()).isTrue();
    }

    @Test
    void scheduledTrackerCleanup_removesStaleTrackers() throws Exception {
        final Long userId = 31L;
        langChainGovernanceService.validateRequest(userId, "conv-31", "msg");
        final Object tracker = trackerFor(userId);
        // lastMinuteReset after lastHourReset (covers the isAfter ternary) and both stale (> 2h).
        setField(tracker, "lastHourReset", LocalDateTime.now().minusHours(4));
        setField(tracker, "lastMinuteReset", LocalDateTime.now().minusHours(3));

        langChainGovernanceService.scheduledTrackerCleanup();

        assertThat(trackers().containsKey(userId)).isFalse();
    }
}
