package com.careconnect.controller;

import com.careconnect.model.CheckIn;
import com.careconnect.model.User;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.Role;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.CheckInService;
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

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.*;

/**
 * RBAC tests for CheckInController.
 * <p>
 * Tests that:
 * - GET /{id} enforces requireAdminOrCaregiver()
 * - GET / (getCheckIns) enforces requireAdminOrCaregiver()
 * - PUT /{id} enforces requireAdminOrCaregiver()
 * - POST / (patientCheckIn) requires resolveCurrentUser() (any authenticated user)
 * <p>
 * Uses pure Mockito to match CheckInControllerTest conventions.
 */
@ExtendWith(MockitoExtension.class)
@DisplayName("CheckInController RBAC Tests")
class CheckInControllerRbacTest {

    @Mock
    private CheckInService checkInService;

    @Mock
    private SecurityUtil securityUtil;

    @Mock
    private AuthorizationService authorizationService;

    @InjectMocks
    private CheckInController checkInController;

    private User makeUser(Long id, Role role) {
        final User u = new User();
        u.setId(id);
        u.setEmail("user" + id + "@test.com");
        u.setRole(role);
        return u;
    }

    // ── GET /v1/checkins/{id} - requireAdminOrCaregiver ───────────────────────

    @Nested
    @DisplayName("GET /{id} - requireAdminOrCaregiver")
    class GetCheckInById {

        @Test
        @DisplayName("ADMIN can access check-in by ID")
        void admin_canAccess() throws UnauthorizedException {
            final User admin = makeUser(1L, Role.ADMIN);
            when(securityUtil.resolveCurrentUser()).thenReturn(admin);
            when(checkInService.getCheckInByID(1L)).thenReturn(new CheckIn());

            final ResponseEntity<CheckIn> response = checkInController.getCheckIn(1L);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
            verify(authorizationService).requireAdminOrCaregiver(admin);
        }

        @Test
        @DisplayName("CAREGIVER can access check-in by ID")
        void caregiver_canAccess() throws UnauthorizedException {
            final User caregiver = makeUser(2L, Role.CAREGIVER);
            when(securityUtil.resolveCurrentUser()).thenReturn(caregiver);
            when(checkInService.getCheckInByID(1L)).thenReturn(new CheckIn());

            final ResponseEntity<CheckIn> response = checkInController.getCheckIn(1L);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
            verify(authorizationService).requireAdminOrCaregiver(caregiver);
        }

        @Test
        @DisplayName("PATIENT is denied check-in by ID - throws UnauthorizedException")
        void patient_isDenied() throws UnauthorizedException {
            final User patient = makeUser(3L, Role.PATIENT);
            when(securityUtil.resolveCurrentUser()).thenReturn(patient);
            doThrow(new UnauthorizedException("Admin or Caregiver access required. User 'user3@test.com' has role 'Patient'"))
                    .when(authorizationService).requireAdminOrCaregiver(patient);

            assertThatThrownBy(() -> checkInController.getCheckIn(1L))
                    .isInstanceOf(UnauthorizedException.class)
                    .hasMessageContaining("Admin or Caregiver access required");

            verifyNoInteractions(checkInService);
        }

        @Test
        @DisplayName("FAMILY_MEMBER is denied check-in by ID - throws UnauthorizedException")
        void familyMember_isDenied() throws UnauthorizedException {
            final User fm = makeUser(4L, Role.FAMILY_MEMBER);
            when(securityUtil.resolveCurrentUser()).thenReturn(fm);
            doThrow(new UnauthorizedException("Admin or Caregiver access required. User 'user4@test.com' has role 'Family Member'"))
                    .when(authorizationService).requireAdminOrCaregiver(fm);

            assertThatThrownBy(() -> checkInController.getCheckIn(1L))
                    .isInstanceOf(UnauthorizedException.class)
                    .hasMessageContaining("Admin or Caregiver access required");

            verifyNoInteractions(checkInService);
        }
    }

    // ── GET /v1/checkins - requireAdminOrCaregiver ────────────────────────────

    @Nested
    @DisplayName("GET / - requireAdminOrCaregiver")
    class GetAllCheckIns {

