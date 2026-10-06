package com.careconnect.service.ehr;

import ca.uhn.fhir.rest.server.exceptions.BaseServerResponseException;
import lombok.extern.slf4j.Slf4j;

import java.time.Duration;
import java.time.Instant;
import java.time.ZonedDateTime;
import java.time.format.DateTimeFormatter;
import java.time.format.DateTimeParseException;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.function.Supplier;

/**
 * Bounded retry with exponential backoff for Blue Button FHIR calls (FR-MCR-23, DEF-MCR-02).
 * <p>
 * A call that fails with HTTP 429 (rate limited) or any 5xx is tried up to {@link #MAX_ATTEMPTS}
 * times in total, waiting 2 s and then 4 s between attempts. If the server sends a
 * {@code Retry-After} header, that wait is used instead, capped at {@link #MAX_RETRY_AFTER} so a
 * misbehaving server cannot hold a request thread for minutes.
 * <p>
 * Every other failure is thrown on the first attempt. In particular a 401 is never retried: a
 * rejected token will not start working, and FR-MCR-09 requires no further call with it.
 */
@Slf4j
final class BlueButtonRetryPolicy {

    static final int MAX_ATTEMPTS = 3;
    static final Duration INITIAL_BACKOFF = Duration.ofSeconds(2);
    static final Duration MAX_RETRY_AFTER = Duration.ofSeconds(30);

    /** Waits between attempts. Tests pass one that records the waits instead of sleeping. */
    @FunctionalInterface
    interface Sleeper {
        void sleep(Duration duration) throws InterruptedException;
    }

    static final Sleeper THREAD_SLEEP = d -> Thread.sleep(d.toMillis());

    private final Sleeper sleeper;

    BlueButtonRetryPolicy(final Sleeper sleeper) {
        this.sleeper = sleeper;
    }

    /**
     * Runs {@code call}, retrying 429/5xx failures as described above.
     *
     * @param lastRetryAfter the {@code Retry-After} header of the response that just failed, or
     *                       null. HAPI does not copy response headers onto its exceptions, so
     *                       {@link MedicareService} reads it from the HTTP response with an interceptor.
     */
    <T> T execute(final String what, final Supplier<T> call, final Supplier<String> lastRetryAfter) {
        Duration backoff = INITIAL_BACKOFF;
        for (int attempt = 1; ; attempt++) {
            try {
                return call.get();
            } catch (BaseServerResponseException e) {
                if (!isRetryable(e.getStatusCode()) || attempt >= MAX_ATTEMPTS) {
                    throw e;
                }
                final Duration wait = parseRetryAfter(lastRetryAfter.get())
                        .or(() -> retryAfter(e))
                        .orElse(backoff);
                log.warn("Blue Button: {} failed with HTTP {} (attempt {} of {}); retrying in {} ms",
                        what, e.getStatusCode(), attempt, MAX_ATTEMPTS, wait.toMillis());
                pause(wait, e);
                backoff = backoff.multipliedBy(2);
            }
        }
    }

    static boolean isRetryable(final int status) {
        return status == 429 || (status >= 500 && status <= 599);
    }

    /** {@code Retry-After} from the exception's headers, if HAPI ever supplies them. */
    static Optional<Duration> retryAfter(final BaseServerResponseException e) {
        final Map<String, List<String>> headers = e.getResponseHeaders();
        if (headers == null) {
            return Optional.empty();
        }
        for (Map.Entry<String, List<String>> header : headers.entrySet()) {
            if ("retry-after".equalsIgnoreCase(header.getKey())
                    && header.getValue() != null && !header.getValue().isEmpty()) {
                return parseRetryAfter(header.getValue().get(0));
            }
        }
        return Optional.empty();
    }

    /**
     * A {@code Retry-After} value in either form RFC 9110 allows (delay in seconds, or an HTTP
     * date), capped at {@link #MAX_RETRY_AFTER}. Empty if null or unreadable.
     */
    static Optional<Duration> parseRetryAfter(final String raw) {
        if (raw == null || raw.isBlank()) {
            return Optional.empty();
        }
        final String value = raw.trim();
        Duration parsed;
        try {
            parsed = Duration.ofSeconds(Long.parseLong(value));
        } catch (NumberFormatException notSeconds) {
            try {
                final Instant at = ZonedDateTime.parse(value, DateTimeFormatter.RFC_1123_DATE_TIME).toInstant();
                parsed = Duration.between(Instant.now(), at);
            } catch (DateTimeParseException notADate) {
                return Optional.empty();
            }
        }
        if (parsed.isNegative()) {
            parsed = Duration.ZERO;
        }
        return Optional.of(parsed.compareTo(MAX_RETRY_AFTER) > 0 ? MAX_RETRY_AFTER : parsed);
    }

    private void pause(final Duration wait, final BaseServerResponseException cause) {
        try {
            sleeper.sleep(wait);
        } catch (InterruptedException interrupted) {
            // Give up rather than retry after an interrupt, and keep the interrupt visible.
            Thread.currentThread().interrupt();
            throw cause;
        }
    }
}
