package com.careconnect.security;

/**
 * Enumeration of all permissions in the CareConnect system.
 * <p>
 * Permissions represent fine-grained actions that users can perform.
 * Each permission is assigned to one or more roles via the RolePermissionService.
 * <p>
 * Usage:
 * - Check if user has permission: user.hasPermission(Permission.CREATE_TASKS)
 * - In controllers: authorizationService.requirePermission(user, Permission.VIEW_HEALTH_DATA)
 *
 * @author CareConnect Team
 * @version 1.0
 */
public enum Permission {

    // ========== User Management Permissions ==========

    /**
     * View all users in the system (admin only).
     * Allows access to complete user directory.
     */
    VIEW_ALL_USERS("View all users in the system"),

    /**
     * Create, update, and delete user accounts.
     * Includes modifying user profile information.
     */
    MANAGE_USERS("Create, update, delete users"),

    /**
     * Change user roles and permissions.
     * Critical permission - admin only.
     */
    ASSIGN_ROLES("Change user roles"),


    // ========== Patient Management Permissions ==========

    /**
     * View all patients in the system (admin only).
     * Unrestricted access to all patient records.
     */
    VIEW_ALL_PATIENTS("View all patients (admin only)"),

    /**
     * View patients assigned to the current user.
     * Caregivers see only their assigned patients.
     */
    VIEW_ASSIGNED_PATIENTS("View patients assigned to you"),

    /**
     * Create new patient profiles.
     * Includes entering demographic and medical information.
     */
    CREATE_PATIENTS("Create new patient profiles"),

    /**
     * Update existing patient information.
     * Modify demographics, medical history, contact info.
     */
    UPDATE_PATIENTS("Update patient information"),

    /**
     * Delete or archive patient profiles.
     * Permanently removes or soft-deletes patient records.
     */
    DELETE_PATIENTS("Delete patient profiles"),


    // ========== Task Management Permissions ==========

    /**
     * Create tasks and care schedules for patients.
     * Includes one-time and recurring tasks.
     */
    CREATE_TASKS("Create tasks for patients"),

    /**
     * View tasks and schedules.
     * Filtered by patient access permissions.
     */
    VIEW_TASKS("View tasks"),

    /**
     * Update task details, schedules, and priorities.
     * Modify existing task information.
     */
    UPDATE_TASKS("Update task details"),

    /**
     * Delete tasks and schedules.
     * Remove tasks from the system.
     */
    DELETE_TASKS("Delete tasks"),

    /**
     * Mark tasks as complete.
     * Patients can complete their own tasks, caregivers can complete any assigned task.
     */
    COMPLETE_TASKS("Mark tasks as complete"),


    // ========== Health Data Permissions ==========

    /**
     * View patient health metrics and vital signs.
     * Includes blood pressure, heart rate, glucose, weight, etc.
     */
    VIEW_HEALTH_DATA("View patient health metrics"),

    /**
     * Record new health measurements.
     * Add new vital signs and health data points.
     */
    RECORD_HEALTH_DATA("Record health measurements"),

    /**
     * Export health data reports.
     * Generate CSV, PDF, or other formats for download.
     */
    EXPORT_HEALTH_DATA("Export health data reports"),


    // ========== Medication Permissions ==========

    /**
     * View medication information for patients.
     * Access to medication lists and prescription details.
     */
    VIEW_MEDICATIONS("View medication information"),

    /**
     * Manage medications for patients.
     * Add, update, and remove medication records.
     */
    MANAGE_MEDICATIONS("Manage patient medications"),


    // ========== Billing & Subscription Permissions ==========

    /**
     * View billing information and invoice history.
     * Access to payment records and subscription status.
     */
    VIEW_BILLING("View billing information"),

    /**
     * Manage subscription plans and payments.
     * Subscribe, upgrade, downgrade, cancel subscriptions.
     */
    MANAGE_SUBSCRIPTIONS("Manage subscription plans"),


    // ========== Communication Permissions ==========

    /**
     * Send messages to care circle members.
     * Includes text messages, images, and file attachments.
     */
    SEND_MESSAGES("Send messages to care circle"),

    /**
     * View messages and conversation history.
     * Access to message threads and communications.
     */
    VIEW_MESSAGES("View messages"),


    // ========== Analytics & Reporting Permissions ==========

    /**
     * View analytics dashboards and metrics.
     * Access to QuickSight dashboards and data visualizations.
     */
    VIEW_ANALYTICS("View analytics dashboards"),

    /**
     * Export reports and analytics data.
     * Generate and download analytics reports.
     */
    EXPORT_REPORTS("Export reports and data"),


    // ========== AI & Assistant Permissions ==========

    /**
     * Use AI assistant features.
     * Access to AI-powered health insights and recommendations.
     */
    USE_AI_FEATURES("Use AI assistant features"),

    /**
     * Review and release or reject held Ask AI answers (Tier-2 HITL).
     * Narrower than USE_AI_FEATURES — caregivers/admins on the review queue only.
     */
    REVIEW_AI_HOLDS("Review and release held Ask AI answers"),


    // ========== Device Integration Permissions ==========

    /**
     * Connect and manage wearable devices.
     * Link Fitbit, Apple Health, Google Fit devices.
     */
    MANAGE_DEVICES("Connect and manage wearable devices"),


    // ========== Notification & Audit Permissions ==========

    /**
     * Manage notification preferences and settings.
     * Configure alert types, delivery methods, and schedules.
     */
    MANAGE_NOTIFICATIONS("Manage notification preferences"),

    /**
     * View system audit logs and access history.
     * Access to security logs and compliance reports (admin only).
     */
    VIEW_AUDIT_LOGS("View system audit logs");


    // ========== Instance Variables ==========

    /**
     * Human-readable description of what this permission allows.
     */
    private final String description;


    // ========== Constructor ==========

    /**
     * Private constructor called automatically for each enum constant.
     *
     * @param description Human-readable description of the permission
     */
    Permission(String description) {
        this.description = description;
    }

    // ========== Public Methods ==========

    /**
     * Gets the human-readable description of this permission.
     *
     * @return Description explaining what this permission allows
     */
    public String getDescription() {
        return description;
    }

    /**
     * Gets the permission name formatted for display.
     * Converts CREATE_TASKS to "Create Tasks" with each word capitalized.
     *
     * @return Formatted permission name with proper capitalization
     * @example Permission.CREATE_TASKS.getDisplayName() returns "Create Tasks"
     * Permission.VIEW_HEALTH_DATA.getDisplayName() returns "View Health Data"
     */
    public String getDisplayName() {
        // Split on underscores: CREATE_TASKS -> ["CREATE", "TASKS"]
        String[] words = this.name().split("_");
        StringBuilder result = new StringBuilder();

        for (String word : words) {
            if (result.length() > 0) {
                result.append(" ");
            }
            // Capitalize first letter, lowercase the rest
            // "CREATE" -> "Create"
            result.append(Character.toUpperCase(word.charAt(0)))
                    .append(word.substring(1).toLowerCase());
        }

        return result.toString();
    }

    /**
     * Checks if this is an admin-only permission.
     *
     * @return true if permission is restricted to admins
     */
    public boolean isAdminOnly() {
        return this == VIEW_ALL_USERS ||
                this == MANAGE_USERS ||
                this == ASSIGN_ROLES ||
                this == VIEW_ALL_PATIENTS ||
                this == DELETE_PATIENTS ||
                this == VIEW_AUDIT_LOGS;
    }

    /**
     * Returns a string representation of this permission.
     *
     * @return Permission name and description
     */
    @Override
    public String toString() {
        return this.name() + ": " + description;
    }
}