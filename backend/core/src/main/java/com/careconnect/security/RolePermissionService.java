package com.careconnect.security;

import java.util.*;

/**
 * Service that maps roles to their permissions.
 * This is the CORE of the RBAC (Role-Based Access Control) system.
 *
 * Responsibilities:
 * - Define which permissions each role has
 * - Provide methods to check if a role has specific permissions
 * - Cache permission mappings for performance
 *
 * This class uses a static initialization block to set up the role-permission
 * mappings when the class is first loaded, ensuring fast lookups.
 *
 * Usage Examples:
 *   // Get all permissions for a role
 *   Set<Permission> caregiverPerms = RolePermissionService.getPermissionsForRole(Role.CAREGIVER);
 *
 *   // Check if role has a permission
 *   boolean canCreate = RolePermissionService.hasPermission(Role.CAREGIVER, Permission.CREATE_TASKS);
 *
 *   // Check multiple permissions
 *   boolean hasAll = RolePermissionService.hasAllPermissions(Role.ADMIN,
 *       Permission.CREATE_TASKS, Permission.DELETE_TASKS);
 *
 * @author CareConnect Team
 * @version 1.0
 */
public class RolePermissionService {

    // ========== Static Cache ==========

    /**
     * Immutable cache mapping each role to its set of permissions.
     * Initialized once when class loads, then never modified.
     * This provides O(1) lookup performance for permission checks.
     */
    private static final Map<Role, Set<Permission>> ROLE_PERMISSIONS;

    // ========== Static Initialization Block ==========

    /**
     * Static initializer that runs ONCE when the class is first loaded.
     * Sets up the permission mappings for all roles.
     */
    static {
        // Create mutable map for initial setup
        Map<Role, Set<Permission>> permissionMap = new HashMap<>();

        // Define permissions for each role
        permissionMap.put(Role.ADMIN, getAdminPermissions());
        permissionMap.put(Role.CAREGIVER, getCaregiverPermissions());
        permissionMap.put(Role.PATIENT, getPatientPermissions());
        permissionMap.put(Role.FAMILY_MEMBER, getFamilyMemberPermissions());

        // Wrap in unmodifiable map to prevent external modifications
        ROLE_PERMISSIONS = Collections.unmodifiableMap(permissionMap);
    }

    // ========== Public Methods ==========

    /**
     * Gets all permissions assigned to a specific role.
     *
     * @param role The user's role
     * @return Unmodifiable set of permissions (never null)
     *
     * @example
     * Set<Permission> permissions = RolePermissionService.getPermissionsForRole(Role.CAREGIVER);
     * // Returns set with 18 permissions
     */
    public static Set<Permission> getPermissionsForRole(Role role) {
        Set<Permission> permissions = ROLE_PERMISSIONS.get(role);

        // Return empty set if role not found (should never happen)
        if (permissions == null) {
            return Collections.emptySet();
        }

        // Return unmodifiable copy to prevent external modifications
        return Collections.unmodifiableSet(permissions);
    }

    /**
     * Checks if a role has a specific permission.
     *
     * @param role The user's role
     * @param permission The permission to check
     * @return true if role has the permission, false otherwise
     *
     * @example
     * boolean canCreate = RolePermissionService.hasPermission(
     *     Role.CAREGIVER,
     *     Permission.CREATE_TASKS
     * );
     * // Returns true
     */
    public static boolean hasPermission(Role role, Permission permission) {
        Set<Permission> rolePermissions = ROLE_PERMISSIONS.get(role);

        if (rolePermissions == null || permission == null) {
            return false;
        }

        return rolePermissions.contains(permission);
    }

