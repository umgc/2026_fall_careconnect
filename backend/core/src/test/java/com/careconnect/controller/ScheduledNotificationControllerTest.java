package com.careconnect.controller;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doNothing;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.careconnect.dto.ScheduledNotificationDTO;
import com.careconnect.model.ScheduledNotification;
import com.careconnect.model.User;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.Role;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.ScheduledNotificationService;
import com.careconnect.util.SecurityUtil;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;

import java.time.LocalDateTime;
import java.util.List;

@ExtendWith(MockitoExtension.class)
class ScheduledNotificationControllerTest {

    @Mock
    private ScheduledNotificationService scheduledNotificationService;

    @Mock
    private SecurityUtil securityUtil;

    @Mock
    private AuthorizationService authorizationService;

    @InjectMocks
    private ScheduledNotificationController controller;

    private User caregiverUser;
    private User adminUser;

    @BeforeEach
    void setUp() {
        caregiverUser = new User();
        caregiverUser.setId(10L);
        caregiverUser.setEmail("caregiver@test.com");
        caregiverUser.setRole(Role.CAREGIVER);

        adminUser = new User();
        adminUser.setId(1L);
        adminUser.setEmail("admin@test.com");
        adminUser.setRole(Role.ADMIN);
    }

    private ScheduledNotification buildNotification(Long receiverId, String title, String body,
                                                    String type, LocalDateTime scheduledTime) {
        return ScheduledNotification.builder()
                .id(100L)
                .receiverId(receiverId)
                .title(title)
                .body(body)
                .notificationType(type)
                .scheduledTime(scheduledTime)
                .status("PENDING")
                .build();
    }

    // =========================================================================
    // POST / (createScheduledNotification)
    // =========================================================================

    @Test
    @DisplayName("createScheduledNotification returns OK with DTO on success")
    void createScheduledNotification_success() throws UnauthorizedException {
        when(securityUtil.resolveCurrentUser()).thenReturn(caregiverUser);
        doNothing().when(authorizationService).requireAdminOrCaregiver(caregiverUser);

        LocalDateTime scheduledTime = LocalDateTime.of(2026, 4, 1, 10, 0);
        ScheduledNotification notification = buildNotification(
                5L, "Reminder", "Take your meds", "REMINDER", scheduledTime);

        when(scheduledNotificationService.createScheduledNotification(
                eq(null), eq(5L), eq("Reminder"), eq("Take your meds"),
                eq(scheduledTime), eq("REMINDER")))
                .thenReturn(notification);

        ScheduledNotificationDTO dto = new ScheduledNotificationDTO(
                5L, "Reminder", "Take your meds", "REMINDER", "2026-04-01T10:00:00");

        ResponseEntity<ScheduledNotificationDTO> response =
                controller.createScheduledNotification(dto);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        ScheduledNotificationDTO result = response.getBody();
        assertThat(result).isNotNull();
        assertThat(result.getReceiverId()).isEqualTo(5L);
        assertThat(result.getTitle()).isEqualTo("Reminder");
        assertThat(result.getBody()).isEqualTo("Take your meds");
        assertThat(result.getNotificationType()).isEqualTo("REMINDER");
    }

    @Test
    @DisplayName("createScheduledNotification throws UnauthorizedException for non-caregiver/admin")
    void createScheduledNotification_unauthorized() throws UnauthorizedException {
        User patientUser = new User();
        patientUser.setId(20L);
        patientUser.setRole(Role.PATIENT);

        when(securityUtil.resolveCurrentUser()).thenReturn(patientUser);
        doThrow(new UnauthorizedException("Unauthorized"))
                .when(authorizationService).requireAdminOrCaregiver(patientUser);

        ScheduledNotificationDTO dto = new ScheduledNotificationDTO(
                5L, "Reminder", "Body", "REMINDER", "2026-04-01T10:00:00");

        assertThatThrownBy(() -> controller.createScheduledNotification(dto))
                .isInstanceOf(UnauthorizedException.class);
    }

    @Test
    @DisplayName("createScheduledNotification with null notification type")
    void createScheduledNotification_nullType() throws UnauthorizedException {
        when(securityUtil.resolveCurrentUser()).thenReturn(caregiverUser);
        doNothing().when(authorizationService).requireAdminOrCaregiver(caregiverUser);

        LocalDateTime scheduledTime = LocalDateTime.of(2026, 5, 1, 8, 30);
        ScheduledNotification notification = buildNotification(
                5L, "Check-in", "How are you?", null, scheduledTime);

        when(scheduledNotificationService.createScheduledNotification(
                eq(null), eq(5L), eq("Check-in"), eq("How are you?"),
                eq(scheduledTime), eq(null)))
                .thenReturn(notification);

        ScheduledNotificationDTO dto = new ScheduledNotificationDTO(
                5L, "Check-in", "How are you?", null, "2026-05-01T08:30:00");

        ResponseEntity<ScheduledNotificationDTO> response =
                controller.createScheduledNotification(dto);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isNotNull();
        assertThat(response.getBody().getNotificationType()).isNull();
    }

