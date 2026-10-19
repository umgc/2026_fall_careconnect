package com.careconnect.controller;

import com.careconnect.dto.ScheduledNotificationDTO;
import com.careconnect.model.ScheduledNotification;
import com.careconnect.model.User;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.RequirePermission;
import com.careconnect.security.Permission;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.ScheduledNotificationService;
import com.careconnect.util.SecurityUtil;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDateTime;
import java.util.List;
import java.util.stream.Collectors;

@RestController
@RequestMapping("/v1/api/scheduled-notifications")
@Tag(name = "Scheduled Notifications", description = "Manage scheduled notifications for automated reminders")
@RequiredArgsConstructor
public class ScheduledNotificationController {

    private final ScheduledNotificationService scheduledNotificationService;
    private final SecurityUtil securityUtil;
    private final AuthorizationService authorizationService;

    @RequirePermission(Permission.CREATE_TASKS)
    @PostMapping
    @Operation(summary = "Create a scheduled notification")
    public ResponseEntity<ScheduledNotificationDTO> createScheduledNotification(@RequestBody ScheduledNotificationDTO dto) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdminOrCaregiver(currentUser);

        ScheduledNotification notification = scheduledNotificationService.createScheduledNotification(
                null, // taskId - could be added to DTO
                dto.getReceiverId(),
                dto.getTitle(),
                dto.getBody(),
                LocalDateTime.parse(dto.getScheduledTime()),
                dto.getNotificationType()
        );

        return ResponseEntity.ok(toDTO(notification));
    }

    @RequirePermission(Permission.VIEW_ASSIGNED_PATIENTS)
    @GetMapping("/user/{userId}")
    @Operation(summary = "Get scheduled notifications for a user")
    public ResponseEntity<List<ScheduledNotificationDTO>> getUserNotifications(@PathVariable Long userId) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireSelfOrAdmin(currentUser, userId);

        List<ScheduledNotification> notifications = scheduledNotificationService.getUserNotifications(userId);
        List<ScheduledNotificationDTO> dtos = notifications.stream()
                .map(this::toDTO)
                .collect(Collectors.toList());

        return ResponseEntity.ok(dtos);
    }

    @RequirePermission(Permission.CREATE_TASKS)
    @PostMapping("/medication-reminder/{patientId}")
    @Operation(summary = "Create medication reminder notifications")
    public ResponseEntity<List<ScheduledNotificationDTO>> createMedicationReminders(
            @PathVariable Long patientId,
            @RequestParam String medicationName,
            @RequestParam String dosage,
            @RequestBody List<String> reminderTimes) throws UnauthorizedException {

        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdminOrCaregiver(currentUser);

        List<LocalDateTime> times = reminderTimes.stream()
                .map(LocalDateTime::parse)
                .collect(Collectors.toList());

        List<ScheduledNotification> notifications = scheduledNotificationService.createMedicationReminders(
                patientId, medicationName, dosage, times);

        List<ScheduledNotificationDTO> dtos = notifications.stream()
                .map(this::toDTO)
                .collect(Collectors.toList());

        return ResponseEntity.ok(dtos);
    }

    @RequirePermission(Permission.CREATE_TASKS)
    @PostMapping("/appointment-reminder/{patientId}")
    @Operation(summary = "Create appointment reminder notification")
    public ResponseEntity<ScheduledNotificationDTO> createAppointmentReminder(
            @PathVariable Long patientId,
            @RequestParam String appointmentType,
            @RequestParam String appointmentTime,
            @RequestParam String location) throws UnauthorizedException {

        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdminOrCaregiver(currentUser);

        ScheduledNotification notification = scheduledNotificationService.createAppointmentReminder(
                patientId, appointmentType, LocalDateTime.parse(appointmentTime), location);

        return ResponseEntity.ok(toDTO(notification));
    }

    @RequirePermission(Permission.CREATE_TASKS)
    @DeleteMapping("/{notificationId}")
    @Operation(summary = "Cancel a scheduled notification")
    public ResponseEntity<Void> cancelScheduledNotification(@PathVariable Long notificationId) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdminOrCaregiver(currentUser);

        scheduledNotificationService.cancelScheduledNotification(notificationId);
        return ResponseEntity.noContent().build();
    }

    // Future enhancement: Bulk operations
    @PostMapping("/bulk")
    @Operation(summary = "Create multiple scheduled notifications")
    public ResponseEntity<List<ScheduledNotificationDTO>> createBulkNotifications(@RequestBody List<ScheduledNotificationDTO> dtos) {
        // TODO: Implement bulk creation
        return ResponseEntity.ok(List.of());
    }

    // Future enhancement: Recurring notifications
    @PostMapping("/recurring")
    @Operation(summary = "Create recurring scheduled notifications")
    public ResponseEntity<List<ScheduledNotificationDTO>> createRecurringNotifications(
            @RequestParam Long taskId,
            @RequestParam Long receiverId,
            @RequestParam String title,
            @RequestParam String body,
            @RequestParam String startTime,
            @RequestParam String endTime,
            @RequestParam String frequency,
            @RequestParam String notificationType) {
        // TODO: Implement recurring notifications
        return ResponseEntity.ok(List.of());
    }

    private ScheduledNotificationDTO toDTO(ScheduledNotification notification) {
        return new ScheduledNotificationDTO(
                notification.getReceiverId(),
                notification.getTitle(),
                notification.getBody(),
                notification.getNotificationType(),
                notification.getScheduledTime().toString()
        );
    }
}