    /**
     * Checks if a role has ALL of the specified permissions.
     * Returns true only if the role has every single permission listed.
     *
     * @param role The user's role
     * @param requiredPermissions One or more permissions to check
     * @return true if role has ALL permissions, false if missing any
     *
     * @example
     * boolean hasAll = RolePermissionService.hasAllPermissions(
     *     Role.CAREGIVER,
     *     Permission.CREATE_TASKS,
     *     Permission.VIEW_HEALTH_DATA,
     *     Permission.RECORD_HEALTH_DATA
     * );
     * // Returns true only if caregiver has all 3 permissions
     */
    public static boolean hasAllPermissions(Role role, Permission... requiredPermissions) {
        Set<Permission> rolePermissions = ROLE_PERMISSIONS.get(role);

        if (rolePermissions == null || requiredPermissions == null) {
            return false;
        }

        // Check each required permission
        for (Permission required : requiredPermissions) {
            if (!rolePermissions.contains(required)) {
                return false; // Missing at least one permission
            }
        }

        return true; // Has all required permissions
    }

    /**
     * Checks if a role has ANY of the specified permissions.
     * Returns true if the role has at least one of the permissions listed.
     *
     * @param role The user's role
     * @param requiredPermissions One or more permissions to check
     * @return true if role has at least ONE permission, false if has none
     *
     * @example
     * boolean hasAny = RolePermissionService.hasAnyPermission(
     *     Role.PATIENT,
     *     Permission.CREATE_TASKS,  // Patient doesn't have this
     *     Permission.VIEW_TASKS     // But patient HAS this
     * );
     * // Returns true because patient has VIEW_TASKS
     */
    public static boolean hasAnyPermission(Role role, Permission... requiredPermissions) {
        Set<Permission> rolePermissions = ROLE_PERMISSIONS.get(role);

        if (rolePermissions == null || requiredPermissions == null) {
            return false;
        }

        // Check if at least one permission exists
        for (Permission required : requiredPermissions) {
            if (rolePermissions.contains(required)) {
                return true; // Found at least one matching permission
            }
        }

        return false; // No matching permissions found
    }

    /**
     * Gets a count of how many permissions a role has.
     * Useful for displaying permission summaries.
     *
     * @param role The user's role
     * @return Number of permissions assigned to the role
     *
     * @example
     * int count = RolePermissionService.getPermissionCount(Role.CAREGIVER);
     * // Returns 18
     */
    public static int getPermissionCount(Role role) {
        Set<Permission> permissions = ROLE_PERMISSIONS.get(role);
        return permissions != null ? permissions.size() : 0;
    }

    // ========== Private Methods: Permission Definitions ==========

    /**
     * Defines all permissions for the ADMIN role.
     * Admins have FULL ACCESS - all 26 permissions.
     *
     * @return Set containing all possible permissions
     */
    private static Set<Permission> getAdminPermissions() {
        // Admins get EVERYTHING
        return new HashSet<>(Arrays.asList(Permission.values()));
    }

    /**
     * Defines all permissions for the CAREGIVER role.
     * Caregivers can manage assigned patients but not system settings.
     *
     * Total: 18 permissions (FINAL - correct count)
     *
     * Can do:
     * - Create, view, and update assigned patients
     * - Create and manage tasks
     * - View and record health data
     * - View billing (but not manage subscriptions)
     * - View and export analytics/reports
     * - Use AI features
     * - Manage devices
     *
     * Cannot do:
     * - Manage users or roles (admin only)
     * - View ALL patients (admin only)
     * - Delete patients (admin only)
     * - Manage subscriptions (admin/patient only)
     *
     * @return Set of caregiver permissions
     */
    private static Set<Permission> getCaregiverPermissions() {
        return new HashSet<>(Arrays.asList(
            // Patient Management
            Permission.VIEW_ASSIGNED_PATIENTS,
            Permission.CREATE_PATIENTS,
            Permission.UPDATE_PATIENTS,

            // Task Management
            Permission.CREATE_TASKS,
            Permission.VIEW_TASKS,
            Permission.UPDATE_TASKS,
            Permission.DELETE_TASKS,
            Permission.COMPLETE_TASKS,

            // Health Data
            Permission.VIEW_HEALTH_DATA,
            Permission.RECORD_HEALTH_DATA,
            Permission.EXPORT_HEALTH_DATA,

            // Medications
            Permission.VIEW_MEDICATIONS,
            Permission.MANAGE_MEDICATIONS,

            // Billing
            Permission.VIEW_BILLING,
            Permission.MANAGE_SUBSCRIPTIONS,

            // Communication
            Permission.SEND_MESSAGES,
            Permission.VIEW_MESSAGES,

            // Analytics
            Permission.VIEW_ANALYTICS,
            Permission.EXPORT_REPORTS,

            // AI and Devices
            Permission.USE_AI_FEATURES,
            Permission.MANAGE_DEVICES
        ));
    }

