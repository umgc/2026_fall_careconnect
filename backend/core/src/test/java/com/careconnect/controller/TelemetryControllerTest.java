package com.careconnect.controller;

import com.careconnect.model.TelemetryEvent;
import com.careconnect.service.TelemetryService;
import com.careconnect.service.TelemetryToggleService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class TelemetryControllerTest {

    @Mock
    private TelemetryService telemetryService;

    @Mock
    private TelemetryToggleService toggleService;

    private TelemetryController controller;

    @BeforeEach
    void setUp() {
        controller = new TelemetryController(telemetryService, toggleService);
    }

    @Test
    void emit_whenTelemetryDisabled_returnsNoContent() {
        when(toggleService.isEnabled()).thenReturn(false);

        Map<String, Object> body = Map.of("eventName", "test_event");
        ResponseEntity<?> response = controller.emit(body);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.NO_CONTENT);
        verify(telemetryService, never()).record(any());
    }

    @Test
    void emit_whenTelemetryEnabled_recordsEventAndReturnsOk() {
        when(toggleService.isEnabled()).thenReturn(true);
        TelemetryEvent savedEvent = new TelemetryEvent();
        savedEvent.setEventName("test_event");
        when(telemetryService.record(any(TelemetryEvent.class))).thenReturn(savedEvent);

        Map<String, Object> body = new HashMap<>();
        body.put("eventName", "test_event");
        body.put("traceId", "trace-123");
        body.put("spanId", "span-456");
        body.put("details", Map.of("key", "value"));
        body.put("deviceInfo", Map.of("os", "android"));

        ResponseEntity<?> response = controller.emit(body);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isEqualTo(savedEvent);
        verify(telemetryService).record(any(TelemetryEvent.class));
    }

    @Test
    void emit_whenTelemetryEnabledAndBodyMissingFields_usesDefaults() {
        when(toggleService.isEnabled()).thenReturn(true);
        TelemetryEvent savedEvent = new TelemetryEvent();
        savedEvent.setEventName("dev_emit");
        when(telemetryService.record(any(TelemetryEvent.class))).thenReturn(savedEvent);

        Map<String, Object> body = new HashMap<>();

        ResponseEntity<?> response = controller.emit(body);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        verify(telemetryService).record(any(TelemetryEvent.class));
    }

    @Test
    void recent_returnsOkWithEvents() {
        List<TelemetryEvent> events = List.of(new TelemetryEvent(), new TelemetryEvent());
        when(telemetryService.recent(50)).thenReturn(events);

        ResponseEntity<?> response = controller.recent(50);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isEqualTo(events);
        verify(telemetryService).recent(50);
    }

    @Test
    void enabled_returnsOkWithEnabledStatus() {
        when(toggleService.isEnabled()).thenReturn(true);

        ResponseEntity<?> response = controller.enabled();

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        @SuppressWarnings("unchecked")
        Map<String, Object> body = (Map<String, Object>) response.getBody();
        assertThat(body).containsEntry("enabled", true);
    }

    @Test
    void enabled_whenDisabled_returnsFalse() {
        when(toggleService.isEnabled()).thenReturn(false);

        ResponseEntity<?> response = controller.enabled();

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        @SuppressWarnings("unchecked")
        Map<String, Object> body = (Map<String, Object>) response.getBody();
        assertThat(body).containsEntry("enabled", false);
    }

    @Test
    void setEnabled_returnsOkWithNewStatus() {
        when(toggleService.setEnabled(true)).thenReturn(true);

        ResponseEntity<?> response = controller.setEnabled(true);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        @SuppressWarnings("unchecked")
        Map<String, Object> body = (Map<String, Object>) response.getBody();
        assertThat(body).containsEntry("enabled", true);
        verify(toggleService).setEnabled(true);
    }

    @Test
    void setEnabled_disablesTelemetry() {
        when(toggleService.setEnabled(false)).thenReturn(false);

        ResponseEntity<?> response = controller.setEnabled(false);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        @SuppressWarnings("unchecked")
        Map<String, Object> body = (Map<String, Object>) response.getBody();
        assertThat(body).containsEntry("enabled", false);
        verify(toggleService).setEnabled(false);
    }

    // ---------------------------------------------------------------------
    // Payload-bounds coverage for commit d9bdd83a (Harden the now-public
    // telemetry ingest endpoint). The controller caps a payload at
    // MAX_TOP_LEVEL_FIELDS=16, MAX_NESTED_ENTRIES=32, MAX_VALUE_LENGTH=256.
    // ---------------------------------------------------------------------

    /** Builds a string of the requested length. */
    private static String stringOfLength(int length) {
        return "x".repeat(length);
    }

    /** Builds a map with the requested number of short-valued entries. */
    private static Map<String, Object> mapOfSize(int size) {
        Map<String, Object> map = new HashMap<>();
        for (int i = 0; i < size; i++) {
            map.put("k" + i, "v" + i);
        }
        return map;
    }

    /**
     * TC-TEL-ING-009 — negative, invalid input. A payload wider than
     * MAX_TOP_LEVEL_FIELDS is rejected with 400 and never reaches the service.
     */
    @Test
    void emit_whenTopLevelFieldsExceedCap_returnsBadRequestAndRecordsNothing() {
        when(toggleService.isEnabled()).thenReturn(true);

        ResponseEntity<?> response = controller.emit(mapOfSize(17));

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
        verify(telemetryService, never()).record(any());
    }

    /**
     * TC-TEL-ING-010 — negative, invalid input. A nested map wider than
     * MAX_NESTED_ENTRIES is rejected with 400 and never reaches the service.
     */
    @Test
    void emit_whenNestedEntriesExceedCap_returnsBadRequestAndRecordsNothing() {
        when(toggleService.isEnabled()).thenReturn(true);

        Map<String, Object> body = new HashMap<>();
        body.put("eventName", "screen_view");
        body.put("details", mapOfSize(33));

        ResponseEntity<?> response = controller.emit(body);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
        verify(telemetryService, never()).record(any());
    }

    /**
     * TC-TEL-ING-011 — negative, invalid input. A single value longer than
     * MAX_VALUE_LENGTH is rejected with 400 and never reaches the service.
     */
    @Test
    void emit_whenValueExceedsLengthCap_returnsBadRequestAndRecordsNothing() {
        when(toggleService.isEnabled()).thenReturn(true);

        Map<String, Object> body = new HashMap<>();
        body.put("eventName", "screen_view");
        body.put("details", Map.of("screen", stringOfLength(257)));

        ResponseEntity<?> response = controller.emit(body);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
        verify(telemetryService, never()).record(any());
    }

    /**
     * TC-TEL-ING-012 — boundary. A payload sitting exactly on every cap
     * (16 top-level fields, 32 nested entries, a 256-character value) is
     * accepted, because each bound rejects only on strictly-greater-than.
     */
    @Test
    void emit_whenPayloadSitsExactlyOnEveryCap_isAccepted() {
        when(toggleService.isEnabled()).thenReturn(true);
        TelemetryEvent savedEvent = new TelemetryEvent();
        savedEvent.setEventName("screen_view");
        when(telemetryService.record(any(TelemetryEvent.class))).thenReturn(savedEvent);

        Map<String, Object> body = mapOfSize(14);
        body.put("eventName", "screen_view");
        body.put("details", mapOfSize(31));
        assertThat(body).hasSize(16);

        @SuppressWarnings("unchecked")
        Map<String, Object> details = (Map<String, Object>) body.get("details");
        details.put("boundaryValue", stringOfLength(256));
        assertThat(details).hasSize(32);

        ResponseEntity<?> response = controller.emit(body);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        verify(telemetryService).record(any(TelemetryEvent.class));
    }

    /**
     * TC-TEL-ING-013 — negative. The disabled-telemetry check runs before the
     * bounds check, so an oversized payload submitted while telemetry is off
     * yields 204, not 400, and records nothing. Pins the documented order.
     */
    @Test
    void emit_whenTelemetryDisabledAndPayloadOversized_returnsNoContentNotBadRequest() {
        when(toggleService.isEnabled()).thenReturn(false);

        ResponseEntity<?> response = controller.emit(mapOfSize(17));

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.NO_CONTENT);
        verify(telemetryService, never()).record(any());
    }

    /**
     * TC-TEL-ING-014 — negative, EXPECTED-FAIL, proves DEF-TEL-11.
     *
     * <p>MAX_VALUE_LENGTH is 256, but telemetry_events.session_id is
     * VARCHAR(64) (V75__add_session_id_to_telemetry_events.sql:2). A
     * 65-character sessionId is therefore accepted by the controller and handed
     * to the service, where it cannot be persisted. The bound should reject at
     * or below the column width; this case asserts that and currently fails.
     *
     * <p>Amended 2026-09-09. The case previously used a 129-character eventName
     * against event_name VARCHAR(128). The TelemetryService allowlist (merged
     * with PR #63, b680e45a) now rejects any name outside a fixed list, so that
     * value can no longer reach the column and the eventName form no longer
     * proves the defect. sessionId, traceId and spanId are not allowlist-checked
     * and remain reachable, so the case now exercises sessionId. The defect and
     * its ID are unchanged.
     *
     * <p>Must go green when DEF-TEL-11 is fixed. Not a characterization test.
     */
    @Test
    void emit_whenSessionIdExceedsColumnWidth_shouldRejectBeforeService() {
        when(toggleService.isEnabled()).thenReturn(true);

        Map<String, Object> body = new HashMap<>();
        body.put("eventName", "screen_view");
        body.put("sessionId", stringOfLength(65));

        ResponseEntity<?> response = controller.emit(body);

        assertThat(response.getStatusCode())
                .as("DEF-TEL-11: a 65-char sessionId exceeds VARCHAR(64) and must not "
                        + "reach the persistence layer")
                .isEqualTo(HttpStatus.BAD_REQUEST);
        verify(telemetryService, never()).record(any());
    }

    /**
     * TC-TEL-ING-017 — negative, invalid input. Every column-backed field is
     * rejected one character past its column width, and none reaches the
     * service. Added 2026-09-09 with the DEF-TEL-11 fix: TC-TEL-ING-014 pins
     * sessionId alone, this pins the other three so a cap can not be raised
     * above its column unnoticed.
     */
    @ParameterizedTest(name = "TC-TEL-ING-017 [{index}] {0} at {1} chars is rejected")
    @CsvSource({
        "eventName, 129",
        "sessionId, 65",
        "traceId, 65",
        "spanId, 33"
    })
    void emit_whenColumnBackedFieldExceedsItsWidth_returnsBadRequest(
            String field, int length) {
        when(toggleService.isEnabled()).thenReturn(true);

        Map<String, Object> body = new HashMap<>();
        body.put("eventName", "screen_view");
        body.put(field, stringOfLength(length));

        ResponseEntity<?> response = controller.emit(body);

        assertThat(response.getStatusCode())
                .as("DEF-TEL-11: %s at %d chars exceeds its column and must be "
                        + "rejected before the service", field, length)
                .isEqualTo(HttpStatus.BAD_REQUEST);
        verify(telemetryService, never()).record(any());
    }

    /**
     * TC-TEL-ING-018 — boundary. A payload sitting exactly on every
     * column-backed cap is accepted, because each bound rejects only on
     * strictly-greater-than. Pairs with TC-TEL-ING-015, which proves the same
     * values persist. Added 2026-09-09 with the DEF-TEL-11 fix.
     */
    @Test
    void emit_whenColumnBackedFieldsSitExactlyOnTheirWidths_isAccepted() {
        when(toggleService.isEnabled()).thenReturn(true);
        TelemetryEvent savedEvent = new TelemetryEvent();
        savedEvent.setEventName("screen_view");
        when(telemetryService.record(any(TelemetryEvent.class))).thenReturn(savedEvent);

        Map<String, Object> body = new HashMap<>();
        body.put("eventName", stringOfLength(128));
        body.put("sessionId", stringOfLength(64));
        body.put("traceId", stringOfLength(64));
        body.put("spanId", stringOfLength(32));

        ResponseEntity<?> response = controller.emit(body);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        verify(telemetryService).record(any(TelemetryEvent.class));
    }
}
