package com.careconnect.security;

import com.careconnect.model.Patient;
import com.careconnect.model.Task;
import com.careconnect.model.User;
import com.careconnect.repository.CaregiverPatientLinkRepository;
import com.careconnect.repository.FamilyMemberLinkRepository;
import com.careconnect.repository.PatientRepository;
import com.careconnect.security.Role;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.LocalDateTime;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
public class AuthorizationServiceTest {

    private AuthorizationService authorizationService;
    private User mockUser;
    private CaregiverPatientLinkRepository caregiverPatientLinkRepository;
    private FamilyMemberLinkRepository familyMemberLinkRepository;
    private PatientRepository patientRepository;

    @BeforeEach
    void setUp() {
        caregiverPatientLinkRepository = mock(CaregiverPatientLinkRepository.class);
        familyMemberLinkRepository = mock(FamilyMemberLinkRepository.class);
        patientRepository = mock(PatientRepository.class);
        authorizationService = new AuthorizationService(
                caregiverPatientLinkRepository, familyMemberLinkRepository, patientRepository);
        mockUser = mock(User.class);
        lenient().when(mockUser.getEmail()).thenReturn("test@example.com");
        lenient().when(mockUser.getId()).thenReturn(1L);
        lenient().when(mockUser.getRole()).thenReturn(Role.PATIENT);
    }

    // ========== requirePermission Tests ==========

    @Nested
    @DisplayName("requirePermission")
    class RequirePermissionTests {

        @Test
        @DisplayName("Should throw when user is null")
        void shouldThrowWhenUserIsNull() {
            UnauthorizedException ex = assertThrows(UnauthorizedException.class,
                    () -> authorizationService.requirePermission(null, Permission.CREATE_TASKS));
            assertEquals("User is not authenticated", ex.getMessage());
        }

        @Test
        @DisplayName("Should throw when user lacks permission")
        void shouldThrowWhenUserLacksPermission() {
            when(mockUser.hasPermission(Permission.CREATE_TASKS)).thenReturn(false);

            UnauthorizedException ex = assertThrows(UnauthorizedException.class,
                    () -> authorizationService.requirePermission(mockUser, Permission.CREATE_TASKS));
            assertTrue(ex.getMessage().contains("test@example.com"));
            assertTrue(ex.getMessage().contains("CREATE_TASKS"));
        }

        @Test
        @DisplayName("Should pass when user has permission")
        void shouldPassWhenUserHasPermission() {
            when(mockUser.hasPermission(Permission.CREATE_TASKS)).thenReturn(true);

            assertDoesNotThrow(
                    () -> authorizationService.requirePermission(mockUser, Permission.CREATE_TASKS));
        }
    }

    // ========== requireAllPermissions Tests ==========

    @Nested
    @DisplayName("requireAllPermissions")
    class RequireAllPermissionsTests {

        @Test
        @DisplayName("Should throw when user is null")
        void shouldThrowWhenUserIsNull() {
            UnauthorizedException ex = assertThrows(UnauthorizedException.class,
                    () -> authorizationService.requireAllPermissions(null, Permission.CREATE_TASKS, Permission.VIEW_TASKS));
            assertEquals("User is not authenticated", ex.getMessage());
        }

        @Test
        @DisplayName("Should throw when user is missing one permission")
        void shouldThrowWhenUserMissingPermission() {
            when(mockUser.hasPermission(Permission.CREATE_TASKS)).thenReturn(true);
            when(mockUser.hasPermission(Permission.VIEW_TASKS)).thenReturn(false);

            UnauthorizedException ex = assertThrows(UnauthorizedException.class,
                    () -> authorizationService.requireAllPermissions(mockUser, Permission.CREATE_TASKS, Permission.VIEW_TASKS));
            assertTrue(ex.getMessage().contains("VIEW_TASKS"));
        }

        @Test
        @DisplayName("Should pass when user has all permissions")
        void shouldPassWhenUserHasAllPermissions() {
            when(mockUser.hasPermission(Permission.CREATE_TASKS)).thenReturn(true);
            when(mockUser.hasPermission(Permission.VIEW_TASKS)).thenReturn(true);

            assertDoesNotThrow(
                    () -> authorizationService.requireAllPermissions(mockUser, Permission.CREATE_TASKS, Permission.VIEW_TASKS));
        }
    }

