package com.careconnect.service;

import com.careconnect.dto.AdminAnalyticsSummaryDTO;
import com.careconnect.dto.EndpointErrorCountDTO;
import com.careconnect.dto.ErrorMetricsDTO;
import com.careconnect.dto.EventNameCountDTO;
import com.careconnect.dto.FeatureUsageCountDTO;
import com.careconnect.dto.SyncMetricsDTO;
import com.careconnect.exception.AppException;
import com.careconnect.repository.TelemetryEventRepository;
import com.careconnect.repository.projection.EndpointErrorCountProjection;
import com.careconnect.repository.projection.EventNameCountProjection;
import com.careconnect.repository.projection.FeatureUsageCountProjection;
import com.careconnect.repository.projection.SyncCompletedSumProjection;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.List;
import java.util.regex.Pattern;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;

/** Aggregates anonymous product telemetry for admin dashboards. */
@Service
@RequiredArgsConstructor
public class AdminAnalyticsService {

  private static final int DEFAULT_DAYS = 7;
  private static final int MIN_DAYS = 1;
  private static final int MAX_DAYS = 90;
  private static final Pattern SAFE_BUCKET = Pattern.compile("^[a-zA-Z0-9._-]+$");

  private final TelemetryEventRepository telemetryEventRepository;
  private final Clock clock = Clock.systemUTC();

  /**
   * Builds an anonymous telemetry summary for the inclusive-exclusive window
   * [{@code from}, {@code to}).
   */
  public AdminAnalyticsSummaryDTO getSummary(final OffsetDateTime from, final OffsetDateTime to) {
    validateRange(from, to);

    final long totalEvents = telemetryEventRepository.countTotalEventsBetween(from, to);
    final long sessionCount = telemetryEventRepository.countDistinctSessionsBetween(from, to);

    final List<EventNameCountDTO> eventCountsByName =
        telemetryEventRepository.countByEventNameBetween(from, to).stream()
            .map(this::toEventNameCount)
            .filter(dto -> dto != null)
            .toList();

    final List<FeatureUsageCountDTO> topFeatures =
        telemetryEventRepository.countTopFeaturesBetween(from, to).stream()
            .map(this::toFeatureUsageCount)
            .filter(dto -> dto != null)
            .toList();

    final SyncMetricsDTO syncMetrics = buildSyncMetrics(from, to);
    final ErrorMetricsDTO errorMetrics = buildErrorMetrics(from, to);

    return new AdminAnalyticsSummaryDTO(
        from.toInstant(),
        to.toInstant(),
        totalEvents,
        sessionCount,
        eventCountsByName,
        topFeatures,
        syncMetrics,
        errorMetrics);
  }

  /**
   * Resolves a query window from optional {@code days}, {@code from}, and {@code to} parameters.
   */
  public TimeRange resolveRange(
      final Integer days, final OffsetDateTime from, final OffsetDateTime to) {
    if (from != null || to != null) {
      final OffsetDateTime resolvedTo =
          to != null ? to : OffsetDateTime.now(clock);
      final OffsetDateTime resolvedFrom =
          from != null ? from : resolvedTo.minusDays(DEFAULT_DAYS);
      return new TimeRange(resolvedFrom, resolvedTo);
    }

    final int safeDays = clampDays(days != null ? days : DEFAULT_DAYS);
    final OffsetDateTime resolvedTo = OffsetDateTime.now(clock);
    final OffsetDateTime resolvedFrom = resolvedTo.minusDays(safeDays);
    return new TimeRange(resolvedFrom, resolvedTo);
  }

