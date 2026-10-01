package com.careconnect.controller;

import com.careconnect.model.User;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.Role;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.WebSocketNotificationService;
import com.careconnect.util.SecurityUtil;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;

import java.util.HashMap;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.*;

/**
 * RBAC tests for WebSocketController.
 * <p>
 * Tests that the defense-in-depth resolveCurrentUser() calls on /init, /register-user,
 * /call-invitation, and /sms-notification throw RuntimeException when no authenticated
 * user is present. Also tests the existing role-based checks on other endpoints.
 */
@ExtendWith(MockitoExtension.class)
@DisplayName("WebSocketController RBAC Tests")
class WebSocketControllerRbacTest {

    @Mock
    private WebSocketNotificationService webSocketNotificationService;

    @Mock
    private SecurityUtil securityUtil;

    @Mock
    private AuthorizationService authorizationService;

    @InjectMocks
    private WebSocketController controller;

    private User makeUser(Role role) {
        final User u = new User();
        u.setId(1L);
        u.setEmail("user@test.com");
        u.setRole(role);
        return u;
    }

    // ── POST /init ────────────────────────────────────────────────────────────

    @Nested
    @DisplayName("POST /init - requires authenticated user")
    class InitEndpoint {

        @Test
        @DisplayName("Authenticated user can initialize")
        void authenticated_canAccess() {
            when(securityUtil.resolveCurrentUser()).thenReturn(makeUser(Role.PATIENT));

            final ResponseEntity<Map<String, Object>> response =
                    controller.initializeWebSocketService(null);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
            verify(securityUtil).resolveCurrentUser();
        }

        @Test
        @DisplayName("Unauthenticated user throws RuntimeException")
        void unauthenticated_throwsException() {
            when(securityUtil.resolveCurrentUser())
                    .thenThrow(new RuntimeException("No authenticated user in SecurityContext"));

            assertThatThrownBy(() -> controller.initializeWebSocketService(null))
                    .isInstanceOf(RuntimeException.class)
                    .hasMessageContaining("No authenticated user");
        }
    }

    // ── POST /register-user ───────────────────────────────────────────────────

    @Nested
    @DisplayName("POST /register-user - requires authenticated user")
    class RegisterUserEndpoint {

        @Test
        @DisplayName("Authenticated user can register")
        void authenticated_canAccess() {
            when(securityUtil.resolveCurrentUser()).thenReturn(makeUser(Role.CAREGIVER));

            final Map<String, Object> request = new HashMap<>();
            request.put("userId", "user1");
            request.put("userName", "Test User");

            final ResponseEntity<Map<String, Object>> response =
                    controller.registerUserForWebSocket(request);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
            verify(securityUtil).resolveCurrentUser();
        }

        @Test
        @DisplayName("Unauthenticated user throws RuntimeException")
        void unauthenticated_throwsException() {
            when(securityUtil.resolveCurrentUser())
                    .thenThrow(new RuntimeException("No authenticated user in SecurityContext"));

            final Map<String, Object> request = Map.of("userId", "user1", "userName", "Test");

            assertThatThrownBy(() -> controller.registerUserForWebSocket(request))
                    .isInstanceOf(RuntimeException.class)
                    .hasMessageContaining("No authenticated user");
        }
    }

    // ── POST /call-invitation ─────────────────────────────────────────────────

    @Nested
    @DisplayName("POST /call-invitation - requires authenticated user")
    class CallInvitationEndpoint {

        @Test
        @DisplayName("Authenticated user can send call invitation")
        void authenticated_canAccess() {
            when(securityUtil.resolveCurrentUser()).thenReturn(makeUser(Role.ADMIN));

            final Map<String, Object> request = new HashMap<>();
            request.put("recipientId", "r1");
            request.put("senderId", "s1");
            request.put("senderName", "Sender");
            request.put("callId", "call1");

            final ResponseEntity<Map<String, Object>> response =
                    controller.sendCallInvitation(request);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
            verify(securityUtil).resolveCurrentUser();
        }

        @Test
        @DisplayName("Unauthenticated user throws RuntimeException")
        void unauthenticated_throwsException() {
            when(securityUtil.resolveCurrentUser())
                    .thenThrow(new RuntimeException("No authenticated user in SecurityContext"));

            final Map<String, Object> request = Map.of("recipientId", "r1", "senderId", "s1");

            assertThatThrownBy(() -> controller.sendCallInvitation(request))
                    .isInstanceOf(RuntimeException.class)
                    .hasMessageContaining("No authenticated user");
        }
    }

    // ── POST /sms-notification ────────────────────────────────────────────────

    @Nested
    @DisplayName("POST /sms-notification - requires authenticated user")
    class SmsNotificationEndpoint {

