package com.careconnect.controller;

import com.careconnect.dto.FirebaseNotificationRequest;
import com.careconnect.dto.NotificationResponse;
import com.careconnect.model.DeviceToken;
import com.careconnect.model.User;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.Role;
import com.careconnect.service.NotificationService;
import com.careconnect.util.SecurityUtil;
import com.careconnect.websocket.NotificationWebSocketHandler;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;

import java.util.List;
import java.util.Map;
import java.util.concurrent.CompletableFuture;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class NotificationControllerTest {

    private static final Long USER_ID = 1L;
    private static final Long PATIENT_ID = 2L;
    @Mock
    private NotificationWebSocketHandler notificationWebSocketHandler;
    @Mock
    private NotificationService notificationService;
    @Mock
    private SecurityUtil securityUtil;
    @Mock
    private AuthorizationService authorizationService;
    @InjectMocks
    private NotificationController controller;

    // ─── sendWebSocketNotificationToUser ──────────────────────────────────────

    @Test
    void sendWebSocketNotification_sent_returns200() throws Exception {
        when(notificationWebSocketHandler.sendNotificationToUser("user-123", "Hello"))
                .thenReturn(true);

        final ResponseEntity<Map<String, String>> response = controller.sendWebSocketNotificationToUser(
                "user-123", Map.of("message", "Hello"));

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody().get("message")).contains("user-123");
    }

    @Test
    void sendWebSocketNotification_notSent_returns404() throws Exception {
        when(notificationWebSocketHandler.sendNotificationToUser("user-123", "Hello"))
                .thenReturn(false);

        final ResponseEntity<Map<String, String>> response = controller.sendWebSocketNotificationToUser(
                "user-123", Map.of("message", "Hello"));

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
        assertThat(response.getBody().get("error")).contains("user-123");
    }

    @Test
    void sendWebSocketNotification_noMessageKey_usesEmptyString() throws Exception {
        when(notificationWebSocketHandler.sendNotificationToUser("u1", "")).thenReturn(true);

        final ResponseEntity<Map<String, String>> response = controller.sendWebSocketNotificationToUser(
                "u1", Map.of());

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
    }

    // ─── sendNotification ─────────────────────────────────────────────────────

    @Test
    void sendNotification_returns200() throws Exception {
        final FirebaseNotificationRequest request = mock(FirebaseNotificationRequest.class);
        final NotificationResponse notifResponse = NotificationResponse.success("msg-id");
        when(notificationService.sendNotification(request)).thenReturn(notifResponse);

        final ResponseEntity<NotificationResponse> response = controller.sendNotification(request);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isSameAs(notifResponse);
    }

    // ─── sendBulkNotifications ────────────────────────────────────────────────

    @Test
    void sendBulkNotifications_returns200() throws Exception {
        final FirebaseNotificationRequest req = mock(FirebaseNotificationRequest.class);
        final List<NotificationResponse> responses = List.of(NotificationResponse.success("id-1"));
        when(notificationService.sendBulkNotifications(anyList())).thenReturn(responses);

        final ResponseEntity<List<NotificationResponse>> response =
                controller.sendBulkNotifications(List.of(req));

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isSameAs(responses);
    }

    // ─── sendNotificationToUser ───────────────────────────────────────────────

    @Test
    void sendNotificationToUser_returns200() throws Exception {
        final List<NotificationResponse> responses = List.of(NotificationResponse.success("id-1"));
        when(notificationService.sendNotificationToUser(USER_ID, "Title", "Body", "GENERAL", null))
                .thenReturn(responses);

        final ResponseEntity<List<NotificationResponse>> response =
                controller.sendNotificationToUser(USER_ID, "Title", "Body", "GENERAL", null);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isSameAs(responses);
    }

    // ─── sendVitalAlert ───────────────────────────────────────────────────────

    @Test
    void sendVitalAlert_returns200_async() throws Exception {
        final User currentUser = User.builder().id(USER_ID).email("caregiver@test.com").role(Role.CAREGIVER).password("p").status("ACTIVE").build();
        when(securityUtil.resolveCurrentUser()).thenReturn(currentUser);
        final List<NotificationResponse> responses = List.of(NotificationResponse.success("alert-1"));
        when(notificationService.sendVitalAlert(PATIENT_ID, "HR", "120bpm", "HIGH"))
                .thenReturn(CompletableFuture.completedFuture(responses));

        final CompletableFuture<ResponseEntity<List<NotificationResponse>>> future =
                controller.sendVitalAlert(PATIENT_ID, "HR", "120bpm", "HIGH");
        final ResponseEntity<List<NotificationResponse>> response = future.get();

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isSameAs(responses);
    }

    // ─── sendMedicationReminder ───────────────────────────────────────────────

    @Test
    void sendMedicationReminder_returns200_async() throws Exception {
        final List<NotificationResponse> responses = List.of(NotificationResponse.success("rem-1"));
        when(notificationService.sendMedicationReminder(PATIENT_ID, "Aspirin", "100mg", "08:00"))
                .thenReturn(CompletableFuture.completedFuture(responses));

        final CompletableFuture<ResponseEntity<List<NotificationResponse>>> future =
                controller.sendMedicationReminder(PATIENT_ID, "Aspirin", "100mg", "08:00");
        final ResponseEntity<List<NotificationResponse>> response = future.get();

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isSameAs(responses);
    }

    // ─── sendEmergencyAlert ───────────────────────────────────────────────────

    @Test
    void sendEmergencyAlert_returns200_async() throws Exception {
        final List<NotificationResponse> responses = List.of(NotificationResponse.success("emg-1"));
        when(notificationService.sendEmergencyAlert(PATIENT_ID, "FALL", "Room 101"))
                .thenReturn(CompletableFuture.completedFuture(responses));

        final CompletableFuture<ResponseEntity<List<NotificationResponse>>> future =
                controller.sendEmergencyAlert(PATIENT_ID, "FALL", "Room 101");
        final ResponseEntity<List<NotificationResponse>> response = future.get();

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isSameAs(responses);
    }

    // ─── registerDeviceToken ──────────────────────────────────────────────────

    @Test
    void registerDeviceToken_success_returns200() throws Exception {
        doNothing().when(notificationService).registerDeviceToken(
                USER_ID, "fcm-token-abc", "device-001", DeviceToken.DeviceType.ANDROID);

        final ResponseEntity<Map<String, String>> response = controller.registerDeviceToken(
                USER_ID, "fcm-token-abc", "device-001", DeviceToken.DeviceType.ANDROID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody().get("message")).isEqualTo("Device token registered successfully");
    }

    @Test
    void registerDeviceToken_throws_returns400() throws Exception {
        doThrow(new RuntimeException("DB error")).when(notificationService).registerDeviceToken(
                any(), anyString(), anyString(), any());

        final ResponseEntity<Map<String, String>> response = controller.registerDeviceToken(
                USER_ID, "bad-token", "device-001", DeviceToken.DeviceType.IOS);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
        assertThat(response.getBody().get("error")).contains("DB error");
    }

    // ─── unregisterDeviceToken ────────────────────────────────────────────────

    @Test
    void unregisterDeviceToken_success_returns200() throws Exception {
        doNothing().when(notificationService).unregisterDeviceToken("fcm-token-xyz");

        final ResponseEntity<Map<String, String>> response = controller.unregisterDeviceToken("fcm-token-xyz");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody().get("message")).isEqualTo("Device token unregistered successfully");
    }

    @Test
    void unregisterDeviceToken_throws_returns400() throws Exception {
        doThrow(new RuntimeException("Token not found")).when(notificationService)
                .unregisterDeviceToken(anyString());

        final ResponseEntity<Map<String, String>> response = controller.unregisterDeviceToken("bad-token");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
        assertThat(response.getBody().get("error")).contains("Token not found");
    }
}