    // ========== requireAnyPermission Tests ==========

    @Nested
    @DisplayName("requireAnyPermission")
    class RequireAnyPermissionTests {

        @Test
        @DisplayName("Should throw when user is null")
        void shouldThrowWhenUserIsNull() {
            UnauthorizedException ex = assertThrows(UnauthorizedException.class,
                    () -> authorizationService.requireAnyPermission(null, Permission.CREATE_TASKS));
            assertEquals("User is not authenticated", ex.getMessage());
        }

        @Test
        @DisplayName("Should throw when user has none of the permissions - single permission")
        void shouldThrowWhenUserHasNoPermissionsSingle() {
            when(mockUser.hasAnyPermission(Permission.CREATE_TASKS)).thenReturn(false);

            UnauthorizedException ex = assertThrows(UnauthorizedException.class,
                    () -> authorizationService.requireAnyPermission(mockUser, Permission.CREATE_TASKS));
            assertTrue(ex.getMessage().contains("CREATE_TASKS"));
            assertFalse(ex.getMessage().contains(", "));
        }

        @Test
        @DisplayName("Should throw when user has none of the permissions - multiple permissions")
        void shouldThrowWhenUserHasNoPermissionsMultiple() {
            when(mockUser.hasAnyPermission(Permission.CREATE_TASKS, Permission.VIEW_TASKS)).thenReturn(false);

            UnauthorizedException ex = assertThrows(UnauthorizedException.class,
                    () -> authorizationService.requireAnyPermission(mockUser, Permission.CREATE_TASKS, Permission.VIEW_TASKS));
            assertTrue(ex.getMessage().contains("CREATE_TASKS, VIEW_TASKS"));
        }

        @Test
        @DisplayName("Should pass when user has at least one permission")
        void shouldPassWhenUserHasAnyPermission() {
            when(mockUser.hasAnyPermission(Permission.CREATE_TASKS, Permission.VIEW_TASKS)).thenReturn(true);

            assertDoesNotThrow(
                    () -> authorizationService.requireAnyPermission(mockUser, Permission.CREATE_TASKS, Permission.VIEW_TASKS));
        }
    }

    // ========== requireAdmin Tests ==========

    @Nested
    @DisplayName("requireAdmin")
    class RequireAdminTests {

        @Test
        @DisplayName("Should throw when user is null")
        void shouldThrowWhenUserIsNull() {
            UnauthorizedException ex = assertThrows(UnauthorizedException.class,
                    () -> authorizationService.requireAdmin(null));
            assertEquals("User is not authenticated", ex.getMessage());
        }

        @Test
        @DisplayName("Should throw when user is not admin")
        void shouldThrowWhenUserIsNotAdmin() {
            when(mockUser.isAdmin()).thenReturn(false);
            when(mockUser.getRole()).thenReturn(Role.CAREGIVER);

            UnauthorizedException ex = assertThrows(UnauthorizedException.class,
                    () -> authorizationService.requireAdmin(mockUser));
            assertTrue(ex.getMessage().contains("Admin access required"));
            assertTrue(ex.getMessage().contains("Caregiver"));
        }

        @Test
        @DisplayName("Should pass when user is admin")
        void shouldPassWhenUserIsAdmin() {
            when(mockUser.isAdmin()).thenReturn(true);

            assertDoesNotThrow(() -> authorizationService.requireAdmin(mockUser));
        }
    }

    // ========== requireCaregiver Tests ==========

    @Nested
    @DisplayName("requireCaregiver")
    class RequireCaregiverTests {

        @Test
        @DisplayName("Should throw when user is null")
        void shouldThrowWhenUserIsNull() {
            UnauthorizedException ex = assertThrows(UnauthorizedException.class,
                    () -> authorizationService.requireCaregiver(null));
            assertEquals("User is not authenticated", ex.getMessage());
        }