        @Test
        @DisplayName("Authenticated user can send SMS notification")
        void authenticated_canAccess() {
            when(securityUtil.resolveCurrentUser()).thenReturn(makeUser(Role.FAMILY_MEMBER));

            final Map<String, Object> request = new HashMap<>();
            request.put("recipientId", "r1");
            request.put("senderId", "s1");
            request.put("senderName", "Sender");
            request.put("message", "Hello");

            final ResponseEntity<Map<String, Object>> response =
                    controller.sendSMSNotification(request);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
            verify(securityUtil).resolveCurrentUser();
        }

        @Test
        @DisplayName("Unauthenticated user throws RuntimeException")
        void unauthenticated_throwsException() {
            when(securityUtil.resolveCurrentUser())
                    .thenThrow(new RuntimeException("No authenticated user in SecurityContext"));

            final Map<String, Object> request = Map.of("recipientId", "r1");

            assertThatThrownBy(() -> controller.sendSMSNotification(request))
                    .isInstanceOf(RuntimeException.class)
                    .hasMessageContaining("No authenticated user");
        }
    }

    // ── POST /medication-reminder - requireAdminOrCaregiver ───────────────────

    @Nested
    @DisplayName("POST /medication-reminder - requireAdminOrCaregiver")
    class MedicationReminderEndpoint {

        @Test
        @DisplayName("ADMIN can send medication reminder")
        void admin_canAccess() throws UnauthorizedException {
            final User admin = makeUser(Role.ADMIN);
            when(securityUtil.resolveCurrentUser()).thenReturn(admin);

            final Map<String, Object> request = new HashMap<>();
            request.put("patientId", "p1");
            request.put("medicationName", "Aspirin");
            request.put("reminderTime", "08:00");
            request.put("dosage", "100mg");

            final ResponseEntity<Map<String, Object>> response =
                    controller.sendMedicationReminder(request);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
            verify(authorizationService).requireAdminOrCaregiver(admin);
        }

        @Test
        @DisplayName("CAREGIVER can send medication reminder")
        void caregiver_canAccess() throws UnauthorizedException {
            final User caregiver = makeUser(Role.CAREGIVER);
            when(securityUtil.resolveCurrentUser()).thenReturn(caregiver);

            final Map<String, Object> request = new HashMap<>();
            request.put("patientId", "p1");
            request.put("medicationName", "Aspirin");
            request.put("reminderTime", "08:00");
            request.put("dosage", "100mg");

            final ResponseEntity<Map<String, Object>> response =
                    controller.sendMedicationReminder(request);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        }

        @Test
        @DisplayName("PATIENT is denied - throws UnauthorizedException")
        void patient_isDenied() throws UnauthorizedException {
            final User patient = makeUser(Role.PATIENT);
            when(securityUtil.resolveCurrentUser()).thenReturn(patient);
            doThrow(new UnauthorizedException("Admin or Caregiver access required"))
                    .when(authorizationService).requireAdminOrCaregiver(patient);

            final Map<String, Object> request = new HashMap<>();
            request.put("patientId", "p1");

            assertThatThrownBy(() -> controller.sendMedicationReminder(request))
                    .isInstanceOf(UnauthorizedException.class)
                    .hasMessageContaining("Admin or Caregiver access required");
        }

        @Test
        @DisplayName("FAMILY_MEMBER is denied - throws UnauthorizedException")
        void familyMember_isDenied() throws UnauthorizedException {
            final User fm = makeUser(Role.FAMILY_MEMBER);
            when(securityUtil.resolveCurrentUser()).thenReturn(fm);
            doThrow(new UnauthorizedException("Admin or Caregiver access required"))
                    .when(authorizationService).requireAdminOrCaregiver(fm);

            final Map<String, Object> request = new HashMap<>();
            request.put("patientId", "p1");

            assertThatThrownBy(() -> controller.sendMedicationReminder(request))
                    .isInstanceOf(UnauthorizedException.class);
        }
    }

    // ── POST /system-announcement - requireAdmin ──────────────────────────────

    @Nested
    @DisplayName("POST /system-announcement - requireAdmin")
    class SystemAnnouncementEndpoint {

        @Test
        @DisplayName("ADMIN can broadcast system announcement")
        void admin_canAccess() throws UnauthorizedException {
            final User admin = makeUser(Role.ADMIN);
            when(securityUtil.resolveCurrentUser()).thenReturn(admin);
            when(webSocketNotificationService.getOnlineUsersCount()).thenReturn(5);

            final Map<String, Object> request = new HashMap<>();
            request.put("title", "Maintenance");
            request.put("message", "System maintenance tonight");

            final ResponseEntity<Map<String, Object>> response =
                    controller.broadcastSystemAnnouncement(request);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
            verify(authorizationService).requireAdmin(admin);
        }

        @Test
        @DisplayName("CAREGIVER is denied - throws UnauthorizedException")
        void caregiver_isDenied() throws UnauthorizedException {
            final User caregiver = makeUser(Role.CAREGIVER);
            when(securityUtil.resolveCurrentUser()).thenReturn(caregiver);
            doThrow(new UnauthorizedException("Admin access required"))
                    .when(authorizationService).requireAdmin(caregiver);

            final Map<String, Object> request = Map.of("title", "Test", "message", "Test");

            assertThatThrownBy(() -> controller.broadcastSystemAnnouncement(request))
                    .isInstanceOf(UnauthorizedException.class)
                    .hasMessageContaining("Admin access required");
        }
    }

