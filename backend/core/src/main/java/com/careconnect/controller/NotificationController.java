package com.careconnect.controller;

import com.careconnect.security.Permission;
import com.careconnect.security.RequirePermission;

import com.careconnect.dto.FirebaseNotificationRequest;
import com.careconnect.dto.NotificationResponse;
import com.careconnect.model.DeviceToken;
import com.careconnect.model.User;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.util.SecurityUtil;
import com.careconnect.websocket.NotificationWebSocketHandler;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;
import java.util.concurrent.CompletableFuture;

@RestController
@RequestMapping("/v1/api/notifications")
@Tag(name = "Firebase Notifications", description = "Firebase Cloud Messaging for push notifications")
@SecurityRequirement(name = "Bearer Authentication")
@ConditionalOnProperty(name = "firebase.enabled", havingValue = "true", matchIfMissing = true)
public class NotificationController {

    @Autowired
    private NotificationWebSocketHandler notificationWebSocketHandler;

    @Autowired
    private com.careconnect.service.NotificationService notificationService;

    @Autowired
    private SecurityUtil securityUtil;

    @Autowired
    private AuthorizationService authorizationService;

    /**
     * Send a WebSocket notification to a specific user
     */
    @RequirePermission(Permission.CREATE_TASKS)

    @PostMapping("/ws/send-to-user/{userId}")
    @Operation(
            summary = "Send WebSocket notification to user",
            description = "Send a WebSocket notification to a specific userId (user must be connected via WebSocket and registered)"
    )
    public ResponseEntity<Map<String, String>> sendWebSocketNotificationToUser(
            @PathVariable String userId,
            @RequestBody Map<String, String> body) {
        String message = body.getOrDefault("message", "");
        boolean sent = notificationWebSocketHandler.sendNotificationToUser(userId, message);
        if (sent) {
            return ResponseEntity.ok(Map.of("message", "WebSocket notification sent to user " + userId));
        } else {
            return ResponseEntity.status(404).body(Map.of("error", "No active WebSocket session for user " + userId));
        }
    }

    @RequirePermission(Permission.CREATE_TASKS)


    @PostMapping("/send")
    @Operation(
            summary = "Send push notification",
            description = "Send a push notification to a specific device token"
    )
    @ApiResponses({
            @ApiResponse(responseCode = "200", description = "Notification sent successfully"),
            @ApiResponse(responseCode = "400", description = "Invalid request"),
            @ApiResponse(responseCode = "401", description = "Unauthorized")
    })
    public ResponseEntity<NotificationResponse> sendNotification(
            @RequestBody FirebaseNotificationRequest request) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdminOrCaregiver(currentUser);

        NotificationResponse response = notificationService.sendNotification(request);
        return ResponseEntity.ok(response);
    }

    @RequirePermission(Permission.CREATE_TASKS)


    @PostMapping("/send-bulk")
    @Operation(
            summary = "Send bulk push notifications",
            description = "Send push notifications to multiple device tokens"
    )
    public ResponseEntity<List<NotificationResponse>> sendBulkNotifications(
            @RequestBody List<FirebaseNotificationRequest> requests) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdminOrCaregiver(currentUser);

        List<NotificationResponse> responses = notificationService.sendBulkNotifications(requests);
        return ResponseEntity.ok(responses);
    }

    @RequirePermission(Permission.CREATE_TASKS)


    @PostMapping("/send-to-user/{userId}")
    @Operation(
            summary = "Send notification to user",
            description = "Send push notification to all devices of a specific user"
    )
    public ResponseEntity<List<NotificationResponse>> sendNotificationToUser(
            @PathVariable Long userId,
            @RequestParam String title,
            @RequestParam String body,
            @RequestParam(required = false, defaultValue = "GENERAL") String notificationType,
            @RequestParam(required = false) Map<String, String> data) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdminOrCaregiver(currentUser);

        List<NotificationResponse> responses = notificationService
                .sendNotificationToUser(userId, title, body, notificationType, data);
        return ResponseEntity.ok(responses);
    }

    @RequirePermission(Permission.CREATE_TASKS)


    @PostMapping("/vital-alert/{patientId}")
    @Operation(
            summary = "Send vital signs alert",
            description = "Send vital signs alert to patient's caregivers"
    )
    public CompletableFuture<ResponseEntity<List<NotificationResponse>>> sendVitalAlert(
            @PathVariable Long patientId,
            @RequestParam String vitalType,
            @RequestParam String vitalValue,
            @RequestParam String alertLevel) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        if (currentUser.isFamilyMember()) throw new UnauthorizedException("Requires ADMIN, CAREGIVER, or PATIENT role");

        return notificationService.sendVitalAlert(patientId, vitalType, vitalValue, alertLevel)
                .thenApply(ResponseEntity::ok);
    }

    @RequirePermission(Permission.CREATE_TASKS)


    @PostMapping("/medication-reminder/{patientId}")
    @Operation(
            summary = "Send medication reminder",
            description = "Send medication reminder to patient"
    )
    public CompletableFuture<ResponseEntity<List<NotificationResponse>>> sendMedicationReminder(
            @PathVariable Long patientId,
            @RequestParam String medicationName,
            @RequestParam String dosage,
            @RequestParam String scheduledTime) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdminOrCaregiver(currentUser);

        return notificationService.sendMedicationReminder(patientId, medicationName, dosage, scheduledTime)
                .thenApply(ResponseEntity::ok);
    }

    @RequirePermission(Permission.CREATE_TASKS)


    @PostMapping("/emergency-alert/{patientId}")
    @Operation(
            summary = "Send emergency alert",
            description = "Send emergency alert to all caregivers and family members"
    )
    public CompletableFuture<ResponseEntity<List<NotificationResponse>>> sendEmergencyAlert(
            @PathVariable Long patientId,
            @RequestParam String emergencyType,
            @RequestParam String location) {

        return notificationService.sendEmergencyAlert(patientId, emergencyType, location)
                .thenApply(ResponseEntity::ok);
    }

    @RequirePermission(Permission.CREATE_TASKS)


    @PostMapping("/register-token")
    @Operation(
            summary = "Register device token",
            description = "Register FCM device token for push notifications"
    )
    @ApiResponses({
            @ApiResponse(responseCode = "200", description = "Token registered successfully"),
            @ApiResponse(responseCode = "400", description = "Invalid request"),
            @ApiResponse(responseCode = "401", description = "Unauthorized")
    })
    public ResponseEntity<Map<String, String>> registerDeviceToken(
            @RequestParam Long userId,
            @RequestParam String fcmToken,
            @RequestParam String deviceId,
            @RequestParam DeviceToken.DeviceType deviceType) {

        try {
            notificationService.registerDeviceToken(userId, fcmToken, deviceId, deviceType);
            return ResponseEntity.ok(Map.of("message", "Device token registered successfully"));
        } catch (Exception e) {
            return ResponseEntity.badRequest()
                    .body(Map.of("error", "Failed to register device token: " + e.getMessage()));
        }
    }

    @RequirePermission(Permission.DELETE_PATIENTS)


    @DeleteMapping("/unregister-token")
    @Operation(
            summary = "Unregister device token",
            description = "Unregister FCM device token"
    )
    public ResponseEntity<Map<String, String>> unregisterDeviceToken(
            @RequestParam String fcmToken) {

        try {
            notificationService.unregisterDeviceToken(fcmToken);
            return ResponseEntity.ok(Map.of("message", "Device token unregistered successfully"));
        } catch (Exception e) {
            return ResponseEntity.badRequest()
                    .body(Map.of("error", "Failed to unregister device token: " + e.getMessage()));
        }
    }
}