        @Test
        @DisplayName("Should throw when user is not caregiver")
        void shouldThrowWhenUserIsNotCaregiver() {
            when(mockUser.isCaregiver()).thenReturn(false);

            UnauthorizedException ex = assertThrows(UnauthorizedException.class,
                    () -> authorizationService.requireCaregiver(mockUser));
            assertTrue(ex.getMessage().contains("Caregiver access required"));
        }

        @Test
        @DisplayName("Should pass when user is caregiver")
        void shouldPassWhenUserIsCaregiver() {
            when(mockUser.isCaregiver()).thenReturn(true);

            assertDoesNotThrow(() -> authorizationService.requireCaregiver(mockUser));
        }
    }

    // ========== requireAdminOrCaregiver Tests ==========

    @Nested
    @DisplayName("requireAdminOrCaregiver")
    class RequireAdminOrCaregiverTests {

        @Test
        @DisplayName("Should throw when user is null")
        void shouldThrowWhenUserIsNull() {
            UnauthorizedException ex = assertThrows(UnauthorizedException.class,
                    () -> authorizationService.requireAdminOrCaregiver(null));
            assertEquals("User is not authenticated", ex.getMessage());
        }

        @Test
        @DisplayName("Should throw when user is neither admin nor caregiver")
        void shouldThrowWhenUserIsNeither() {
            when(mockUser.isAdmin()).thenReturn(false);
            when(mockUser.isCaregiver()).thenReturn(false);

            UnauthorizedException ex = assertThrows(UnauthorizedException.class,
                    () -> authorizationService.requireAdminOrCaregiver(mockUser));
            assertTrue(ex.getMessage().contains("Admin or Caregiver access required"));
        }

        @Test
        @DisplayName("Should pass when user is admin")
        void shouldPassWhenUserIsAdmin() {
            when(mockUser.isAdmin()).thenReturn(true);

            assertDoesNotThrow(() -> authorizationService.requireAdminOrCaregiver(mockUser));
        }

        @Test
        @DisplayName("Should pass when user is caregiver")
        void shouldPassWhenUserIsCaregiver() {
            when(mockUser.isAdmin()).thenReturn(false);
            when(mockUser.isCaregiver()).thenReturn(true);

            assertDoesNotThrow(() -> authorizationService.requireAdminOrCaregiver(mockUser));
        }
    }

    // ========== requirePatientAccess / requirePatientRecordAccess Tests ==========

    // patient.id and users.id are separate sequences; these values mirror a real
    // patient whose two IDs differ (entity 6, user 9).
    private static final long PATIENT_ID = 6L;
    private static final long PATIENT_USER_ID = 9L;

    private static Patient patient(long patientId, Long userId) {
        return Patient.builder()
                .id(patientId)
                .user(userId == null ? null : User.builder().id(userId).build())
                .build();
    }

    private void actAs(Role role, long userId) {
        lenient().when(mockUser.isAdmin()).thenReturn(role == Role.ADMIN);
        lenient().when(mockUser.isPatient()).thenReturn(role == Role.PATIENT);
        lenient().when(mockUser.isCaregiver()).thenReturn(role == Role.CAREGIVER);
        lenient().when(mockUser.isFamilyMember()).thenReturn(role == Role.FAMILY_MEMBER);
        lenient().when(mockUser.getId()).thenReturn(userId);
    }

    @Nested
    @DisplayName("requirePatientRecordAccess (patient entity ID)")
    class RequirePatientRecordAccessTests {

        @BeforeEach
        void knownPatient() {
            lenient().when(patientRepository.findById(PATIENT_ID))
                    .thenReturn(Optional.of(patient(PATIENT_ID, PATIENT_USER_ID)));
        }

        @Test
        void whenUserIsNull_throwsUnauthorized() {
            UnauthorizedException ex = assertThrows(UnauthorizedException.class,
                    () -> authorizationService.requirePatientRecordAccess(null, PATIENT_ID));
            assertEquals("User is not authenticated", ex.getMessage());
        }

