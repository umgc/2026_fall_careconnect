package com.careconnect.service;

import com.careconnect.model.TelemetryEvent;
import com.careconnect.repository.TelemetryEventRepository;

import java.time.ZoneOffset;
import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.time.OffsetDateTime;
import java.util.concurrent.TimeUnit;

import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.env.Environment;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import lombok.extern.slf4j.Slf4j;

/** Service that records and queries application telemetry events. */
@Service
@RequiredArgsConstructor
@Slf4j
public class TelemetryService {

  /** Repository used to persist telemetry events. */
  private final TelemetryEventRepository repository;

  /** Feature toggle used to enable or disable telemetry collection. */
  private final TelemetryToggleService toggle;

  /**
   * Records a telemetry event when telemetry is enabled.
   *
   * @param event telemetry event to store
   * @return stored event, or the original event when telemetry is disabled
   */
  public TelemetryEvent record(final TelemetryEvent event) {
    if (!toggle.isEnabled()) {
      return event;
    }

    return repository.save(event);
  }

  @Value("${careconnect.telemetry.memory.cleanup-after-days:30}")
  private int cleanupAfterDays;
  /**
   *  Every day, drops telemetry that's older than our retention policy
   */
  @Scheduled(fixedDelay=1, timeUnit=TimeUnit.DAYS)
  public void dropOld(){
    int removedCount = repository.removeByEventTimeBefore(OffsetDateTime.now(ZoneOffset.UTC).minusDays(cleanupAfterDays));
    if(removedCount > 0){
      log.info("Removed {} old telemetry events from database.", removedCount);
    }

  }

  /**
   * Returns the most recent telemetry events up to the requested limit.
   *
   * @param limit requested number of events
   * @return recent telemetry events
   */
  public List<TelemetryEvent> recent(final int limit) {
    final List<TelemetryEvent> results = repository.findTop50ByOrderByEventTimeDesc();

    if (results == null || results.isEmpty()) {
      return Collections.emptyList();
    }

    final int safeLimit = Math.max(1, Math.min(limit, 200));
    if (results.size() <= safeLimit) {
      return results;
    }

    return results.subList(0, safeLimit);
  }

  /**
   * Records anonymous feature telemetry without user identifiers.
   *
   * @param eventName event name to store
   * @param details optional event details
   * @param deviceInfo optional device metadata
   * @param traceId distributed trace identifier
   * @param spanId distributed span identifier
   * @return stored event, or {@code null} when telemetry is disabled
   */
  public TelemetryEvent recordAnonymous(
      final String eventName,
      final Map<String, Object> details,
      final Map<String, Object> deviceInfo,
      final String traceId,
      final String spanId) {
    if (!toggle.isEnabled()) {
      return null;
    }

    final TelemetryEvent event = new TelemetryEvent();
    event.setEventName(eventName);
    event.setTraceId(traceId);
    event.setSpanId(spanId);
    event.setDetails(details);
    event.setDeviceInfo(deviceInfo);
    return repository.save(event);
  }
}
