package com.careconnect.security;

import com.careconnect.model.User;
import com.careconnect.service.CaregiverPatientLinkService;
import org.springframework.stereotype.Service;
import lombok.RequiredArgsConstructor;

/**
 * Service for enforcing Role-Based Access Control (RBAC) throughout the application.
 * 
 * This service provides methods to check and enforce permissions at API endpoints.
 * It acts as the enforcement layer that ensures users can only perform authorized actions.
 * 
 * Usage in Controllers:
 * <pre>
 * {@code
 * @Autowired
 * private AuthorizationService authorizationService;
 * 
 * @PostMapping("/tasks")
 * public ResponseEntity<?> createTask(@RequestBody Task task, @AuthenticationPrincipal User user) {
 *     try {
 *         authorizationService.requirePermission(user, Permission.CREATE_TASKS);
 *         // Permission granted, execute business logic
 *         return ResponseEntity.ok(taskService.create(task));
 *     } catch (UnauthorizedException e) {
 *         return ResponseEntity.status(403).body(e.getMessage());
 *     }
 * }
 * }
 * </pre>
 * 
 * @author CareConnect Team
 * @version 1.0
 */
@Service
@RequiredArgsConstructor // this will inject any required dependencies (e.g., services for checking relationships)
public class AuthorizationService {

    private final CaregiverPatientLinkService caregiverPatientLinkService;

    // ========== Permission Enforcement Methods ==========

    /**
     * Require user to have a specific permission.
     * Throws UnauthorizedException if user doesn't have the permission.
     * 
     * @param user The authenticated user
     * @param permission The required permission
     * @throws UnauthorizedException if user lacks the permission
     * 
     * @example
     * authorizationService.requirePermission(user, Permission.CREATE_TASKS);
     */
    public void requirePermission(User user, Permission permission) throws UnauthorizedException {
        if (user == null) {
            throw new UnauthorizedException("User is not authenticated");
        }

        if (!user.hasPermission(permission)) {
            throw new UnauthorizedException(
                String.format("User '%s' does not have permission '%s'. This action requires %s permission.",
                    user.getEmail(),
                    permission.name(),
                    permission.getDescription().toLowerCase())
            );
        }
    }

    /**
     * Require user to have ALL of the specified permissions.
     * Throws UnauthorizedException if user is missing any permission.
     * 
     * @param user The authenticated user
     * @param permissions One or more required permissions
     * @throws UnauthorizedException if user lacks any permission
     * 
     * @example
     * authorizationService.requireAllPermissions(user, 
     *     Permission.CREATE_TASKS, 
     *     Permission.VIEW_ASSIGNED_PATIENTS);
     */
    public void requireAllPermissions(User user, Permission... permissions) throws UnauthorizedException {
        if (user == null) {
            throw new UnauthorizedException("User is not authenticated");
        }

        for (Permission permission : permissions) {
            if (!user.hasPermission(permission)) {
                throw new UnauthorizedException(
                    String.format("User '%s' is missing required permission: %s",
                        user.getEmail(),
                        permission.name())
                );
            }
        }
    }

    /**
     * Require user to have ANY of the specified permissions.
     * Throws UnauthorizedException if user has none of the permissions.
     * 
     * @param user The authenticated user
     * @param permissions One or more acceptable permissions
     * @throws UnauthorizedException if user has none of the permissions
     * 
     * @example
     * // Allow if user can either create or update tasks
     * authorizationService.requireAnyPermission(user, 
     *     Permission.CREATE_TASKS, 
     *     Permission.UPDATE_TASKS);
     */
    public void requireAnyPermission(User user, Permission... permissions) throws UnauthorizedException {
        if (user == null) {
            throw new UnauthorizedException("User is not authenticated");
        }

        if (!user.hasAnyPermission(permissions)) {
            StringBuilder permissionList = new StringBuilder();
            for (int i = 0; i < permissions.length; i++) {
                permissionList.append(permissions[i].name());
                if (i < permissions.length - 1) {
                    permissionList.append(", ");
                }
            }
            throw new UnauthorizedException(
                String.format("User '%s' does not have any of the required permissions: %s",
                    user.getEmail(),
                    permissionList.toString())
            );
        }
    }

