/// Permission checking helper based on roles.
/// Permission strings match backend RolePermissionService; see [Permission] enum for all 29 values.
class PermissionHelper {
  /// Check if role has specific permission
  static bool hasPermission(String role, String permission) {
    final r = role.toUpperCase();
    final p = permission.toUpperCase();

    // Admin has all permissions
    if (r == 'ADMIN') return true;

    // Check permission by role
    return _getRolePermissions(r).contains(p);
  }

  /// Check if role has any of the specified permissions
  static bool hasAnyPermission(String role, List<String> permissions) {
    return permissions.any((permission) => hasPermission(role, permission));
  }

  /// Check if role has all of the specified permissions
  static bool hasAllPermissions(String role, List<String> permissions) {
    return permissions.every((permission) => hasPermission(role, permission));
  }

  /// Get all permissions for a role
  /// IMPORTANT: This matches your backend RolePermissionService exactly
  static Set<String> _getRolePermissions(String role) {
    switch (role.toUpperCase()) {
      case 'ADMIN':
        // Admin has all 27 listed permissions (hasPermission short-circuits to true)
        return {
          'VIEW_ALL_USERS',
          'MANAGE_USERS',
          'ASSIGN_ROLES',
          'VIEW_ALL_PATIENTS',
          'VIEW_ASSIGNED_PATIENTS',
          'CREATE_PATIENTS',
          'UPDATE_PATIENTS',
          'DELETE_PATIENTS',
          'CREATE_TASKS',
          'VIEW_TASKS',
          'UPDATE_TASKS',
          'DELETE_TASKS',
          'COMPLETE_TASKS',
          'VIEW_HEALTH_DATA',
          'RECORD_HEALTH_DATA',
          'EXPORT_HEALTH_DATA',
          'VIEW_BILLING',
          'MANAGE_SUBSCRIPTIONS',
          'SEND_MESSAGES',
          'VIEW_MESSAGES',
          'VIEW_ANALYTICS',
          'EXPORT_REPORTS',
          'USE_AI_FEATURES',
          'REVIEW_AI_HOLDS',
          'MANAGE_DEVICES',
          'MANAGE_NOTIFICATIONS',
          'VIEW_AUDIT_LOGS',
        };

      case 'CAREGIVER':
      case 'FAMILY_LINK':
        // Caregiver has 20 permissions (matches backend RolePermissionService)
        return {
          'VIEW_ASSIGNED_PATIENTS',
          'CREATE_PATIENTS',
          'UPDATE_PATIENTS',
          'CREATE_TASKS',
          'VIEW_TASKS',
          'UPDATE_TASKS',
          'DELETE_TASKS',
          'COMPLETE_TASKS',
          'VIEW_HEALTH_DATA',
          'RECORD_HEALTH_DATA',
          'EXPORT_HEALTH_DATA',
          'VIEW_BILLING',
          'MANAGE_SUBSCRIPTIONS',
          'SEND_MESSAGES',
          'VIEW_MESSAGES',
          'VIEW_ANALYTICS',
          'EXPORT_REPORTS',
          'USE_AI_FEATURES',
          'REVIEW_AI_HOLDS',
          'MANAGE_DEVICES',
        };

      case 'PATIENT':
        // Patient has 7 permissions (includes USE_AI_FEATURES for Ask AI on own records)
        return {
          'VIEW_TASKS',
          'COMPLETE_TASKS',
          'VIEW_HEALTH_DATA',
          'RECORD_HEALTH_DATA',
          'SEND_MESSAGES',
          'VIEW_MESSAGES',
          'USE_AI_FEATURES',
        };

      case 'FAMILY_MEMBER':
        // Family member has 3 permissions (read-only)
        return {'VIEW_TASKS', 'VIEW_HEALTH_DATA', 'VIEW_MESSAGES'};

      default:
        return {};
    }
  }

  /// Get count of permissions for a role (useful for testing)
  static int getPermissionCount(String role) {
    return _getRolePermissions(role.toUpperCase()).length;
  }
}
