package com.careconnect.security;

/**
 * Enumeration of all user roles in the CareConnect system.
 * <p>
 * Each user has exactly ONE role that determines their permissions and access level.
 * Roles are assigned during user registration or by administrators.
 * <p>
 * Role Hierarchy:
 * ADMIN > CAREGIVER > PATIENT > FAMILY_MEMBER
 * <p>
 * Usage:
 * - Assign role: user.setRole(Role.CAREGIVER)
 * - Check role: if (user.getRole() == Role.ADMIN)
 * - Get permissions: RolePermissionService.getPermissionsForRole(Role.CAREGIVER)
 *
 * @author CareConnect Team
 * @version 1.0
 */
public enum Role {

    /**
     * System administrator with full access to all features and data.
     * <p>
     * Capabilities:
     * - Manage all users and roles
     * - View and modify all patient data
     * - Configure system settings
     * - Access audit logs and analytics
     * - Override any permission restriction
     * <p>
     * Typical Users: IT administrators, system managers
     */
    ADMIN("Administrator", "Full system access with all permissions"),

    /**
     * Professional caregiver managing assigned patients.
     * <p>
     * Capabilities:
     * - Create and manage care plans for assigned patients
     * - Record health data and vital signs
     * - Create and assign tasks
     * - Communicate with patients and family members
     * - View analytics for assigned patients
     * - Manage billing and subscriptions
     * <p>
     * Typical Users: Nurses, healthcare workers, professional caregivers
     */
    CAREGIVER("Caregiver", "Professional caregiver managing patients"),

    /**
     * Patient receiving care through the CareConnect system.
     * <p>
     * Capabilities:
     * - View own health data and care plan
     * - Complete assigned tasks
     * - Record own health measurements
     * - Communicate with caregivers and family
     * - View own schedule and appointments
     * <p>
     * Typical Users: Elderly individuals, patients with chronic conditions
     */
    PATIENT("Patient", "Individual receiving care"),

    /**
     * Family member with read-only access to a linked patient.
     * <p>
     * Capabilities:
     * - View linked patient's health data (read-only)
     * - View care schedule and tasks (read-only)
     * - Communicate with caregivers
     * - Receive notifications about patient
     * <p>
     * Restrictions:
     * - Cannot modify any patient data
     * - Cannot create or edit tasks
     * - Cannot access billing information
     * <p>
     * Typical Users: Family members, friends, concerned relatives
     */
    FAMILY_MEMBER("Family Member", "Read-only access to linked patient");


    // ========== Instance Variables ==========

    /**
     * Human-readable display name for the role.
     * Used in UI dropdowns and user-facing messages.
     */
    private final String displayName;

    /**
     * Brief description of the role and its purpose.
     */
    private final String description;


    // ========== Constructor ==========

    /**
     * Private constructor called automatically for each enum constant.
     *
     * @param displayName User-friendly name for this role
     * @param description Brief explanation of role's purpose
     */
    Role(String displayName, String description) {
        this.displayName = displayName;
        this.description = description;
    }


    // ========== Public Methods ==========

    /**
     * Safely converts a string to a Role enum.
     * Handles case-insensitive input and provides helpful error messages.
     * <p>
     * Usage:
     * Role role = Role.fromString("caregiver");  // Works!
     * Role role = Role.fromString("ADMIN");      // Works!
     * Role role = Role.fromString("invalid");    // Throws exception with helpful message
     *
     * @param roleStr String representation of the role
     * @return Corresponding Role enum value
     * @throws IllegalArgumentException if role string is invalid
     */
    public static Role fromString(String roleStr) {
        // Handle null input
        if (roleStr == null || roleStr.trim().isEmpty()) {
            throw new IllegalArgumentException(
                    "Role cannot be null or empty. Valid roles are: " +
                            "ADMIN, CAREGIVER, PATIENT, FAMILY_MEMBER"
            );
        }

        // Convert to uppercase and handle common variations
        String normalized = roleStr.trim().toUpperCase();

        // Handle underscore vs space (e.g., "family member" vs "family_member")
        normalized = normalized.replace(' ', '_');

        // Try to find matching role
        try {
            return Role.valueOf(normalized);
        } catch (IllegalArgumentException e) {
            // Provide helpful error message with valid options
            throw new IllegalArgumentException(
                    String.format(
                            "Invalid role: '%s'. Valid roles are: ADMIN, CAREGIVER, PATIENT, FAMILY_MEMBER",
                            roleStr
                    )
            );
        }
    }

    /**
     * Gets the human-readable display name of this role.
     * Use this for UI elements and user-facing messages.
     *
     * @return Display name (e.g., "Administrator", "Caregiver")
     */
    public String getDisplayName() {
        return displayName;
    }

    /**
     * Gets the description of what this role can do.
     *
     * @return Role description
     */
    public String getDescription() {
        return description;
    }

    /**
     * Converts this role to a string suitable for API responses and database storage.
     * Returns lowercase with underscores (e.g., "family_member").
     *
     * @return API-friendly string representation
     */
    public String toApiString() {
        return this.name().toLowerCase();
    }

    /**
     * Checks if this role is an administrator.
     * Convenience method for common permission check.
     *
     * @return true if this role is ADMIN
     */
    public boolean isAdmin() {
        return this == ADMIN;
    }

    /**
     * Checks if this role is a caregiver.
     *
     * @return true if this role is CAREGIVER
     */
    public boolean isCaregiver() {
        return this == CAREGIVER;
    }

    /**
     * Checks if this role is a patient.
     *
     * @return true if this role is PATIENT
     */
    public boolean isPatient() {
        return this == PATIENT;
    }

    /**
     * Checks if this role is a family member.
     *
     * @return true if this role is FAMILY_MEMBER
     */
    public boolean isFamilyMember() {
        return this == FAMILY_MEMBER;
    }

    /**
     * Checks if this role can modify data (not read-only).
     * Family members have read-only access.
     *
     * @return true if role can create/update/delete data
     */
    public boolean canModifyData() {
        return this != FAMILY_MEMBER;
    }

    /**
     * Gets the hierarchy level of this role (lower number = more power).
     * Useful for comparing role authority levels.
     * <p>
     * Levels:
     * ADMIN = 0 (highest)
     * CAREGIVER = 1
     * PATIENT = 2
     * FAMILY_MEMBER = 3 (lowest)
     *
     * @return Hierarchy level (0-3)
     */
    public int getHierarchyLevel() {
        switch (this) {
            case ADMIN:
                return 0;
            case CAREGIVER:
                return 1;
            case PATIENT:
                return 2;
            case FAMILY_MEMBER:
                return 3;
            default:
                return Integer.MAX_VALUE; // Should never happen
        }
    }

    /**
     * Checks if this role has higher or equal authority than another role.
     *
     * @param otherRole Role to compare against
     * @return true if this role is higher or equal in hierarchy
     */
    public boolean hasHigherOrEqualAuthorityThan(Role otherRole) {
        return this.getHierarchyLevel() <= otherRole.getHierarchyLevel();
    }

    /**
     * Returns a detailed string representation of this role.
     *
     * @return Role information including name and description
     */
    @Override
    public String toString() {
        return String.format(
                "Role{name=%s, displayName='%s', description='%s'}",
                this.name(),
                this.displayName,
                this.description
        );
    }
}