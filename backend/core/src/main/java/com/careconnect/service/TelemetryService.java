package com.careconnect.service;

import com.careconnect.model.TelemetryEvent;
import com.careconnect.repository.TelemetryEventRepository;

import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.function.Function;
import java.util.stream.Collectors;

import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

/** Service that records and queries application telemetry events. */
@Service
@RequiredArgsConstructor
public class TelemetryService {

  /** Repository used to persist telemetry events. */
  private final TelemetryEventRepository repository;

  /** Feature toggle used to enable or disable telemetry collection. */
  private final TelemetryToggleService toggle;

  /* A list of all known telemetry events */
  private static final List<String> allowedEvents =  List.of(
          "privacy_telemetry_toggle",
          "screen_view",
          "button_tap",
          "error_network",
          "error_timeout",
          "offline_toggled",
          "feature_use",
          "sync_started",
          "sync_completed",
          "sync_failed",
          "session_start",
          "session_end",
          // Feature analytics (anonymous)
          "feature.medications.view_all",
          "feature.medications.view_active",
          "feature.medications.view_pending",
          "feature.medications.add",
          "feature.medications.approve",
          "feature.medications.delete_soft",
          "feature.medications.delete_hard"
  );

  /* A list of all known telemetry properties */
  private static final List<String> allowedDetails = List.of(
          "source",
          "target",
          "reason",
          "screen",
          "feature",
          "method",
          "endpoint",
          "timeoutMs",
          "statusCode",
          "errorType",
          "setting",
          "enabled",
          "route",
          "button_name",
          "scope",
          "pendingCount",
          "attempted",
          "failed",
          "succeeded"
  );
  /* A list of all known telemetry deviceInfo details */
  private static final List<String> allowedDeviceInfo = List.of(
          "uiSurface",
          "platform",
          "isWeb",
          "debug"
  );

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

    /* Filter by events that are allowed */
    if(allowedEvents.contains(event.getEventName())){
        /* Remove all invalid details */
        Map<String, Object> details = event.getDetails();
        /* Do a little dark magic to filter it out */
        Map<String, Object> newDetails = allowedDetails.stream().filter(details::containsKey)
                .collect(Collectors.toMap(Function.identity(), details::get));
        if(newDetails.isEmpty()){
          // Not going to bother storing an event with no valid details.
          return event;
        }
        event.setDetails(newDetails);

        Map<String, Object> deviceInfo = event.getDeviceInfo();
        Map<String, Object> newDeviceInfo = allowedDeviceInfo.stream().filter(deviceInfo::containsKey)
              .collect(Collectors.toMap(Function.identity(), deviceInfo::get));
        if(newDeviceInfo.isEmpty()){
          // Not going to bother storing an event with no valid deviceInfo
          return event;
        }
        event.setDeviceInfo(newDeviceInfo);
        return repository.save(event);
    }

    return event;
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