        @Test
        void whenPatientIdIsNull_throwsIllegalArgument() {
            assertThrows(IllegalArgumentException.class,
                    () -> authorizationService.requirePatientRecordAccess(mockUser, null));
        }

        @Test
        void whenUserIsAdmin_allowsAnyPatientWithoutLookup() {
            actAs(Role.ADMIN, 1L);

            assertDoesNotThrow(() -> authorizationService.requirePatientRecordAccess(mockUser, 99L));
            verifyNoInteractions(patientRepository);
        }

        @Test
        void whenPatientAccessesOwnRecordWithDifferentUserId_allowsAccess() {
            actAs(Role.PATIENT, PATIENT_USER_ID);

            assertDoesNotThrow(() -> authorizationService.requirePatientRecordAccess(mockUser, PATIENT_ID));
        }

        @Test
        void whenPatientPassesOwnUserIdThatIsAnotherPatientsEntityId_throwsUnauthorized() {
            // Arrange: entity 9 is a different patient whose user ID is 30
            actAs(Role.PATIENT, PATIENT_USER_ID);
            when(patientRepository.findById(PATIENT_USER_ID))
                    .thenReturn(Optional.of(patient(PATIENT_USER_ID, 30L)));

            // Act / Assert
            UnauthorizedException ex = assertThrows(UnauthorizedException.class,
                    () -> authorizationService.requirePatientRecordAccess(mockUser, PATIENT_USER_ID));
            assertTrue(ex.getMessage().contains("Patients can only access their own data"));
        }

        @Test
        void whenPatientDoesNotExist_throwsUnauthorized() {
            actAs(Role.CAREGIVER, 10L);
            when(patientRepository.findById(404L)).thenReturn(Optional.empty());

            UnauthorizedException ex = assertThrows(UnauthorizedException.class,
                    () -> authorizationService.requirePatientRecordAccess(mockUser, 404L));
            assertTrue(ex.getMessage().contains("is not authorized to access patient 404"));
            verifyNoInteractions(caregiverPatientLinkRepository);
        }

        @Test
        void whenPatientRecordHasNoUser_throwsUnauthorized() {
            actAs(Role.PATIENT, PATIENT_USER_ID);
            when(patientRepository.findById(7L)).thenReturn(Optional.of(patient(7L, null)));

            assertThrows(UnauthorizedException.class,
                    () -> authorizationService.requirePatientRecordAccess(mockUser, 7L));
        }

        @Test
        void whenCaregiverLacksViewPermission_throwsUnauthorized() {
            actAs(Role.CAREGIVER, 10L);
            when(mockUser.hasPermission(Permission.VIEW_ASSIGNED_PATIENTS)).thenReturn(false);

            UnauthorizedException ex = assertThrows(UnauthorizedException.class,
                    () -> authorizationService.requirePatientRecordAccess(mockUser, PATIENT_ID));
            assertTrue(ex.getMessage().contains("does not have permission to view patient data"));
        }

        @Test
        void whenCaregiverIsLinked_checksLinkByPatientUserId() {
            actAs(Role.CAREGIVER, 10L);
            when(mockUser.hasPermission(Permission.VIEW_ASSIGNED_PATIENTS)).thenReturn(true);
            when(caregiverPatientLinkRepository.existsActiveNonExpiredLinkByUserIds(
                    eq(10L), eq(PATIENT_USER_ID), any(LocalDateTime.class))).thenReturn(true);

            assertDoesNotThrow(() -> authorizationService.requirePatientRecordAccess(mockUser, PATIENT_ID));
        }

        @Test
        void whenCaregiverHasNoActiveLink_throwsUnauthorized() {
            // Repository filters expired links; false covers expired and missing assignments.
            actAs(Role.CAREGIVER, 10L);
            when(mockUser.hasPermission(Permission.VIEW_ASSIGNED_PATIENTS)).thenReturn(true);
            when(caregiverPatientLinkRepository.existsActiveNonExpiredLinkByUserIds(
                    eq(10L), eq(PATIENT_USER_ID), any(LocalDateTime.class))).thenReturn(false);

            UnauthorizedException ex = assertThrows(UnauthorizedException.class,
                    () -> authorizationService.requirePatientRecordAccess(mockUser, PATIENT_ID));
            assertTrue(ex.getMessage().contains("not assigned to patient 6"));
        }