        @Test
        @DisplayName("ADMIN can access all check-ins")
        void admin_canAccess() throws UnauthorizedException {
            final User admin = makeUser(1L, Role.ADMIN);
            when(securityUtil.resolveCurrentUser()).thenReturn(admin);
            when(checkInService.getAllCheckIns()).thenReturn(List.of(new CheckIn()));

            final ResponseEntity<List<CheckIn>> response = checkInController.getCheckIns();

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
            verify(authorizationService).requireAdminOrCaregiver(admin);
        }

        @Test
        @DisplayName("CAREGIVER can access all check-ins")
        void caregiver_canAccess() throws UnauthorizedException {
            final User caregiver = makeUser(2L, Role.CAREGIVER);
            when(securityUtil.resolveCurrentUser()).thenReturn(caregiver);
            when(checkInService.getAllCheckIns()).thenReturn(List.of());

            final ResponseEntity<List<CheckIn>> response = checkInController.getCheckIns();

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
            verify(authorizationService).requireAdminOrCaregiver(caregiver);
        }

        @Test
        @DisplayName("PATIENT is denied all check-ins")
        void patient_isDenied() throws UnauthorizedException {
            final User patient = makeUser(3L, Role.PATIENT);
            when(securityUtil.resolveCurrentUser()).thenReturn(patient);
            doThrow(new UnauthorizedException("Admin or Caregiver access required"))
                    .when(authorizationService).requireAdminOrCaregiver(patient);

            assertThatThrownBy(() -> checkInController.getCheckIns())
                    .isInstanceOf(UnauthorizedException.class);

            verifyNoInteractions(checkInService);
        }

        @Test
        @DisplayName("FAMILY_MEMBER is denied all check-ins")
        void familyMember_isDenied() throws UnauthorizedException {
            final User fm = makeUser(4L, Role.FAMILY_MEMBER);
            when(securityUtil.resolveCurrentUser()).thenReturn(fm);
            doThrow(new UnauthorizedException("Admin or Caregiver access required"))
                    .when(authorizationService).requireAdminOrCaregiver(fm);

            assertThatThrownBy(() -> checkInController.getCheckIns())
                    .isInstanceOf(UnauthorizedException.class);

            verifyNoInteractions(checkInService);
        }
    }

    // ── PUT /v1/checkins/{id} - requireAdminOrCaregiver ───────────────────────

    @Nested
    @DisplayName("PUT /{id} - requireAdminOrCaregiver")
    class UpdateCheckIn {

        @Test
        @DisplayName("ADMIN can update check-in")
        void admin_canAccess() throws UnauthorizedException {
            final User admin = makeUser(1L, Role.ADMIN);
            when(securityUtil.resolveCurrentUser()).thenReturn(admin);

            final ResponseEntity<CheckIn> response = checkInController.updateCheckIn(1L);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
            verify(authorizationService).requireAdminOrCaregiver(admin);
        }

        @Test
        @DisplayName("PATIENT is denied check-in update")
        void patient_isDenied() throws UnauthorizedException {
            final User patient = makeUser(3L, Role.PATIENT);
            when(securityUtil.resolveCurrentUser()).thenReturn(patient);
            doThrow(new UnauthorizedException("Admin or Caregiver access required"))
                    .when(authorizationService).requireAdminOrCaregiver(patient);

            assertThatThrownBy(() -> checkInController.updateCheckIn(1L))
                    .isInstanceOf(UnauthorizedException.class);
        }
    }

    // ── POST /v1/checkins - resolveCurrentUser (any authenticated) ────────────

    @Nested
    @DisplayName("POST / - resolveCurrentUser (any authenticated user)")
    class PatientCheckIn {

        @Test
        @DisplayName("Authenticated user can perform patient check-in")
        void authenticated_canAccess() throws UnauthorizedException {
            final User patient = makeUser(3L, Role.PATIENT);
            when(securityUtil.resolveCurrentUser()).thenReturn(patient);

            final ResponseEntity<CheckIn> response = checkInController.patientCheckIn();

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
            verify(securityUtil).resolveCurrentUser();
        }

        @Test
        @DisplayName("Unauthenticated user throws RuntimeException")
        void unauthenticated_throwsException() {
            when(securityUtil.resolveCurrentUser())
                    .thenThrow(new RuntimeException("No authenticated user in SecurityContext"));

            assertThatThrownBy(() -> checkInController.patientCheckIn())
                    .isInstanceOf(RuntimeException.class)
                    .hasMessageContaining("No authenticated user");
        }
    }
}