    // ========== Role-Based Enforcement Methods ==========

    /**
     * Require user to have Admin role.
     * Throws UnauthorizedException if user is not an admin.
     * 
     * @param user The authenticated user
     * @throws UnauthorizedException if user is not admin
     * 
     * @example
     * authorizationService.requireAdmin(user);
     */
    public void requireAdmin(User user) throws UnauthorizedException {
        if (user == null) {
            throw new UnauthorizedException("User is not authenticated");
        }

        if (!user.isAdmin()) {
            throw new UnauthorizedException(
                String.format("Admin access required. User '%s' has role '%s'",
                    user.getEmail(),
                    user.getRole().getDisplayName())
            );
        }
    }

    /**
     * Require user to have Caregiver role.
     * Throws UnauthorizedException if user is not a caregiver.
     * 
     * @param user The authenticated user
     * @throws UnauthorizedException if user is not caregiver
     * 
     * @example
     * authorizationService.requireCaregiver(user);
     */
    public void requireCaregiver(User user) throws UnauthorizedException {
        if (user == null) {
            throw new UnauthorizedException("User is not authenticated");
        }

        if (!user.isCaregiver()) {
            throw new UnauthorizedException(
                String.format("Caregiver access required. User '%s' has role '%s'",
                    user.getEmail(),
                    user.getRole().getDisplayName())
            );
        }
    }

    /**
     * Require user to be either Admin or Caregiver.
     * Throws UnauthorizedException otherwise.
     * 
     * @param user The authenticated user
     * @throws UnauthorizedException if user is neither admin nor caregiver
     * 
     * @example
     * authorizationService.requireAdminOrCaregiver(user);
     */
    public void requireAdminOrCaregiver(User user) throws UnauthorizedException {
        if (user == null) {
            throw new UnauthorizedException("User is not authenticated");
        }

        if (!user.isAdmin() && !user.isCaregiver()) {
            throw new UnauthorizedException(
                String.format("Admin or Caregiver access required. User '%s' has role '%s'",
                    user.getEmail(),
                    user.getRole().getDisplayName())
            );
        }
    }

    // ========== Patient Access Control Methods ==========

    /**
     * Check if user can access a specific patient's data.
     * 
     * Rules:
     * - Admins can access all patients
     * - Caregivers can access assigned patients only
     * - Patients can access only themselves
     * - Family members can access linked patients only
     * 
     * Note: This method checks basic access rules. Assignment/linking must be 
     * verified separately via database queries.
     * 
     * @param user The authenticated user
     * @param patientId The ID of the patient being accessed
     * @throws UnauthorizedException if user cannot access this patient
     * 
     * @example
     * authorizationService.requirePatientAccess(user, patientId);
     */
    public void requirePatientAccess(User user, Long patientId) throws UnauthorizedException {
        if (user == null) {
            throw new UnauthorizedException("User is not authenticated");
        }

        if (patientId == null) {
            throw new IllegalArgumentException("Patient ID cannot be null");
        }

        // Admins can access all patients
        if (user.isAdmin()) {
            return;
        }

        // Patients can only access themselves
        if (user.isPatient()) {
            if (!user.getId().equals(patientId)) {
                throw new UnauthorizedException(
                    "Patients can only access their own data"
                );
            }
            return;
        }


       // For Caregivers, assignment/linking must be verified against the DB
        //This is the security fix that is required to ensure that caregivers can only access patients they are assigned to. 
        // The caregiverPatientLinkService is assumed to be a service that checks the database for valid caregiver-patient relationships.
        if (user.isCaregiver()) {
            if (!user.hasPermission(Permission.VIEW_ASSIGNED_PATIENTS)) {
                throw new UnauthorizedException(
                    "User does not have permission to view patient data"
                );
            }
            if (!caregiverPatientLinkService.hasAccessToPatient(user.getId(), patientId)) {
                throw new UnauthorizedException(
                    String.format("Caregiver '%s' is not linked to patient %d", user.getEmail(), patientId)
                );
            }
        } else if (user.isFamilyMember()) {
            if (!user.hasPermission(Permission.VIEW_HEALTH_DATA)) {
                throw new UnauthorizedException(
                    "User does not have permission to view patient data"
                );
            }
            // In production, verify: SELECT COUNT(*) FROM family_patient WHERE family_id = ? AND patient_id = ?
        } else {
            throw new UnauthorizedException(
                String.format("User '%s' is not authorized to access patient %d",
                    user.getEmail(),
                    patientId)
            );
        }
    }

