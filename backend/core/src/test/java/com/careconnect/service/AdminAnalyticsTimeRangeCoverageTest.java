package com.careconnect.service;

import com.careconnect.repository.TelemetryEventRepository;
import org.junit.jupiter.api.Test;

import java.time.Clock;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;

class AdminAnalyticsTimeRangeCoverageTest {

    private final Clock clock = Clock.fixed(Instant.parse("2026-10-30T12:00:00Z"), ZoneOffset.UTC);
    private final AdminAnalyticsService service =
            new AdminAnalyticsService(mock(TelemetryEventRepository.class), clock);

    @Test
    void resolveRangeFillsMissingEndpoints() {
        OffsetDateTime from = OffsetDateTime.parse("2026-10-01T00:00:00Z");
        OffsetDateTime to = OffsetDateTime.parse("2026-10-10T00:00:00Z");
        assertThat(service.resolveRange(null, from, null).to()).isEqualTo(OffsetDateTime.now(clock));
        assertThat(service.resolveRange(null, null, to).from()).isBefore(to);
        assertThat(service.resolveRange(null, from, to).from()).isEqualTo(from);
    }

    @Test
    void timeRangeFactoriesAndAccessors() {
        AdminAnalyticsService.TimeRange last = AdminAnalyticsService.TimeRange.lastDays(3, clock);
        assertThat(last.startInstant()).isEqualTo(Instant.parse("2026-10-27T12:00:00Z"));
        assertThat(last.endInstant()).isEqualTo(Instant.parse("2026-10-30T12:00:00Z"));
        AdminAnalyticsService.TimeRange utc = AdminAnalyticsService.TimeRange.ofUtc(
                Instant.parse("2026-01-01T00:00:00Z"), Instant.parse("2026-01-02T00:00:00Z"));
        assertThat(utc.from().getOffset()).isEqualTo(ZoneOffset.UTC);
    }
}