    // ── GET /online-users - requireAdmin ──────────────────────────────────────

    @Nested
    @DisplayName("GET /online-users - requireAdmin")
    class OnlineUsersEndpoint {

        @Test
        @DisplayName("ADMIN can get online users")
        void admin_canAccess() throws UnauthorizedException {
            final User admin = makeUser(Role.ADMIN);
            when(securityUtil.resolveCurrentUser()).thenReturn(admin);
            when(webSocketNotificationService.getOnlineUsers()).thenReturn(Map.of());
            when(webSocketNotificationService.getOnlineUsersCount()).thenReturn(0);

            final ResponseEntity<Map<String, Object>> response =
                    controller.getOnlineUsers();

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
            verify(authorizationService).requireAdmin(admin);
        }

        @Test
        @DisplayName("PATIENT is denied - throws UnauthorizedException")
        void patient_isDenied() throws UnauthorizedException {
            final User patient = makeUser(Role.PATIENT);
            when(securityUtil.resolveCurrentUser()).thenReturn(patient);
            doThrow(new UnauthorizedException("Admin access required"))
                    .when(authorizationService).requireAdmin(patient);

            assertThatThrownBy(() -> controller.getOnlineUsers())
                    .isInstanceOf(UnauthorizedException.class);
        }
    }

    // ── GET /user-status/{userId} - requireAdminOrCaregiver ───────────────────

    @Nested
    @DisplayName("GET /user-status/{userId} - requireAdminOrCaregiver")
    class UserStatusEndpoint {

        @Test
        @DisplayName("ADMIN can check user status")
        void admin_canAccess() throws UnauthorizedException {
            final User admin = makeUser(Role.ADMIN);
            when(securityUtil.resolveCurrentUser()).thenReturn(admin);
            when(webSocketNotificationService.isUserOnline("user1")).thenReturn(true);

            final ResponseEntity<Map<String, Object>> response =
                    controller.getUserOnlineStatus("user1");

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
            verify(authorizationService).requireAdminOrCaregiver(admin);
        }

        @Test
        @DisplayName("PATIENT is denied - throws UnauthorizedException")
        void patient_isDenied() throws UnauthorizedException {
            final User patient = makeUser(Role.PATIENT);
            when(securityUtil.resolveCurrentUser()).thenReturn(patient);
            doThrow(new UnauthorizedException("Admin or Caregiver access required"))
                    .when(authorizationService).requireAdminOrCaregiver(patient);

            assertThatThrownBy(() -> controller.getUserOnlineStatus("user1"))
                    .isInstanceOf(UnauthorizedException.class);
        }
    }

    // ── POST /sos-call - patient only ─────────────────────────────────────────

    @Nested
    @DisplayName("POST /sos-call - patient only")
    class SosCallEndpoint {

        @Test
        @DisplayName("PATIENT can initiate SOS call")
        void patient_canAccess() throws UnauthorizedException {
            final User patient = makeUser(Role.PATIENT);
            when(securityUtil.resolveCurrentUser()).thenReturn(patient);
            when(webSocketNotificationService.sendSOSCallToAllCaregivers(
                    any(), any(), any(), any(), any(), any(), anyBoolean())).thenReturn(2);

            final Map<String, Object> request = new HashMap<>();
            request.put("patientUserId", "p1");
            request.put("patientName", "Patient One");
            request.put("callId", "call1");

            final ResponseEntity<Map<String, Object>> response =
                    controller.sendSOSCall(request);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        }

        @Test
        @DisplayName("ADMIN is denied SOS call - throws UnauthorizedException")
        void admin_isDenied() {
            final User admin = makeUser(Role.ADMIN);
            when(securityUtil.resolveCurrentUser()).thenReturn(admin);

            final Map<String, Object> request = new HashMap<>();
            request.put("patientUserId", "p1");
            request.put("patientName", "Patient One");
            request.put("callId", "call1");

            assertThatThrownBy(() -> controller.sendSOSCall(request))
                    .isInstanceOf(UnauthorizedException.class)
                    .hasMessageContaining("Only patients can initiate SOS calls");
        }

        @Test
        @DisplayName("CAREGIVER is denied SOS call - throws UnauthorizedException")
        void caregiver_isDenied() {
            final User caregiver = makeUser(Role.CAREGIVER);
            when(securityUtil.resolveCurrentUser()).thenReturn(caregiver);

            final Map<String, Object> request = new HashMap<>();
            request.put("patientUserId", "p1");

            assertThatThrownBy(() -> controller.sendSOSCall(request))
                    .isInstanceOf(UnauthorizedException.class)
                    .hasMessageContaining("Only patients can initiate SOS calls");
        }
    }
}
