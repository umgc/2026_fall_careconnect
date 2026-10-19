package com.careconnect.controller;

import com.careconnect.security.Permission;
import com.careconnect.security.RequirePermission;

import com.careconnect.model.User;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.WebSocketNotificationService;
import com.careconnect.util.SecurityUtil;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

@RestController
@RequestMapping("/api/websocket")
@RequiredArgsConstructor
@Slf4j
@Tag(name = "WebSocket Management", description = "WebSocket notifications and real-time communication management")
@SecurityRequirement(name = "Bearer Authentication")
public class WebSocketController {
    private final WebSocketNotificationService webSocketNotificationService;
    private final SecurityUtil securityUtil;
    private final AuthorizationService authorizationService;

    /**
     * Initialize WebSocket service (dummy endpoint for client handshake/testing)
     */
    @RequirePermission(Permission.CREATE_TASKS)

    @PostMapping("/init")
    @Operation(
            summary = "Initialize WebSocket service",
            description = "Initialize or handshake with the WebSocket service via HTTP"
    )
    public ResponseEntity<Map<String, Object>> initializeWebSocketService(@RequestBody(required = false) Map<String, Object> request) {
        // RBAC: Verify the caller is an authenticated user (any role).
        // resolveCurrentUser() throws RuntimeException if no valid JWT is present.
        securityUtil.resolveCurrentUser();
        return ResponseEntity.ok(Map.of(
                "success", true,
                "message", "WebSocket service initialized",
                "timestamp", System.currentTimeMillis()
        ));
    }

    /**
     * Register a user for WebSocket notifications
     */
    @RequirePermission(Permission.CREATE_TASKS)

    @PostMapping("/register-user")
    @Operation(
            summary = "Register user for WebSocket notifications",
            description = "Register a user for WebSocket notifications via HTTP"
    )
    public ResponseEntity<Map<String, Object>> registerUserForWebSocket(@RequestBody Map<String, Object> request) {
        // RBAC: Verify the caller is an authenticated user (any role).
        // resolveCurrentUser() throws RuntimeException if no valid JWT is present.
        securityUtil.resolveCurrentUser();
        try {
            String userId = (String) request.get("userId");
            String userName = (String) request.get("userName");
            if (userId == null || userName == null) {
                return ResponseEntity.badRequest().body(Map.of(
                        "success", false,
                        "message", "Missing required fields: userId and userName are required"
                ));
            }
            // Register user in the WebSocket service (dummy logic, replace with real registration if needed)
            webSocketNotificationService.registerUser(userId, userName);
            return ResponseEntity.ok(Map.of(
                    "success", true,
                    "message", "User registered for WebSocket notifications",
                    "userId", userId,
                    "userName", userName
            ));
        } catch (Exception e) {
            log.error("Error registering user for WebSocket", e);
            return ResponseEntity.badRequest().body(Map.of(
                    "success", false,
                    "message", "Failed to register user: " + e.getMessage()
            ));
        }
    }

    @RequirePermission(Permission.CREATE_TASKS)


    @PostMapping("/call-invitation")
    @Operation(
            summary = "Send call invitation",
            description = "Send a video/audio call invitation to another user through WebSocket"
    )
    @ApiResponses(value = {
            @ApiResponse(responseCode = "200", description = "Call invitation sent successfully"),
            @ApiResponse(responseCode = "400", description = "Invalid request data"),
            @ApiResponse(responseCode = "401", description = "Unauthorized"),
            @ApiResponse(responseCode = "403", description = "Access denied")
    })
    public ResponseEntity<Map<String, Object>> sendCallInvitation(
            @RequestBody Map<String, Object> request) {
        // RBAC: Verify the caller is an authenticated user (any role may initiate calls).
        // resolveCurrentUser() throws RuntimeException if no valid JWT is present.
        securityUtil.resolveCurrentUser();

        try {
            String recipientId = (String) request.get("recipientId");
            String senderId = (String) request.get("senderId");
            String senderName = (String) request.get("senderName");
            String callId = (String) request.get("callId");
            Boolean isVideoCall = (Boolean) request.getOrDefault("isVideoCall", true);
            String callType = (String) request.getOrDefault("callType", "general");

            webSocketNotificationService.sendCallInvitation(
                    recipientId, senderId, senderName, callId, isVideoCall, callType
            );

            return ResponseEntity.ok(Map.of(
                    "success", true,
                    "message", "Call invitation sent successfully",
                    "callId", callId,
                    "recipientId", recipientId
            ));

        } catch (Exception e) {
            log.error("Error sending call invitation", e);
            return ResponseEntity.badRequest().body(Map.of(
                    "success", false,
                    "message", "Failed to send call invitation: " + e.getMessage()
            ));
        }
    }

