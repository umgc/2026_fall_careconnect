package com.careconnect.service.emergency;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.time.Clock;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Per-client fixed-window limit on the public passport scan endpoint, the only unauthenticated
 * endpoint that reads PHI. A responder scans a code a handful of times; anything near the limit
 * is guessing.
 * <p>
 * In memory and per instance: with N backend tasks a client gets up to N times the limit. That is
 * acceptable as a brake on guessing, which the 256-bit token already makes hopeless; it is not a
 * quota. A shared limiter (e.g. at the load balancer) would replace this, not sit beside it.
 */
@Component
public class PassportScanRateLimiter {

    private static final long WINDOW_MILLIS = 60_000L;
    /** Above this many tracked clients, expired windows are swept before adding another. */
    private static final int SWEEP_THRESHOLD = 10_000;

    private final int maxPerWindow;
    private final Clock clock;
    private final Map<String, Window> windows = new ConcurrentHashMap<>();

    @Autowired
    public PassportScanRateLimiter(@Value("${careconnect.passport.scan.max-per-minute:30}") final int maxPerWindow) {
        this(maxPerWindow, Clock.systemUTC());
    }

    PassportScanRateLimiter(final int maxPerWindow, final Clock clock) {
        this.maxPerWindow = maxPerWindow;
        this.clock = clock;
    }

    /** True if the client may make another scan now; counts the attempt either way. */
    public boolean tryAcquire(final String clientKey) {
        final long now = clock.millis();
        if (windows.size() > SWEEP_THRESHOLD) {
            windows.values().removeIf(w -> now - w.start() >= WINDOW_MILLIS);
        }
        final Window window = windows.compute(clientKey == null ? "unknown" : clientKey, (key, current) ->
                current == null || now - current.start() >= WINDOW_MILLIS
                        ? new Window(now, 1)
                        : new Window(current.start(), current.count() + 1));
        return window.count() <= maxPerWindow;
    }

    private record Window(long start, int count) {
    }
}
