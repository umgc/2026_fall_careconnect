package com.careconnect.controller;

import com.careconnect.model.TelemetryEvent;
import com.careconnect.service.TelemetryService;
import com.careconnect.service.TelemetryToggleService;

import java.time.Clock;
import java.time.OffsetDateTime;
import java.util.Map;

import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * Endpoints for emitting and inspecting telemetry.
 */
@RestController
@RequestMapping("/v1/api/dev/telemetry")
@RequiredArgsConstructor
public class TelemetryController {

  /**
   * Maximum number of top-level fields accepted on a telemetry payload.
   *
   * <p>The client sends six. The cap leaves headroom without allowing an
   * unauthenticated caller to submit arbitrarily wide objects.
   */
  private static final int MAX_TOP_LEVEL_FIELDS = 16;

  /** Maximum number of entries accepted in the details or deviceInfo maps. */
  private static final int MAX_NESTED_ENTRIES = 32;

  /**
   * Maximum accepted character length of any single stringified value.
   *
   * <p>Set above the client-side guardrail cap of 64 so that legitimate
   * payloads are never rejected here; this is a backstop against direct
   * callers, not a duplicate of the client's own limit.
   */
  private static final int MAX_VALUE_LENGTH = 256;

    /**
     * Service used to persist and query telemetry events.
     */
    private final TelemetryService telemetry;

    /**
     * Feature toggle used to enable or disable telemetry collection.
     */
    private final TelemetryToggleService toggle;

    /**
    * Reports whether a nested map is small enough to accept.
    *
    * @param nested details or deviceInfo map to measure
    * @return true when the map is within every configured bound
    */
    private static boolean nestedWithinBounds(final Map<?, ?> nested) {
      if (nested.size() > MAX_NESTED_ENTRIES) {
        return false;
      }

      for (final Object value : nested.values()) {
        if (tooLong(value)) {
          return false;
        }
      }
      return true;
    }

    /**
    * Reports whether a single value stringifies to an over-long representation.
    *
    * @param value value to measure
    * @return true when the value exceeds the accepted length
    */
    private static boolean tooLong(final Object value) {
      return value != null && String.valueOf(value).length() > MAX_VALUE_LENGTH;
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

    /**
    * Emits a telemetry event from a request payload.
    *
    * <p>This endpoint is reachable without authentication in every profile (see
    * SecurityConfig for why), so it bounds the payload before anything is handed
    * to the service layer or persisted. Size rejection happens here; event-name
    * and detail-key filtering happen in {@link TelemetryService}.
    *
    * @param body request body containing telemetry fields
    * @return created telemetry event, no content when telemetry is disabled, or
    *     bad request when the payload exceeds the accepted bounds
    */
    @PostMapping
    public final ResponseEntity<?> emit(@RequestBody final Map<String, Object> body) {
      if (!toggle.isEnabled()) {
        return ResponseEntity.noContent().build();
      }

      if (!withinBounds(body)) {
        return ResponseEntity.badRequest().body(Map.of("error", "payload exceeds accepted bounds"));
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

  /**
   * Reports whether a telemetry payload is small enough to accept.
   *
   * @param body request body to measure
   * @return true when the payload is within every configured bound
   */
  private static boolean withinBounds(final Map<String, Object> body) {
    if (body.size() > MAX_TOP_LEVEL_FIELDS) {
      return false;
    }

    for (final Map.Entry<String, Object> entry : body.entrySet()) {
      final Object value = entry.getValue();
      final boolean nested = value instanceof Map<?, ?>;
      if (nested && !nestedWithinBounds((Map<?, ?>) value)) {
        return false;
      }
      if (!nested && tooLong(value)) {
        return false;
      }
    }
    return true;
  }

}