    /**
     * Check if user can access their own data or is an admin.
     * Common pattern for endpoints that operate on user's own data.
     * 
     * @param user The authenticated user
     * @param targetUserId The user ID being accessed
     * @throws UnauthorizedException if user cannot access this user's data
     * 
     * @example
     * authorizationService.requireSelfOrAdmin(user, targetUserId);
     */
    public void requireSelfOrAdmin(User user, Long targetUserId) throws UnauthorizedException {
        if (user == null) {
            throw new UnauthorizedException("User is not authenticated");
        }

        if (targetUserId == null) {
            throw new IllegalArgumentException("Target user ID cannot be null");
        }

        // Allow if accessing own data or if admin
        if (!user.getId().equals(targetUserId) && !user.isAdmin()) {
            throw new UnauthorizedException(
                "You can only access your own data unless you are an administrator"
            );
        }
    }

    // ========== Utility Methods ==========

    /**
     * Check if user has a permission without throwing exception.
     * Returns true/false instead of throwing.
     * 
     * @param user The user to check
     * @param permission The permission to verify
     * @return true if user has permission, false otherwise
     * 
     * @example
     * if (authorizationService.hasPermission(user, Permission.CREATE_TASKS)) {
     *     // Show create button
     * }
     */
    public boolean hasPermission(User user, Permission permission) {
        return user != null && user.hasPermission(permission);
    }

    /**
     * Check if user is authenticated (not null).
     * 
     * @param user The user to check
     * @return true if user is authenticated
     */
    public boolean isAuthenticated(User user) {
        return user != null;
    }

    /**
     * Check if user can modify data (not read-only).
     * Family members have read-only access.
     * 
     * @param user The user to check
     * @return true if user can create/update/delete data
     */
    public boolean canModifyData(User user) {
        return user != null && user.canModifyData();
    }

    /**
     * Get a user-friendly error message for permission denial.
     * Useful for generating helpful error responses.
     * 
     * @param permission The permission that was denied
     * @return User-friendly error message
     */
    public String getPermissionDeniedMessage(Permission permission) {
        return String.format(
            "Access denied. This action requires '%s' permission. " +
            "Description: %s. Please contact your administrator if you believe you should have this access.",
            permission.name(),
            permission.getDescription()
        );
    }

    // ========== Authorization Check Results ==========

    /**
     * Simple result class for authorization checks.
     * Useful when you need to know why authorization failed without exceptions.
     */
    public static class AuthorizationResult {
        private final boolean authorized;
        private final String reason;

        public AuthorizationResult(boolean authorized, String reason) {
            this.authorized = authorized;
            this.reason = reason;
        }

        public boolean isAuthorized() {
            return authorized;
        }

        public String getReason() {
            return reason;
        }

        public static AuthorizationResult allow() {
            return new AuthorizationResult(true, "Authorized");
        }

        public static AuthorizationResult deny(String reason) {
            return new AuthorizationResult(false, reason);
        }
    }

    /**
     * Check authorization without throwing exception.
     * Returns a result object with authorization status and reason.
     * 
     * @param user The user to check
     * @param permission The required permission
     * @return AuthorizationResult indicating if authorized and why
     * 
     * @example
     * AuthorizationResult result = authorizationService.checkPermission(user, Permission.CREATE_TASKS);
     * if (!result.isAuthorized()) {
     *     return ResponseEntity.status(403).body(result.getReason());
     * }
     */
    public AuthorizationResult checkPermission(User user, Permission permission) {
        if (user == null) {
            return AuthorizationResult.deny("User is not authenticated");
        }

        if (!user.hasPermission(permission)) {
            return AuthorizationResult.deny(
                String.format("User lacks required permission: %s", permission.name())
            );
        }

        return AuthorizationResult.allow();
    }
}