    // =========================================================================
    // GET /user/{userId} (getUserNotifications)
    // =========================================================================

    @Test
    @DisplayName("getUserNotifications returns list of DTOs")
    void getUserNotifications_success() throws UnauthorizedException {
        when(securityUtil.resolveCurrentUser()).thenReturn(adminUser);
        doNothing().when(authorizationService).requireSelfOrAdmin(adminUser, 5L);

        LocalDateTime time1 = LocalDateTime.of(2026, 4, 1, 10, 0);
        LocalDateTime time2 = LocalDateTime.of(2026, 4, 2, 14, 0);
        List<ScheduledNotification> notifications = List.of(
                buildNotification(5L, "Title1", "Body1", "REMINDER", time1),
                buildNotification(5L, "Title2", "Body2", "ALERT", time2));
        when(scheduledNotificationService.getUserNotifications(5L)).thenReturn(notifications);

        ResponseEntity<List<ScheduledNotificationDTO>> response =
                controller.getUserNotifications(5L);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).hasSize(2);
        assertThat(response.getBody().get(0).getTitle()).isEqualTo("Title1");
        assertThat(response.getBody().get(1).getTitle()).isEqualTo("Title2");
    }

    @Test
    @DisplayName("getUserNotifications returns empty list when no notifications")
    void getUserNotifications_emptyList() throws UnauthorizedException {
        when(securityUtil.resolveCurrentUser()).thenReturn(adminUser);
        doNothing().when(authorizationService).requireSelfOrAdmin(adminUser, 5L);
        when(scheduledNotificationService.getUserNotifications(5L)).thenReturn(List.of());

        ResponseEntity<List<ScheduledNotificationDTO>> response =
                controller.getUserNotifications(5L);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isEmpty();
    }

    @Test
    @DisplayName("getUserNotifications throws UnauthorizedException when not self or admin")
    void getUserNotifications_unauthorized() throws UnauthorizedException {
        User otherUser = new User();
        otherUser.setId(99L);
        otherUser.setRole(Role.PATIENT);

        when(securityUtil.resolveCurrentUser()).thenReturn(otherUser);
        doThrow(new UnauthorizedException("Not allowed"))
                .when(authorizationService).requireSelfOrAdmin(otherUser, 5L);

        assertThatThrownBy(() -> controller.getUserNotifications(5L))
                .isInstanceOf(UnauthorizedException.class);
    }

    // =========================================================================
    // POST /medication-reminder/{patientId}
    // =========================================================================

    @Test
    @DisplayName("createMedicationReminders returns list of DTOs on success")
    void createMedicationReminders_success() throws UnauthorizedException {
        when(securityUtil.resolveCurrentUser()).thenReturn(caregiverUser);
        doNothing().when(authorizationService).requireAdminOrCaregiver(caregiverUser);

        LocalDateTime time1 = LocalDateTime.of(2026, 4, 1, 8, 0);
        LocalDateTime time2 = LocalDateTime.of(2026, 4, 1, 20, 0);

        List<ScheduledNotification> notifications = List.of(
                buildNotification(42L, "Med Reminder", "Take Aspirin (100mg)", "MEDICATION_REMINDER", time1),
                buildNotification(42L, "Med Reminder", "Take Aspirin (100mg)", "MEDICATION_REMINDER", time2));
        when(scheduledNotificationService.createMedicationReminders(
                eq(42L), eq("Aspirin"), eq("100mg"), any()))
                .thenReturn(notifications);

        List<String> times = List.of("2026-04-01T08:00:00", "2026-04-01T20:00:00");

        ResponseEntity<List<ScheduledNotificationDTO>> response =
                controller.createMedicationReminders(42L, "Aspirin", "100mg", times);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).hasSize(2);
    }

    @Test
    @DisplayName("createMedicationReminders throws UnauthorizedException for patient role")
    void createMedicationReminders_unauthorized() throws UnauthorizedException {
        User patientUser = new User();
        patientUser.setId(20L);
        patientUser.setRole(Role.PATIENT);

        when(securityUtil.resolveCurrentUser()).thenReturn(patientUser);
        doThrow(new UnauthorizedException("Unauthorized"))
                .when(authorizationService).requireAdminOrCaregiver(patientUser);

        assertThatThrownBy(() ->
                controller.createMedicationReminders(42L, "Aspirin", "100mg",
                        List.of("2026-04-01T08:00:00")))
                .isInstanceOf(UnauthorizedException.class);
    }

    @Test
    @DisplayName("createMedicationReminders returns empty list when service returns empty")
    void createMedicationReminders_emptyResult() throws UnauthorizedException {
        when(securityUtil.resolveCurrentUser()).thenReturn(caregiverUser);
        doNothing().when(authorizationService).requireAdminOrCaregiver(caregiverUser);
        when(scheduledNotificationService.createMedicationReminders(
                eq(42L), eq("Aspirin"), eq("100mg"), any()))
                .thenReturn(List.of());

        ResponseEntity<List<ScheduledNotificationDTO>> response =
                controller.createMedicationReminders(42L, "Aspirin", "100mg", List.of());

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isEmpty();
    }

    // =========================================================================
    // POST /appointment-reminder/{patientId}
    // =========================================================================

    @Test
    @DisplayName("createAppointmentReminder returns DTO on success")
    void createAppointmentReminder_success() throws UnauthorizedException {
        when(securityUtil.resolveCurrentUser()).thenReturn(caregiverUser);
        doNothing().when(authorizationService).requireAdminOrCaregiver(caregiverUser);

        LocalDateTime appointmentTime = LocalDateTime.of(2026, 4, 15, 9, 30);
        ScheduledNotification notification = buildNotification(
                42L, "Appointment Reminder", "Doctor visit at Clinic A",
                "APPOINTMENT_REMINDER", appointmentTime.minusHours(24));

        when(scheduledNotificationService.createAppointmentReminder(
                eq(42L), eq("Checkup"), eq(appointmentTime), eq("Clinic A")))
                .thenReturn(notification);

        ResponseEntity<ScheduledNotificationDTO> response =
                controller.createAppointmentReminder(42L, "Checkup",
                        "2026-04-15T09:30:00", "Clinic A");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isNotNull();
        assertThat(response.getBody().getReceiverId()).isEqualTo(42L);
    }

    @Test
    @DisplayName("createAppointmentReminder throws UnauthorizedException for patient role")
    void createAppointmentReminder_unauthorized() throws UnauthorizedException {
        User patientUser = new User();
        patientUser.setId(20L);
        patientUser.setRole(Role.PATIENT);

        when(securityUtil.resolveCurrentUser()).thenReturn(patientUser);
        doThrow(new UnauthorizedException("Unauthorized"))
                .when(authorizationService).requireAdminOrCaregiver(patientUser);

        assertThatThrownBy(() ->
                controller.createAppointmentReminder(42L, "Checkup",
                        "2026-04-15T09:30:00", "Clinic A"))
                .isInstanceOf(UnauthorizedException.class);
    }

    // =========================================================================
    // DELETE /{notificationId} (cancelScheduledNotification)
    // =========================================================================

    @Test
    @DisplayName("cancelScheduledNotification returns 204 on success")
    void cancelScheduledNotification_success() throws UnauthorizedException {
        when(securityUtil.resolveCurrentUser()).thenReturn(caregiverUser);
        doNothing().when(authorizationService).requireAdminOrCaregiver(caregiverUser);
        doNothing().when(scheduledNotificationService).cancelScheduledNotification(100L);

        ResponseEntity<Void> response = controller.cancelScheduledNotification(100L);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.NO_CONTENT);
        verify(scheduledNotificationService).cancelScheduledNotification(100L);
    }

    @Test
    @DisplayName("cancelScheduledNotification throws UnauthorizedException for non-admin/caregiver")
    void cancelScheduledNotification_unauthorized() throws UnauthorizedException {
        User patientUser = new User();
        patientUser.setId(20L);
        patientUser.setRole(Role.PATIENT);

        when(securityUtil.resolveCurrentUser()).thenReturn(patientUser);
        doThrow(new UnauthorizedException("Unauthorized"))
                .when(authorizationService).requireAdminOrCaregiver(patientUser);

        assertThatThrownBy(() -> controller.cancelScheduledNotification(100L))
                .isInstanceOf(UnauthorizedException.class);
    }

    @Test
    @DisplayName("cancelScheduledNotification propagates exception when notification not found")
    void cancelScheduledNotification_notFound() throws UnauthorizedException {
        when(securityUtil.resolveCurrentUser()).thenReturn(caregiverUser);
        doNothing().when(authorizationService).requireAdminOrCaregiver(caregiverUser);
        doThrow(new IllegalArgumentException("Notification not found: 999"))
                .when(scheduledNotificationService).cancelScheduledNotification(999L);

        assertThatThrownBy(() -> controller.cancelScheduledNotification(999L))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("Notification not found: 999");
    }

    // =========================================================================
    // POST /bulk (createBulkNotifications) - stub/TODO endpoint
    // =========================================================================

    @Test
    @DisplayName("createBulkNotifications returns empty list (not yet implemented)")
    void createBulkNotifications_returnsEmptyList() {
        List<ScheduledNotificationDTO> dtos = List.of(
                new ScheduledNotificationDTO(1L, "T", "B", "R", "2026-04-01T10:00:00"));

        ResponseEntity<List<ScheduledNotificationDTO>> response =
                controller.createBulkNotifications(dtos);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isEmpty();
    }

    // =========================================================================
    // POST /recurring (createRecurringNotifications) - stub/TODO endpoint
    // =========================================================================

    @Test
    @DisplayName("createRecurringNotifications returns empty list (not yet implemented)")
    void createRecurringNotifications_returnsEmptyList() {
        ResponseEntity<List<ScheduledNotificationDTO>> response =
                controller.createRecurringNotifications(
                        1L, 2L, "Title", "Body",
                        "2026-04-01T10:00:00", "2026-05-01T10:00:00",
                        "DAILY", "REMINDER");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isEmpty();
    }
}