    @RequirePermission(Permission.CREATE_TASKS)


    @PostMapping("/sms-notification")
    @Operation(
            summary = "Send SMS notification",
            description = "Send an SMS-style notification to another user through WebSocket"
    )
    @ApiResponses(value = {
            @ApiResponse(responseCode = "200", description = "SMS notification sent successfully"),
            @ApiResponse(responseCode = "400", description = "Invalid request data"),
            @ApiResponse(responseCode = "401", description = "Unauthorized")
    })
    public ResponseEntity<Map<String, Object>> sendSMSNotification(
            @RequestBody Map<String, Object> request) {
        // RBAC: Verify the caller is an authenticated user (any role may send notifications).
        // resolveCurrentUser() throws RuntimeException if no valid JWT is present.
        securityUtil.resolveCurrentUser();

        try {
            String recipientId = (String) request.get("recipientId");
            String senderId = (String) request.get("senderId");
            String senderName = (String) request.get("senderName");
            String message = (String) request.get("message");
            String messageType = (String) request.getOrDefault("messageType", "general");

            webSocketNotificationService.sendSMSNotification(
                    recipientId, senderId, senderName, message, messageType
            );

            return ResponseEntity.ok(Map.of(
                    "success", true,
                    "message", "SMS notification sent successfully",
                    "recipientId", recipientId
            ));

        } catch (Exception e) {
            log.error("Error sending SMS notification", e);
            return ResponseEntity.badRequest().body(Map.of(
                    "success", false,
                    "message", "Failed to send SMS notification: " + e.getMessage()
            ));
        }
    }

    @RequirePermission(Permission.CREATE_TASKS)


    @PostMapping("/medication-reminder")
    @Operation(
            summary = "Send medication reminder",
            description = "Send a medication reminder notification to a patient"
    )
    @ApiResponses(value = {
            @ApiResponse(responseCode = "200", description = "Medication reminder sent successfully"),
            @ApiResponse(responseCode = "400", description = "Invalid request data"),
            @ApiResponse(responseCode = "403", description = "Access denied - Only caregivers can send medication reminders")
    })
    public ResponseEntity<Map<String, Object>> sendMedicationReminder(
            @RequestBody Map<String, Object> request) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdminOrCaregiver(currentUser);