        @Test
        void whenFamilyMemberLacksViewPermission_throwsUnauthorized() {
            actAs(Role.FAMILY_MEMBER, 20L);
            when(mockUser.hasPermission(Permission.VIEW_HEALTH_DATA)).thenReturn(false);

            UnauthorizedException ex = assertThrows(UnauthorizedException.class,
                    () -> authorizationService.requirePatientRecordAccess(mockUser, PATIENT_ID));
            assertTrue(ex.getMessage().contains("does not have permission to view patient data"));
        }

        @Test
        void whenFamilyMemberIsLinked_checksLinkByPatientUserId() {
            actAs(Role.FAMILY_MEMBER, 20L);
            when(mockUser.hasPermission(Permission.VIEW_HEALTH_DATA)).thenReturn(true);
            when(familyMemberLinkRepository.existsActiveNonExpiredLinkByUserIds(
                    eq(20L), eq(PATIENT_USER_ID), any(LocalDateTime.class))).thenReturn(true);

            assertDoesNotThrow(() -> authorizationService.requirePatientRecordAccess(mockUser, PATIENT_ID));
        }

        @Test
        void whenFamilyMemberHasNoActiveLink_throwsUnauthorized() {
            actAs(Role.FAMILY_MEMBER, 20L);
            when(mockUser.hasPermission(Permission.VIEW_HEALTH_DATA)).thenReturn(true);
            when(familyMemberLinkRepository.existsActiveNonExpiredLinkByUserIds(
                    eq(20L), eq(PATIENT_USER_ID), any(LocalDateTime.class))).thenReturn(false);

            UnauthorizedException ex = assertThrows(UnauthorizedException.class,
                    () -> authorizationService.requirePatientRecordAccess(mockUser, PATIENT_ID));
            assertTrue(ex.getMessage().contains("not linked to patient"));
        }

        @Test
        void whenRoleIsUnrecognized_throwsUnauthorized() {
            actAs(Role.PATIENT, 1L);
            when(mockUser.isPatient()).thenReturn(false);

            UnauthorizedException ex = assertThrows(UnauthorizedException.class,
                    () -> authorizationService.requirePatientRecordAccess(mockUser, PATIENT_ID));
            assertTrue(ex.getMessage().contains("is not authorized to access patient"));
        }
    }

    @Nested
    @DisplayName("requireTaskAccess")
    class RequireTaskAccessTests {

        private Task taskOf(Patient patient) {
            return Task.builder().id(70L).name("Check Vitals").patient(patient).build();
        }

        @Test
        void patientMayAccessOwnTask() {
            actAs(Role.PATIENT, PATIENT_USER_ID);
            when(patientRepository.findById(PATIENT_ID))
                    .thenReturn(Optional.of(patient(PATIENT_ID, PATIENT_USER_ID)));

            assertDoesNotThrow(() -> authorizationService.requireTaskAccess(
                    mockUser, taskOf(patient(PATIENT_ID, PATIENT_USER_ID))));
        }

        @Test
        void patientCannotAccessAnotherPatientsTask() {
            actAs(Role.PATIENT, PATIENT_USER_ID);
            when(patientRepository.findById(2L)).thenReturn(Optional.of(patient(2L, 30L)));

            assertThrows(UnauthorizedException.class, () -> authorizationService.requireTaskAccess(
                    mockUser, taskOf(patient(2L, 30L))));
        }

        @Test
        void unlinkedCaregiverCannotAccessTask() {
            actAs(Role.CAREGIVER, 10L);
            when(mockUser.hasPermission(Permission.VIEW_ASSIGNED_PATIENTS)).thenReturn(true);
            when(patientRepository.findById(PATIENT_ID))
                    .thenReturn(Optional.of(patient(PATIENT_ID, PATIENT_USER_ID)));

            assertThrows(UnauthorizedException.class, () -> authorizationService.requireTaskAccess(
                    mockUser, taskOf(patient(PATIENT_ID, PATIENT_USER_ID))));
        }

