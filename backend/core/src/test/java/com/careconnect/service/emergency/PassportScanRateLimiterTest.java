package com.careconnect.service.emergency;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.util.ReflectionTestUtils.getField;

/**
 * The per-client limit on public passport scans, driven by a clock the test advances.
 * <p>
 * Test Plan §3.24.3: TC-EMG-100, 101 (author) and TC-EMG-121…123 (Testing Lead). Test IDs are permanent.
 */
class PassportScanRateLimiterTest {

    @Test
    @DisplayName("TC-EMG-100: a client gets the limit, then 429s, until the window passes")
    void limitResetsAfterTheWindow() {
        MutableClock clock = new MutableClock();
        PassportScanRateLimiter limiter = new PassportScanRateLimiter(3, clock);

        assertThat(limiter.tryAcquire("203.0.113.5")).isTrue();
        assertThat(limiter.tryAcquire("203.0.113.5")).isTrue();
        assertThat(limiter.tryAcquire("203.0.113.5")).isTrue();
        assertThat(limiter.tryAcquire("203.0.113.5")).isFalse();

        clock.advance(Duration.ofSeconds(61));
        assertThat(limiter.tryAcquire("203.0.113.5")).isTrue();
    }

    @Test
    @DisplayName("TC-EMG-101: clients are limited separately")
    void clientsAreIndependent() {
        PassportScanRateLimiter limiter = new PassportScanRateLimiter(1, new MutableClock());

        assertThat(limiter.tryAcquire("203.0.113.5")).isTrue();
        assertThat(limiter.tryAcquire("203.0.113.5")).isFalse();
        assertThat(limiter.tryAcquire("198.51.100.7")).isTrue();
    }

    // ---- Testing Lead cases (TC-EMG-121…123) ----

    @Test
    @DisplayName("TC-EMG-121: the window is exactly one minute: still limited at 59.999 s, open again at 60 s")
    void windowBoundaryIsSixtySeconds() {
        MutableClock clock = new MutableClock();
        PassportScanRateLimiter limiter = new PassportScanRateLimiter(1, clock);
        assertThat(limiter.tryAcquire("203.0.113.5")).isTrue();

        clock.advance(Duration.ofMillis(59_999));
        assertThat(limiter.tryAcquire("203.0.113.5")).as("59.999 s").isFalse();

        clock.advance(Duration.ofMillis(1));
        assertThat(limiter.tryAcquire("203.0.113.5")).as("60 s").isTrue();
    }

    @Test
    @DisplayName("TC-EMG-122: requests with no client key share one limit instead of escaping it")
    void missingClientKeySharesOneLimit() {
        PassportScanRateLimiter limiter = new PassportScanRateLimiter(1, new MutableClock());

        assertThat(limiter.tryAcquire(null)).isTrue();
        assertThat(limiter.tryAcquire(null)).isFalse();
        assertThat(limiter.tryAcquire("unknown")).as("the same bucket").isFalse();
    }

    @Test
    @DisplayName("TC-EMG-123: past 10,000 tracked clients, expired windows are swept and live ones are kept")
    void expiredWindowsAreSweptPastTheThreshold() {
        MutableClock clock = new MutableClock();
        PassportScanRateLimiter limiter = new PassportScanRateLimiter(1, clock);
        for (int i = 0; i <= 10_000; i++) {
            limiter.tryAcquire("old-" + i);
        }
        clock.advance(Duration.ofSeconds(61));
        limiter.tryAcquire("live-1");
        @SuppressWarnings("unchecked")
        Map<String, ?> windows = (Map<String, ?>) getField(limiter, "windows");
        assertThat(windows).as("the 10,001 expired windows were swept before live-1 was added")
                .containsOnlyKeys("live-1");
        assertThat(limiter.tryAcquire("live-1")).as("live-1's window survives the sweep").isFalse();
    }

    /** A clock the test moves forward by hand. */
    private static final class MutableClock extends Clock {
        private Instant now = Instant.parse("2026-10-13T12:00:00Z");

        void advance(Duration by) {
            now = now.plus(by);
        }

        @Override
        public ZoneId getZone() {
            return ZoneOffset.UTC;
        }

        @Override
        public Clock withZone(ZoneId zone) {
            return this;
        }

        @Override
        public Instant instant() {
            return now;
        }
    }
}
