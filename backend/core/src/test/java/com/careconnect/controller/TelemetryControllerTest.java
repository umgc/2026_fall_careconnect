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
}