        @Test
        void taskWithoutPatientIsAdminOnly() {
            actAs(Role.CAREGIVER, 10L);

            assertThrows(UnauthorizedException.class,
                    () -> authorizationService.requireTaskAccess(mockUser, taskOf(null)));
        }
    }

    @Nested
    @DisplayName("requirePatientAccess (patient user ID)")
    class RequirePatientAccessTests {

        @Test
        void whenUserIsNull_throwsUnauthorized() {
            UnauthorizedException ex = assertThrows(UnauthorizedException.class,
                    () -> authorizationService.requirePatientAccess(null, PATIENT_USER_ID));
            assertEquals("User is not authenticated", ex.getMessage());
        }

        @Test
        void whenPatientUserIdIsNull_throwsIllegalArgument() {
            assertThrows(IllegalArgumentException.class,
                    () -> authorizationService.requirePatientAccess(mockUser, null));
        }

        @Test
        void whenUserIsAdmin_allowsWithoutLookup() {
            actAs(Role.ADMIN, 1L);

            assertDoesNotThrow(() -> authorizationService.requirePatientAccess(mockUser, 99L));
            verifyNoInteractions(patientRepository);
        }

        @Test
        void whenPatientAccessesOwnUserId_allowsAccess() {
            actAs(Role.PATIENT, PATIENT_USER_ID);

            assertDoesNotThrow(() -> authorizationService.requirePatientAccess(mockUser, PATIENT_USER_ID));
        }

        @Test
        void whenPatientPassesOwnEntityId_throwsUnauthorized() {
            actAs(Role.PATIENT, PATIENT_USER_ID);

            assertThrows(UnauthorizedException.class,
                    () -> authorizationService.requirePatientAccess(mockUser, PATIENT_ID));
        }

        @Test
        void whenCaregiverIsLinked_checksLinkByPatientUserId() {
            actAs(Role.CAREGIVER, 10L);
            when(mockUser.hasPermission(Permission.VIEW_ASSIGNED_PATIENTS)).thenReturn(true);
            when(caregiverPatientLinkRepository.existsActiveNonExpiredLinkByUserIds(
                    eq(10L), eq(PATIENT_USER_ID), any(LocalDateTime.class))).thenReturn(true);

            assertDoesNotThrow(() -> authorizationService.requirePatientAccess(mockUser, PATIENT_USER_ID));
        }

        @Test
        void whenFamilyMemberIsLinked_matchesByUserIdWithoutPatientLookup() {
            // Arrange: seeded links carry only patientUser, so the check must not need a patient row
            actAs(Role.FAMILY_MEMBER, 20L);
            when(mockUser.hasPermission(Permission.VIEW_HEALTH_DATA)).thenReturn(true);
            when(familyMemberLinkRepository.existsActiveNonExpiredLinkByUserIds(
                    eq(20L), eq(55L), any(LocalDateTime.class))).thenReturn(true);

            // Act / Assert
            assertDoesNotThrow(() -> authorizationService.requirePatientAccess(mockUser, 55L));
            verifyNoInteractions(patientRepository);
        }

        @Test
        void whenFamilyMemberHasNoActiveLink_throwsUnauthorized() {
            actAs(Role.FAMILY_MEMBER, 20L);
            when(mockUser.hasPermission(Permission.VIEW_HEALTH_DATA)).thenReturn(true);
            when(familyMemberLinkRepository.existsActiveNonExpiredLinkByUserIds(
                    eq(20L), eq(PATIENT_USER_ID), any(LocalDateTime.class))).thenReturn(false);

            UnauthorizedException ex = assertThrows(UnauthorizedException.class,
                    () -> authorizationService.requirePatientAccess(mockUser, PATIENT_USER_ID));
            assertTrue(ex.getMessage().contains("not linked to patient 9"));
        }
    }

    @Nested
    @DisplayName("requireWriteAccess")
    class RequireWriteAccessTests {