  private SyncMetricsDTO buildSyncMetrics(
      final OffsetDateTime from, final OffsetDateTime to) {
    final long started =
        telemetryEventRepository.countEventsNamedBetween("sync_started", from, to);
    final long completed =
        telemetryEventRepository.countEventsNamedBetween("sync_completed", from, to);
    final long failedEvents =
        telemetryEventRepository.countEventsNamedBetween("sync_failed", from, to);

    final SyncCompletedSumProjection sums = telemetryEventRepository.sumSyncCompletedBetween(from, to);
    final long attempted = sums != null ? sums.getAttempted() : 0L;
    final long succeeded = sums != null ? sums.getSucceeded() : 0L;
    final long failed = sums != null ? sums.getFailed() : 0L;

    final long denominator = succeeded + failed;
    final Double successRate =
        denominator > 0 ? (double) succeeded / denominator : null;

    return new SyncMetricsDTO(
        started, completed, failedEvents, attempted, succeeded, failed, successRate);
  }

  private ErrorMetricsDTO buildErrorMetrics(
      final OffsetDateTime from, final OffsetDateTime to) {
    final List<EndpointErrorCountProjection> raw =
        telemetryEventRepository.countErrorsByEndpointBetween(from, to);

    final List<EndpointErrorCountDTO> sanitized = new ArrayList<>();
    long totalErrors = 0L;

    for (final EndpointErrorCountProjection row : raw) {
      final String endpoint = sanitizeBucket(row.getEndpoint());
      if (endpoint == null) {
        continue;
      }
      sanitized.add(new EndpointErrorCountDTO(endpoint, row.getCount(), 0.0d));
      totalErrors += row.getCount();
    }

    if (totalErrors == 0L) {
      return new ErrorMetricsDTO(0L, List.of());
    }

    final long totalErrorCount = totalErrors;
    final List<EndpointErrorCountDTO> withRates =
        sanitized.stream()
            .map(
                row ->
                    new EndpointErrorCountDTO(
                        row.endpoint(),
                        row.count(),
                        (double) row.count() / totalErrorCount))
            .toList();

    return new ErrorMetricsDTO(totalErrorCount, withRates);
  }

  private EventNameCountDTO toEventNameCount(final EventNameCountProjection projection) {
    final String eventName = sanitizeBucket(projection.getEventName());
    if (eventName == null) {
      return null;
    }
    return new EventNameCountDTO(eventName, projection.getCount());
  }

  private FeatureUsageCountDTO toFeatureUsageCount(final FeatureUsageCountProjection projection) {
    final String feature = sanitizeBucket(projection.getFeature());
    if (feature == null) {
      return null;
    }
    return new FeatureUsageCountDTO(feature, projection.getCount());
  }

  private void validateRange(final OffsetDateTime from, final OffsetDateTime to) {
    if (from == null || to == null) {
      throw new AppException(HttpStatus.BAD_REQUEST, "Both from and to are required");
    }
    if (!from.isBefore(to)) {
      throw new AppException(HttpStatus.BAD_REQUEST, "from must be before to");
    }

    final Duration window = Duration.between(from, to);
    if (window.toDays() > MAX_DAYS) {
      throw new AppException(
          HttpStatus.BAD_REQUEST, "Date range cannot exceed " + MAX_DAYS + " days");
    }
  }

  private int clampDays(final int days) {
    return Math.max(MIN_DAYS, Math.min(days, MAX_DAYS));
  }

  private String sanitizeBucket(final String value) {
    if (value == null) {
      return null;
    }
    final String trimmed = value.trim();
    if (trimmed.isEmpty() || trimmed.length() > 64) {
      return null;
    }
    if (!SAFE_BUCKET.matcher(trimmed).matches()) {
      return null;
    }
    return trimmed;
  }

  /** Resolved inclusive-exclusive telemetry query window. */
  public record TimeRange(OffsetDateTime from, OffsetDateTime to) {

    public Instant startInstant() {
      return from.toInstant();
    }

    public Instant endInstant() {
      return to.toInstant();
    }

    public static TimeRange lastDays(final int days, final Clock clock) {
      final OffsetDateTime to = OffsetDateTime.now(clock);
      final OffsetDateTime from = to.minusDays(days);
      return new TimeRange(from, to);
    }

    public static TimeRange ofUtc(final Instant from, final Instant to) {
      return new TimeRange(
          OffsetDateTime.ofInstant(from, ZoneOffset.UTC),
          OffsetDateTime.ofInstant(to, ZoneOffset.UTC));
    }
  }
}