        try {
            String patientId = (String) request.get("patientId");
            String medicationName = (String) request.get("medicationName");
            String reminderTime = (String) request.get("reminderTime");
            String dosage = (String) request.get("dosage");

            webSocketNotificationService.sendMedicationReminder(
                    patientId, medicationName, reminderTime, dosage
            );

            return ResponseEntity.ok(Map.of(
                    "success", true,
                    "message", "Medication reminder sent successfully",
                    "patientId", patientId,
                    "medicationName", medicationName
            ));

        } catch (Exception e) {
            log.error("Error sending medication reminder", e);
            return ResponseEntity.badRequest().body(Map.of(
                    "success", false,
                    "message", "Failed to send medication reminder: " + e.getMessage()
            ));
        }
    }

    @RequirePermission(Permission.CREATE_TASKS)


    @PostMapping("/vital-signs-alert")
    @Operation(
            summary = "Send vital signs alert",
            description = "Send a vital signs alert to healthcare providers"
    )
    @ApiResponses(value = {
            @ApiResponse(responseCode = "200", description = "Vital signs alert sent successfully"),
            @ApiResponse(responseCode = "400", description = "Invalid request data"),
            @ApiResponse(responseCode = "403", description = "Access denied")
    })
    public ResponseEntity<Map<String, Object>> sendVitalSignsAlert(
            @RequestBody Map<String, Object> request) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdminOrCaregiver(currentUser);

        try {
            String patientId = (String) request.get("patientId");
            String patientName = (String) request.get("patientName");
            String alertType = (String) request.get("alertType");
            String alertMessage = (String) request.get("alertMessage");
            String severity = (String) request.get("severity");

            @SuppressWarnings("unchecked")
            java.util.List<String> recipientIdsList = (java.util.List<String>) request.get("recipientIds");
            String[] recipientIds = recipientIdsList.toArray(new String[0]);

            webSocketNotificationService.sendVitalSignsAlert(
                    patientId, patientName, alertType, alertMessage, severity, recipientIds
            );

            return ResponseEntity.ok(Map.of(
                    "success", true,
                    "message", "Vital signs alert sent successfully",
                    "patientId", patientId,
                    "recipientCount", recipientIds.length
            ));

        } catch (Exception e) {
            log.error("Error sending vital signs alert", e);
            return ResponseEntity.badRequest().body(Map.of(
                    "success", false,
                    "message", "Failed to send vital signs alert: " + e.getMessage()
            ));
        }
    }

    @RequirePermission(Permission.CREATE_TASKS)


    @PostMapping("/emergency-alert")
    @Operation(
            summary = "Send emergency alert",
            description = "Send a high-priority emergency alert to emergency contacts"
    )
    @ApiResponses(value = {
            @ApiResponse(responseCode = "200", description = "Emergency alert sent successfully"),
            @ApiResponse(responseCode = "400", description = "Invalid request data"),
            @ApiResponse(responseCode = "403", description = "Access denied")
    })
    public ResponseEntity<Map<String, Object>> sendEmergencyAlert(
            @RequestBody Map<String, Object> request) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdminOrCaregiver(currentUser);

        try {
            String patientId = (String) request.get("patientId");
            String patientName = (String) request.get("patientName");
            String alertMessage = (String) request.get("alertMessage");

            @SuppressWarnings("unchecked")
            java.util.List<String> emergencyContactIdsList = (java.util.List<String>) request.get("emergencyContactIds");
            String[] emergencyContactIds = emergencyContactIdsList.toArray(new String[0]);

            webSocketNotificationService.sendEmergencyAlert(
                    patientId, patientName, alertMessage, emergencyContactIds
            );

            return ResponseEntity.ok(Map.of(
                    "success", true,
                    "message", "Emergency alert sent successfully",
                    "patientId", patientId,
                    "contactCount", emergencyContactIds.length
            ));

        } catch (Exception e) {
            log.error("Error sending emergency alert", e);
            return ResponseEntity.badRequest().body(Map.of(
                    "success", false,
                    "message", "Failed to send emergency alert: " + e.getMessage()
            ));
        }
    }

    @RequirePermission(Permission.CREATE_TASKS)


    @PostMapping("/appointment-reminder")
    @Operation(
            summary = "Send appointment reminder",
            description = "Send an appointment reminder to a patient"
    )
    @ApiResponses(value = {
            @ApiResponse(responseCode = "200", description = "Appointment reminder sent successfully"),
            @ApiResponse(responseCode = "400", description = "Invalid request data"),
            @ApiResponse(responseCode = "403", description = "Access denied")
    })
    public ResponseEntity<Map<String, Object>> sendAppointmentReminder(
            @RequestBody Map<String, Object> request) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdminOrCaregiver(currentUser);

        try {
            String patientId = (String) request.get("patientId");
            String appointmentDetails = (String) request.get("appointmentDetails");
            String appointmentTime = (String) request.get("appointmentTime");
            String providerName = (String) request.get("providerName");

            webSocketNotificationService.sendAppointmentReminder(
                    patientId, appointmentDetails, appointmentTime, providerName
            );

            return ResponseEntity.ok(Map.of(
                    "success", true,
                    "message", "Appointment reminder sent successfully",
                    "patientId", patientId,
                    "appointmentTime", appointmentTime
            ));

        } catch (Exception e) {
            log.error("Error sending appointment reminder", e);
            return ResponseEntity.badRequest().body(Map.of(
                    "success", false,
                    "message", "Failed to send appointment reminder: " + e.getMessage()
            ));
        }
    }

    @RequirePermission(Permission.CREATE_TASKS)


    @PostMapping("/system-announcement")
    @Operation(
            summary = "Broadcast system announcement",
            description = "Send a system-wide announcement to all connected users"
    )
    @ApiResponses(value = {
            @ApiResponse(responseCode = "200", description = "System announcement broadcasted successfully"),
            @ApiResponse(responseCode = "400", description = "Invalid request data"),
            @ApiResponse(responseCode = "403", description = "Access denied - Admin only")
    })
    public ResponseEntity<Map<String, Object>> broadcastSystemAnnouncement(
            @RequestBody Map<String, Object> request) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdmin(currentUser);

        try {
            String title = (String) request.get("title");
            String message = (String) request.get("message");
            String type = (String) request.getOrDefault("type", "info");

            webSocketNotificationService.broadcastSystemAnnouncement(title, message, type);

            return ResponseEntity.ok(Map.of(
                    "success", true,
                    "message", "System announcement broadcasted successfully",
                    "title", title,
                    "onlineUsers", webSocketNotificationService.getOnlineUsersCount()
            ));

        } catch (Exception e) {
            log.error("Error broadcasting system announcement", e);
            return ResponseEntity.badRequest().body(Map.of(
                    "success", false,
                    "message", "Failed to broadcast system announcement: " + e.getMessage()
            ));
        }
    }

    @RequirePermission(Permission.VIEW_ASSIGNED_PATIENTS)


    @GetMapping("/online-users")
    @Operation(
            summary = "Get online users",
            description = "Get list of currently online users"
    )
    @ApiResponses(value = {
            @ApiResponse(responseCode = "200", description = "Online users retrieved successfully"),
            @ApiResponse(responseCode = "403", description = "Access denied - Admin only")
    })
    public ResponseEntity<Map<String, Object>> getOnlineUsers() throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdmin(currentUser);

        try {
            Map<String, String> onlineUsers = webSocketNotificationService.getOnlineUsers();
            int onlineCount = webSocketNotificationService.getOnlineUsersCount();

            return ResponseEntity.ok(Map.of(
                    "success", true,
                    "onlineUsers", onlineUsers,
                    "onlineCount", onlineCount,
                    "timestamp", System.currentTimeMillis()
            ));

        } catch (Exception e) {
            log.error("Error getting online users", e);
            return ResponseEntity.badRequest().body(Map.of(
                    "success", false,
                    "message", "Failed to get online users: " + e.getMessage()
            ));
        }
    }

    @RequirePermission(Permission.VIEW_ASSIGNED_PATIENTS)


    @GetMapping("/user-status/{userId}")
    @Operation(
            summary = "Check user online status",
            description = "Check if a specific user is currently online"
    )
    @ApiResponses(value = {
            @ApiResponse(responseCode = "200", description = "User status retrieved successfully"),
            @ApiResponse(responseCode = "403", description = "Access denied")
    })
    public ResponseEntity<Map<String, Object>> getUserOnlineStatus(
            @Parameter(description = "User ID to check") @PathVariable String userId) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdminOrCaregiver(currentUser);

        try {
            boolean isOnline = webSocketNotificationService.isUserOnline(userId);

            return ResponseEntity.ok(Map.of(
                    "success", true,
                    "userId", userId,
                    "isOnline", isOnline,
                    "timestamp", System.currentTimeMillis()
            ));

        } catch (Exception e) {
            log.error("Error checking user online status", e);
            return ResponseEntity.badRequest().body(Map.of(
                    "success", false,
                    "message", "Failed to check user status: " + e.getMessage()
            ));
        }
    }

    @RequirePermission(Permission.CREATE_TASKS)


    @PostMapping("/sos-call")
    @Operation(
            summary = "Send SOS call to all caregivers",
            description = "Send an emergency SOS call from a patient to all their associated caregivers"
    )
    @ApiResponses(value = {
            @ApiResponse(responseCode = "200", description = "SOS call sent successfully to all caregivers"),
            @ApiResponse(responseCode = "400", description = "Invalid request data"),
            @ApiResponse(responseCode = "401", description = "Unauthorized"),
            @ApiResponse(responseCode = "403", description = "Access denied - Only patients can initiate SOS calls"),
            @ApiResponse(responseCode = "404", description = "Patient not found or no caregivers associated")
    })
    public ResponseEntity<Map<String, Object>> sendSOSCall(
            @RequestBody Map<String, Object> request) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        if (!currentUser.isPatient()) throw new UnauthorizedException("Only patients can initiate SOS calls");

        try {
            String patientUserId = (String) request.get("patientUserId");
            String patientName = (String) request.get("patientName");
            String callId = (String) request.get("callId");
            String emergencyType = (String) request.getOrDefault("emergencyType", "GENERAL");
            String location = (String) request.get("location");
            String additionalInfo = (String) request.get("additionalInfo");
            Boolean isVideoCall = (Boolean) request.getOrDefault("isVideoCall", true);

            // Validate required fields
            if (patientUserId == null || patientName == null || callId == null) {
                return ResponseEntity.badRequest().body(Map.of(
                        "success", false,
                        "message", "Missing required fields: patientUserId, patientName, and callId are required"
                ));
            }

            int notifiedCaregivers = webSocketNotificationService.sendSOSCallToAllCaregivers(
                    patientUserId, patientName, callId, emergencyType, location, additionalInfo, isVideoCall
            );

            if (notifiedCaregivers == 0) {
                return ResponseEntity.status(404).body(Map.of(
                        "success", false,
                        "message", "No caregivers found for this patient or none are currently online",
                        "patientUserId", patientUserId,
                        "callId", callId
                ));
            }

            return ResponseEntity.ok(Map.of(
                    "success", true,
                    "message", "SOS call sent successfully to all caregivers",
                    "patientUserId", patientUserId,
                    "patientName", patientName,
                    "callId", callId,
                    "emergencyType", emergencyType,
                    "notifiedCaregivers", notifiedCaregivers,
                    "timestamp", System.currentTimeMillis()
            ));

        } catch (Exception e) {
            log.error("Error sending SOS call", e);
            return ResponseEntity.badRequest().body(Map.of(
                    "success", false,
                    "message", "Failed to send SOS call: " + e.getMessage()
            ));
        }
    }
}