        @Test
        void whenUserIsNull_throwsUnauthorized() {
            UnauthorizedException ex = assertThrows(UnauthorizedException.class,
                    () -> authorizationService.requireWriteAccess(null));
            assertEquals("User is not authenticated", ex.getMessage());
        }

        @Test
        void whenUserIsReadOnly_throwsUnauthorized() {
            // Arrange: family members are the read-only role
            when(mockUser.canModifyData()).thenReturn(false);
            when(mockUser.getEmail()).thenReturn("family@test.invalid");

            // Act / Assert
            UnauthorizedException ex = assertThrows(UnauthorizedException.class,
                    () -> authorizationService.requireWriteAccess(mockUser));
            assertEquals("User 'family@test.invalid' has read-only access", ex.getMessage());
        }

        @Test
        void whenUserCanModifyData_allows() {
            when(mockUser.canModifyData()).thenReturn(true);

            assertDoesNotThrow(() -> authorizationService.requireWriteAccess(mockUser));
        }
    }

    // ========== requireSelfOrAdmin Tests ==========

    @Nested
    @DisplayName("requireSelfOrAdmin")
    class RequireSelfOrAdminTests {

        @Test
        @DisplayName("Should throw when user is null")
        void shouldThrowWhenUserIsNull() {
            UnauthorizedException ex = assertThrows(UnauthorizedException.class,
                    () -> authorizationService.requireSelfOrAdmin(null, 1L));
            assertEquals("User is not authenticated", ex.getMessage());
        }

        @Test
        @DisplayName("Should throw when targetUserId is null")
        void shouldThrowWhenTargetUserIdIsNull() {
            assertThrows(IllegalArgumentException.class,
                    () -> authorizationService.requireSelfOrAdmin(mockUser, null));
        }

        @Test
        @DisplayName("Should allow user to access own data")
        void shouldAllowSelfAccess() {
            when(mockUser.getId()).thenReturn(1L);

            assertDoesNotThrow(
                    () -> authorizationService.requireSelfOrAdmin(mockUser, 1L));
        }

        @Test
        @DisplayName("Should allow admin to access any user data")
        void shouldAllowAdminAccess() {
            when(mockUser.getId()).thenReturn(1L);
            when(mockUser.isAdmin()).thenReturn(true);

            assertDoesNotThrow(
                    () -> authorizationService.requireSelfOrAdmin(mockUser, 99L));
        }

        @Test
        @DisplayName("Should deny non-admin accessing other user data")
        void shouldDenyNonAdminAccessingOther() {
            when(mockUser.getId()).thenReturn(1L);
            when(mockUser.isAdmin()).thenReturn(false);

            UnauthorizedException ex = assertThrows(UnauthorizedException.class,
                    () -> authorizationService.requireSelfOrAdmin(mockUser, 99L));
            assertTrue(ex.getMessage().contains("You can only access your own data"));
        }
    }

    // ========== Utility Method Tests ==========

    @Nested
    @DisplayName("hasPermission")
    class HasPermissionTests {

        @Test
        @DisplayName("Should return false when user is null")
        void shouldReturnFalseWhenUserIsNull() {
            assertFalse(authorizationService.hasPermission(null, Permission.CREATE_TASKS));
        }

        @Test
        @DisplayName("Should return true when user has permission")
        void shouldReturnTrueWhenUserHasPermission() {
            when(mockUser.hasPermission(Permission.CREATE_TASKS)).thenReturn(true);
            assertTrue(authorizationService.hasPermission(mockUser, Permission.CREATE_TASKS));
        }

        @Test
        @DisplayName("Should return false when user lacks permission")
        void shouldReturnFalseWhenUserLacksPermission() {
            when(mockUser.hasPermission(Permission.CREATE_TASKS)).thenReturn(false);
            assertFalse(authorizationService.hasPermission(mockUser, Permission.CREATE_TASKS));
        }
    }

    @Nested
    @DisplayName("isAuthenticated")
    class IsAuthenticatedTests {

        @Test
        @DisplayName("Should return false when user is null")
        void shouldReturnFalseWhenUserIsNull() {
            assertFalse(authorizationService.isAuthenticated(null));
        }

