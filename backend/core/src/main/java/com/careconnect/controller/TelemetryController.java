package com.careconnect.controller;

import com.careconnect.model.TelemetryEvent;
import com.careconnect.service.TelemetryService;
import com.careconnect.service.TelemetryToggleService;
import java.time.Clock;
import java.time.OffsetDateTime;
import java.util.Map;
import lombok.RequiredArgsConstructor;
import org.springframework.context.annotation.Profile;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** Endpoints for emitting and inspecting telemetry. */
@RestController
@RequestMapping("/v1/api/dev/telemetry")
@RequiredArgsConstructor
public class TelemetryController {

  /** Service used to persist and query telemetry events. */
  private final TelemetryService telemetry;

  /** Feature toggle used to enable or disable telemetry collection. */
  private final TelemetryToggleService toggle;

  /**
   * Emits a telemetry event from a development request payload.
   *
   * @param body request body containing telemetry fields
   * @return created telemetry event, or no content when telemetry is disabled
   */
  @PostMapping
  public final ResponseEntity<?> emit(@RequestBody final Map<String, Object> body) {
    if (!toggle.isEnabled()) {
      return ResponseEntity.noContent().build();
    }

    final TelemetryEvent event = new TelemetryEvent();
    event.setEventName(asString(body.getOrDefault("eventName", "dev_emit")));
    event.setEventTime(OffsetDateTime.now(Clock.systemUTC()));
    event.setSessionId(asString(body.get("sessionId")));
    event.setTraceId(asString(body.get("traceId")));
    event.setSpanId(asString(body.get("spanId")));
    setOptionalMap(event, body);
    return ResponseEntity.ok(telemetry.record(event));
  }

  /**
   * Returns the most recent telemetry events.
   *
   * @param limit maximum number of events to return
   * @return recent telemetry events
   */
  @GetMapping("/recent")
  public final ResponseEntity<?> recent(@RequestParam(defaultValue = "50") final int limit) {
    return ResponseEntity.ok(telemetry.recent(limit));
  }

  /**
   * Returns whether telemetry collection is currently enabled.
   *
   * @return telemetry enabled state
   */
  @GetMapping("/enabled")
  public final ResponseEntity<?> enabled() {
    return ResponseEntity.ok(Map.of("enabled", toggle.isEnabled()));
  }

  /**
   * Updates whether telemetry collection is enabled.
   *
   * @param enabled desired enabled state
   * @return updated telemetry enabled state
   */
  @PutMapping("/enabled")
  @SuppressWarnings("PMD.LinguisticNaming")
  public final ResponseEntity<?> setEnabled(@RequestParam final boolean enabled) {
    return ResponseEntity.ok(Map.of("enabled", toggle.setEnabled(enabled)));
  }

  private static void setOptionalMap(final TelemetryEvent event, final Map<String, Object> body) {
    final Map<String, Object> details = asMap(body.get("details"));
    if (!details.isEmpty()) {
      event.setDetails(details);
    }

    final Map<String, Object> deviceInfo = asMap(body.get("deviceInfo"));
    if (!deviceInfo.isEmpty()) {
      event.setDeviceInfo(deviceInfo);
    }
  }

  private static String asString(final Object value) {
    return value == null ? null : String.valueOf(value);
  }

  @SuppressWarnings("unchecked")
  private static Map<String, Object> asMap(final Object value) {
    final Map<String, Object> mapValue;
    if (value instanceof Map<?, ?> rawMap) {
      mapValue = (Map<String, Object>) rawMap;
    } else {
      mapValue = Map.of();
    }
    return mapValue;
  }
}
