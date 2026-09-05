package com.careconnect.controller;

import com.careconnect.model.TelemetryEvent;
import com.careconnect.service.TelemetryService;
import com.careconnect.service.TelemetryToggleService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
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
     * <p>MAX_VALUE_LENGTH is 256, but telemetry_events.event_name is
     * VARCHAR(128) (V34.2__create_telemetry_events.sql:3, mirrored by
     * TelemetryEvent.EVENT_NAME_LENGTH). A 129-character event name is
     * therefore accepted by the controller and handed to the service, where it
     * cannot be persisted. The bound should reject at or below the column
     * width; this case asserts that and currently fails.
     *
     * <p>Must go green when DEF-TEL-11 is fixed. Not a characterization test.
     */
    @Test
    void emit_whenEventNameExceedsColumnWidth_shouldRejectBeforeService() {
        when(toggleService.isEnabled()).thenReturn(true);

        Map<String, Object> body = new HashMap<>();
        body.put("eventName", stringOfLength(129));

        ResponseEntity<?> response = controller.emit(body);

        assertThat(response.getStatusCode())
                .as("DEF-TEL-11: a 129-char eventName exceeds VARCHAR(128) and must not "
                        + "reach the persistence layer")
                .isEqualTo(HttpStatus.BAD_REQUEST);
        verify(telemetryService, never()).record(any());
    }
}
