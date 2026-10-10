package com.careconnect.service.ehr;

import ca.uhn.fhir.rest.server.exceptions.AuthenticationException;
import ca.uhn.fhir.rest.server.exceptions.BaseServerResponseException;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.time.Duration;
import java.time.ZoneOffset;
import java.time.ZonedDateTime;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.function.Supplier;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * The retry rule for Blue Button calls (FR-MCR-23, NFR-DEG-02), on its own: what is retried, how long
 * it waits, and when it gives up. {@code MedicareServiceTest} covers it through real HTTP.
 * <p>
 * Test IDs TC-MCR-FHIR-040..049 are permanent. Never renumber, never reuse.
 */
class BlueButtonRetryPolicyTest {

    private final List<Duration> waits = new ArrayList<>();
    private final BlueButtonRetryPolicy policy = new BlueButtonRetryPolicy(waits::add);

    @AfterEach
    void clearInterrupt() {
        Thread.interrupted();
    }

    private static BaseServerResponseException status(final int code) {
        return BaseServerResponseException.newInstance(code, "HTTP " + code);
    }

    /** Fails with each status in turn, then returns "ok". */
    private static Supplier<String> failThen(final int... statuses) {
        final AtomicInteger call = new AtomicInteger();
        return () -> {
            final int i = call.getAndIncrement();
            if (i < statuses.length) {
                throw status(statuses[i]);
            }
            return "ok";
        };
    }

    private static final Supplier<String> NO_HEADER = () -> null;

    @Test
    @DisplayName("TC-MCR-FHIR-040: a call that succeeds first time is not retried")
    void successIsNotRetried() {
        assertThat(policy.execute("read", () -> "ok", NO_HEADER)).isEqualTo("ok");
        assertThat(waits).isEmpty();
    }

    @Test
    @DisplayName("TC-MCR-FHIR-041: 5xx and 429 are retried, waiting 2 s then 4 s")
    void serverErrorsAndRateLimitsAreRetried() {
        assertThat(policy.execute("read", failThen(503, 429), NO_HEADER)).isEqualTo("ok");
        assertThat(waits).containsExactly(Duration.ofSeconds(2), Duration.ofSeconds(4));
    }

    @Test
    @DisplayName("TC-MCR-FHIR-042: after 3 attempts in all the last error is thrown")
    void givesUpAfterThreeAttempts() {
        assertThatThrownBy(() -> policy.execute("read", failThen(500, 502, 504), NO_HEADER))
                .isInstanceOf(BaseServerResponseException.class)
                .extracting(e -> ((BaseServerResponseException) e).getStatusCode())
                .isEqualTo(504);
        assertThat(waits).hasSize(BlueButtonRetryPolicy.MAX_ATTEMPTS - 1);
    }

    @Test
    @DisplayName("TC-MCR-FHIR-043: 401 is thrown at once: a rejected token will not start working (FR-MCR-09)")
    void unauthorizedIsNotRetried() {
        final AtomicInteger calls = new AtomicInteger();
        assertThatThrownBy(() -> policy.execute("read", () -> {
            calls.incrementAndGet();
            throw new AuthenticationException("rejected");
        }, NO_HEADER)).isInstanceOf(AuthenticationException.class);
        assertThat(calls).hasValue(1);
        assertThat(waits).isEmpty();
    }

    @Test
    @DisplayName("TC-MCR-FHIR-044: other 4xx are not retried")
    void clientErrorsAreNotRetried() {
        assertThatThrownBy(() -> policy.execute("read", failThen(404), NO_HEADER))
                .isInstanceOf(BaseServerResponseException.class);
        assertThat(waits).isEmpty();
    }

    @Test
    @DisplayName("TC-MCR-FHIR-045: Retry-After from the response is used instead of the backoff, capped at 30 s")
    void retryAfterHeaderIsUsedAndCapped() {
        final AtomicInteger header = new AtomicInteger();
        final Supplier<String> retryAfter = () -> header.getAndIncrement() == 0 ? "7" : "600";

        assertThat(policy.execute("read", failThen(503, 503), retryAfter)).isEqualTo("ok");
        assertThat(waits).containsExactly(Duration.ofSeconds(7), BlueButtonRetryPolicy.MAX_RETRY_AFTER);
    }

    @Test
    @DisplayName("TC-MCR-FHIR-046: Retry-After on the exception's own headers is honoured when the response one is absent")
    void retryAfterOnExceptionHeaders() {
        final BaseServerResponseException e = status(429);
        e.addResponseHeader("Retry-After", "5");

        assertThat(BlueButtonRetryPolicy.retryAfter(e)).contains(Duration.ofSeconds(5));
        assertThat(BlueButtonRetryPolicy.retryAfter(status(429))).isEmpty();
    }

    @Test
    @DisplayName("TC-MCR-FHIR-047: Retry-After is read as seconds or an HTTP date; unreadable, blank or past values give no or zero wait")
    void parseRetryAfterForms() {
        assertThat(BlueButtonRetryPolicy.parseRetryAfter("12")).contains(Duration.ofSeconds(12));
        assertThat(BlueButtonRetryPolicy.parseRetryAfter(" 3 ")).contains(Duration.ofSeconds(3));
        final String inTenSeconds = DateTimeFormatter.RFC_1123_DATE_TIME
                .format(ZonedDateTime.now(ZoneOffset.UTC).plusSeconds(10));
        assertThat(BlueButtonRetryPolicy.parseRetryAfter(inTenSeconds))
                .hasValueSatisfying(d -> assertThat(d).isBetween(Duration.ZERO, Duration.ofSeconds(10)));
        final String past = DateTimeFormatter.RFC_1123_DATE_TIME
                .format(ZonedDateTime.now(ZoneOffset.UTC).minusMinutes(5));
        assertThat(BlueButtonRetryPolicy.parseRetryAfter(past)).contains(Duration.ZERO);
        assertThat(BlueButtonRetryPolicy.parseRetryAfter("soon")).isEmpty();
        assertThat(BlueButtonRetryPolicy.parseRetryAfter("  ")).isEmpty();
        assertThat(BlueButtonRetryPolicy.parseRetryAfter(null)).isEqualTo(Optional.empty());
    }

    @Test
    @DisplayName("TC-MCR-FHIR-048: isRetryable is exactly 429 and 500..599")
    void retryableStatuses() {
        assertThat(BlueButtonRetryPolicy.isRetryable(429)).isTrue();
        assertThat(BlueButtonRetryPolicy.isRetryable(500)).isTrue();
        assertThat(BlueButtonRetryPolicy.isRetryable(599)).isTrue();
        assertThat(BlueButtonRetryPolicy.isRetryable(400)).isFalse();
        assertThat(BlueButtonRetryPolicy.isRetryable(401)).isFalse();
        assertThat(BlueButtonRetryPolicy.isRetryable(600)).isFalse();
    }

    @Test
    @DisplayName("TC-MCR-FHIR-049: an interrupted wait gives up with the original error and keeps the thread's interrupt flag")
    void interruptedWaitGivesUp() {
        final BlueButtonRetryPolicy interrupting = new BlueButtonRetryPolicy(d -> {
            throw new InterruptedException("shutting down");
        });

        assertThatThrownBy(() -> interrupting.execute("read", failThen(503), NO_HEADER))
                .isInstanceOf(BaseServerResponseException.class)
                .extracting(e -> ((BaseServerResponseException) e).getStatusCode())
                .isEqualTo(503);
        assertThat(Thread.currentThread().isInterrupted()).isTrue();
    }
}