    /**
     * Defines all permissions for the PATIENT role.
     * Patients can view and interact with their OWN data only.
     *
     * Total: 7 permissions
     *
     * Can do:
     * - View and complete own tasks
     * - View and record own health data
     * - Communicate with caregivers
     * - Use Ask AI features on own records (USE_AI_FEATURES; scope enforced elsewhere)
     *
     * Cannot do:
     * - Create or delete tasks
     * - View other patients
     * - Access billing
     * - View analytics
     * - Manage devices (caregiver/admin only)
     *
     * @return Set of patient permissions
     */
    private static Set<Permission> getPatientPermissions() {
        return new HashSet<>(Arrays.asList(
            // Task Management (own tasks only)
            Permission.VIEW_TASKS,
            Permission.COMPLETE_TASKS,

            // Health Data (own data only)
            Permission.VIEW_HEALTH_DATA,
            Permission.RECORD_HEALTH_DATA,

            // Communication
            Permission.SEND_MESSAGES,
            Permission.VIEW_MESSAGES,

            // Ask AI (own patient scope enforced by RetrievalScopeService / gateway)
            Permission.USE_AI_FEATURES
        ));
    }

    /**
     * Defines all permissions for the FAMILY_MEMBER role.
     * Family members have READ-ONLY access to linked patient data.
     *
     * Total: 3 permissions
     *
     * Can do:
     * - View linked patient's tasks (read-only)
     * - View linked patient's health data (read-only)
     * - View messages
     *
     * Cannot do:
     * - Create, update, or delete anything
     * - Record health data
     * - Send messages (receive only)
     * - Access billing or analytics
     *
     * @return Set of family member permissions
     */
    private static Set<Permission> getFamilyMemberPermissions() {
        return new HashSet<>(Arrays.asList(
            // Read-only access
            Permission.VIEW_TASKS,
            Permission.VIEW_HEALTH_DATA,
            Permission.VIEW_MESSAGES

            // Note: Family members CANNOT create, update, or delete anything
        ));
    }

    // ========== Utility Methods ==========

    /**
     * Gets a summary of permissions for all roles.
     * Useful for debugging and documentation.
     *
     * @return Map of role names to permission counts
     */
    public static Map<String, Integer> getPermissionSummary() {
        Map<String, Integer> summary = new LinkedHashMap<>();

        for (Role role : Role.values()) {
            summary.put(role.getDisplayName(), getPermissionCount(role));
        }

        return summary;
    }

    /**
     * Prints a detailed report of all role-permission mappings.
     * Useful for verification during development.
     */
    public static void printPermissionReport() {
        System.out.println("=== CareConnect RBAC Permission Report ===\n");

        for (Role role : Role.values()) {
            Set<Permission> permissions = getPermissionsForRole(role);

            System.out.println(role.getDisplayName() + " (" + permissions.size() + " permissions):");
            System.out.println("  " + role.getDescription());
            System.out.println("  Permissions:");

            for (Permission p : permissions) {
                System.out.println("    - " + p.name());
            }
            System.out.println();
        }

        System.out.println("Total unique permissions: " + Permission.values().length);
    }
}