        @Test
        @DisplayName("Should return true when user is not null")
        void shouldReturnTrueWhenUserIsNotNull() {
            assertTrue(authorizationService.isAuthenticated(mockUser));
        }
    }

    @Nested
    @DisplayName("canModifyData")
    class CanModifyDataTests {

        @Test
        @DisplayName("Should return false when user is null")
        void shouldReturnFalseWhenUserIsNull() {
            assertFalse(authorizationService.canModifyData(null));
        }

        @Test
        @DisplayName("Should return true when user can modify data")
        void shouldReturnTrueWhenUserCanModify() {
            when(mockUser.canModifyData()).thenReturn(true);
            assertTrue(authorizationService.canModifyData(mockUser));
        }

        @Test
        @DisplayName("Should return false when user cannot modify data")
        void shouldReturnFalseWhenUserCannotModify() {
            when(mockUser.canModifyData()).thenReturn(false);
            assertFalse(authorizationService.canModifyData(mockUser));
        }
    }

    @Nested
    @DisplayName("getPermissionDeniedMessage")
    class GetPermissionDeniedMessageTests {

        @Test
        @DisplayName("Should return formatted message with permission details")
        void shouldReturnFormattedMessage() {
            String message = authorizationService.getPermissionDeniedMessage(Permission.CREATE_TASKS);
            assertTrue(message.contains("CREATE_TASKS"));
            assertTrue(message.contains("Create tasks for patients"));
            assertTrue(message.contains("Access denied"));
        }
    }

    // ========== checkPermission Tests ==========

    @Nested
    @DisplayName("checkPermission")
    class CheckPermissionTests {

        @Test
        @DisplayName("Should return deny when user is null")
        void shouldReturnDenyWhenUserIsNull() {
            AuthorizationService.AuthorizationResult result =
                    authorizationService.checkPermission(null, Permission.CREATE_TASKS);
            assertFalse(result.isAuthorized());
            assertEquals("User is not authenticated", result.getReason());
        }

        @Test
        @DisplayName("Should return deny when user lacks permission")
        void shouldReturnDenyWhenUserLacksPermission() {
            when(mockUser.hasPermission(Permission.CREATE_TASKS)).thenReturn(false);

            AuthorizationService.AuthorizationResult result =
                    authorizationService.checkPermission(mockUser, Permission.CREATE_TASKS);
            assertFalse(result.isAuthorized());
            assertTrue(result.getReason().contains("CREATE_TASKS"));
        }

        @Test
        @DisplayName("Should return allow when user has permission")
        void shouldReturnAllowWhenUserHasPermission() {
            when(mockUser.hasPermission(Permission.CREATE_TASKS)).thenReturn(true);

            AuthorizationService.AuthorizationResult result =
                    authorizationService.checkPermission(mockUser, Permission.CREATE_TASKS);
            assertTrue(result.isAuthorized());
            assertEquals("Authorized", result.getReason());
        }
    }

    // ========== AuthorizationResult Tests ==========

    @Nested
    @DisplayName("AuthorizationResult")
    class AuthorizationResultTests {

        @Test
        @DisplayName("allow() should create authorized result")
        void allowShouldCreateAuthorizedResult() {
            AuthorizationService.AuthorizationResult result = AuthorizationService.AuthorizationResult.allow();
            assertTrue(result.isAuthorized());
            assertEquals("Authorized", result.getReason());
        }

        @Test
        @DisplayName("deny() should create unauthorized result with reason")
        void denyShouldCreateUnauthorizedResult() {
            AuthorizationService.AuthorizationResult result =
                    AuthorizationService.AuthorizationResult.deny("Not allowed");
            assertFalse(result.isAuthorized());
            assertEquals("Not allowed", result.getReason());
        }

        @Test
        @DisplayName("Constructor should set fields correctly")
        void constructorShouldSetFields() {
            AuthorizationService.AuthorizationResult result =
                    new AuthorizationService.AuthorizationResult(true, "Custom reason");
            assertTrue(result.isAuthorized());
            assertEquals("Custom reason", result.getReason());
        }
    }
}
