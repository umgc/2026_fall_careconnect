package com.careconnect.security;

import com.careconnect.model.User;
import com.careconnect.repository.CaregiverPatientLinkRepository;
import com.careconnect.repository.FamilyMemberLinkRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.junit.jupiter.MockitoExtension;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
public class AuthorizationServiceTest {

    private AuthorizationService authorizationService;
    private User mockUser;
    private CaregiverPatientLinkRepository caregiverPatientLinkRepository;
    private FamilyMemberLinkRepository familyMemberLinkRepository;

    @BeforeEach
    void setUp() {
        caregiverPatientLinkRepository = mock(CaregiverPatientLinkRepository.class);
        familyMemberLinkRepository = mock(FamilyMemberLinkRepository.class);
        authorizationService = new AuthorizationService(caregiverPatientLinkRepository, familyMemberLinkRepository);
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

    // ========== requirePatientAccess Tests ==========

    @Nested
    @DisplayName("requirePatientAccess")
    class RequirePatientAccessTests {

        @Test
        @DisplayName("requirePatientAccess_whenUserIsNull_throwsUnauthorized")
        void requirePatientAccess_whenUserIsNull_throwsUnauthorized() {
            UnauthorizedException ex = assertThrows(UnauthorizedException.class,
                () -> authorizationService.requirePatientAccess(null, 1L));
            assertEquals("User is not authenticated", ex.getMessage());
        }

        @Test
        @DisplayName("requirePatientAccess_whenPatientIdIsNull_throwsIllegalArgument")
        void requirePatientAccess_whenPatientIdIsNull_throwsIllegalArgument() {
            assertThrows(IllegalArgumentException.class,
                () -> authorizationService.requirePatientAccess(mockUser, null));
        }

        @Test
        @DisplayName("requirePatientAccess_whenUserIsAdmin_allowsAccessToAnyPatient")
        void requirePatientAccess_whenUserIsAdmin_allowsAccessToAnyPatient() {
            when(mockUser.isAdmin()).thenReturn(true);

            assertDoesNotThrow(
                () -> authorizationService.requirePatientAccess(mockUser, 99L));
        }

        @Test
        @DisplayName("requirePatientAccess_whenPatientAccessesOwnData_allowsAccess")
        void requirePatientAccess_whenPatientAccessesOwnData_allowsAccess() {
            when(mockUser.isAdmin()).thenReturn(false);
            when(mockUser.isPatient()).thenReturn(true);
            when(mockUser.getId()).thenReturn(1L);

            assertDoesNotThrow(
                () -> authorizationService.requirePatientAccess(mockUser, 1L));
        }

        @Test
        @DisplayName("requirePatientAccess_whenPatientAccessesOtherPatientData_throwsUnauthorized")
        void requirePatientAccess_whenPatientAccessesOtherPatientData_throwsUnauthorized() {
            when(mockUser.isAdmin()).thenReturn(false);
            when(mockUser.isPatient()).thenReturn(true);
            when(mockUser.getId()).thenReturn(1L);

            UnauthorizedException ex = assertThrows(UnauthorizedException.class,
                () -> authorizationService.requirePatientAccess(mockUser, 2L));
            assertTrue(ex.getMessage().contains("Patients can only access their own data"));
        }

        @Test
        @DisplayName("requirePatientAccess_whenCaregiverLacksViewPermission_throwsUnauthorized")
        void requirePatientAccess_whenCaregiverLacksViewPermission_throwsUnauthorized() {
            when(mockUser.isAdmin()).thenReturn(false);
            when(mockUser.isPatient()).thenReturn(false);
            when(mockUser.isCaregiver()).thenReturn(true);
            when(mockUser.hasPermission(Permission.VIEW_ASSIGNED_PATIENTS)).thenReturn(false);

            UnauthorizedException ex = assertThrows(UnauthorizedException.class,
                () -> authorizationService.requirePatientAccess(mockUser, 5L));
            assertTrue(ex.getMessage().contains("does not have permission to view patient data"));
        }

        @Test
        @DisplayName("requirePatientAccess_whenCaregiverHasPermissionAndActiveLink_allowsAccess")
        void requirePatientAccess_whenCaregiverHasPermissionAndActiveLink_allowsAccess() {
            when(mockUser.isAdmin()).thenReturn(false);
            when(mockUser.isPatient()).thenReturn(false);
            when(mockUser.isCaregiver()).thenReturn(true);
            when(mockUser.hasPermission(Permission.VIEW_ASSIGNED_PATIENTS)).thenReturn(true);
            when(mockUser.getId()).thenReturn(10L);
            when(caregiverPatientLinkRepository.existsActiveNonExpiredLinkByUserIds(eq(10L), eq(5L), any()))
                .thenReturn(true);

            assertDoesNotThrow(
                () -> authorizationService.requirePatientAccess(mockUser, 5L));
        }

        @Test
        @DisplayName("requirePatientAccess_whenCaregiverHasPermissionButNoActiveLink_throwsUnauthorized")
        void requirePatientAccess_whenCaregiverHasPermissionButNoActiveLink_throwsUnauthorized() {
            when(mockUser.isAdmin()).thenReturn(false);
            when(mockUser.isPatient()).thenReturn(false);
            when(mockUser.isCaregiver()).thenReturn(true);
            when(mockUser.hasPermission(Permission.VIEW_ASSIGNED_PATIENTS)).thenReturn(true);
            when(mockUser.getId()).thenReturn(10L);
            when(caregiverPatientLinkRepository.existsActiveNonExpiredLinkByUserIds(eq(10L), eq(5L), any()))
                .thenReturn(false);

            UnauthorizedException ex = assertThrows(UnauthorizedException.class,
                () -> authorizationService.requirePatientAccess(mockUser, 5L));
            assertTrue(ex.getMessage().contains("not assigned to patient"));
        }

        @Test
        @DisplayName("requirePatientAccess_whenFamilyMemberLacksViewPermission_throwsUnauthorized")
        void requirePatientAccess_whenFamilyMemberLacksViewPermission_throwsUnauthorized() {
            when(mockUser.isAdmin()).thenReturn(false);
            when(mockUser.isPatient()).thenReturn(false);
            when(mockUser.isCaregiver()).thenReturn(false);
            when(mockUser.isFamilyMember()).thenReturn(true);
            when(mockUser.hasPermission(Permission.VIEW_HEALTH_DATA)).thenReturn(false);

            UnauthorizedException ex = assertThrows(UnauthorizedException.class,
                () -> authorizationService.requirePatientAccess(mockUser, 5L));
            assertTrue(ex.getMessage().contains("does not have permission to view patient data"));
        }

        @Test
        @DisplayName("requirePatientAccess_whenFamilyMemberHasPermissionAndActiveLink_allowsAccess")
        void requirePatientAccess_whenFamilyMemberHasPermissionAndActiveLink_allowsAccess() {
            when(mockUser.isAdmin()).thenReturn(false);
            when(mockUser.isPatient()).thenReturn(false);
            when(mockUser.isCaregiver()).thenReturn(false);
            when(mockUser.isFamilyMember()).thenReturn(true);
            when(mockUser.hasPermission(Permission.VIEW_HEALTH_DATA)).thenReturn(true);
            when(mockUser.getId()).thenReturn(20L);
            when(familyMemberLinkRepository.existsByFamilyMemberUserIdAndPatientId(eq(20L), eq(5L), any()))
                .thenReturn(true);

            assertDoesNotThrow(
                () -> authorizationService.requirePatientAccess(mockUser, 5L));
        }

        @Test
        @DisplayName("requirePatientAccess_whenFamilyMemberHasPermissionButNoActiveLink_throwsUnauthorized")
        void requirePatientAccess_whenFamilyMemberHasPermissionButNoActiveLink_throwsUnauthorized() {
            when(mockUser.isAdmin()).thenReturn(false);
            when(mockUser.isPatient()).thenReturn(false);
            when(mockUser.isCaregiver()).thenReturn(false);
            when(mockUser.isFamilyMember()).thenReturn(true);
            when(mockUser.hasPermission(Permission.VIEW_HEALTH_DATA)).thenReturn(true);
            when(mockUser.getId()).thenReturn(20L);
            when(familyMemberLinkRepository.existsByFamilyMemberUserIdAndPatientId(eq(20L), eq(5L), any()))
                .thenReturn(false);

            UnauthorizedException ex = assertThrows(UnauthorizedException.class,
                () -> authorizationService.requirePatientAccess(mockUser, 5L));
            assertTrue(ex.getMessage().contains("not linked to patient"));
        }

        @Test
        @DisplayName("requirePatientAccess_whenRoleIsUnrecognized_throwsUnauthorized")
        void requirePatientAccess_whenRoleIsUnrecognized_throwsUnauthorized() {
            when(mockUser.isAdmin()).thenReturn(false);
            when(mockUser.isPatient()).thenReturn(false);
            when(mockUser.isCaregiver()).thenReturn(false);
            when(mockUser.isFamilyMember()).thenReturn(false);

            UnauthorizedException ex = assertThrows(UnauthorizedException.class,
                () -> authorizationService.requirePatientAccess(mockUser, 5L));
            assertTrue(ex.getMessage().contains("is not authorized to access patient"));
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
