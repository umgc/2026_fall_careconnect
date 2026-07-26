/// Permissions in the CareConnect system.
/// Must match backend Permission enum exactly (29 total).
enum Permission {
  // User Management (3)
  viewAllUsers,
  manageUsers,
  assignRoles,

  // Patient Management (5)
  viewAllPatients,
  viewAssignedPatients,
  createPatients,
  updatePatients,
  deletePatients,

  // Task Management (5)
  createTasks,
  viewTasks,
  updateTasks,
  deleteTasks,
  completeTasks,

  // Health Data (3)
  viewHealthData,
  recordHealthData,
  exportHealthData,

  // Medication Management (2)
  viewMedications,
  manageMedications,

  // Billing (2)
  viewBilling,
  manageSubscriptions,

  // Messaging (2)
  sendMessages,
  viewMessages,

  // Analytics & Reports (2)
  viewAnalytics,
  exportReports,

  // AI & Assistant (2)
  useAiFeatures,
  reviewAiHolds,

  // Device Integration (1)
  manageDevices,

  // Notification & Audit (2)
  manageNotifications,
  viewAuditLogs;

  /// Convert from backend string (SCREAMING_SNAKE_CASE) to Dart enum.
  static Permission fromString(String permissionString) {
    switch (permissionString.toUpperCase()) {
      case 'VIEW_ALL_USERS':
        return Permission.viewAllUsers;
      case 'MANAGE_USERS':
        return Permission.manageUsers;
      case 'ASSIGN_ROLES':
        return Permission.assignRoles;
      case 'VIEW_ALL_PATIENTS':
        return Permission.viewAllPatients;
      case 'VIEW_ASSIGNED_PATIENTS':
        return Permission.viewAssignedPatients;
      case 'CREATE_PATIENTS':
        return Permission.createPatients;
      case 'UPDATE_PATIENTS':
        return Permission.updatePatients;
      case 'DELETE_PATIENTS':
        return Permission.deletePatients;
      case 'CREATE_TASKS':
        return Permission.createTasks;
      case 'VIEW_TASKS':
        return Permission.viewTasks;
      case 'UPDATE_TASKS':
        return Permission.updateTasks;
      case 'DELETE_TASKS':
        return Permission.deleteTasks;
      case 'COMPLETE_TASKS':
        return Permission.completeTasks;
      case 'VIEW_HEALTH_DATA':
        return Permission.viewHealthData;
      case 'RECORD_HEALTH_DATA':
        return Permission.recordHealthData;
      case 'EXPORT_HEALTH_DATA':
        return Permission.exportHealthData;
      case 'VIEW_MEDICATIONS':
        return Permission.viewMedications;
      case 'MANAGE_MEDICATIONS':
        return Permission.manageMedications;
      case 'VIEW_BILLING':
        return Permission.viewBilling;
      case 'MANAGE_SUBSCRIPTIONS':
        return Permission.manageSubscriptions;
      case 'SEND_MESSAGES':
        return Permission.sendMessages;
      case 'VIEW_MESSAGES':
        return Permission.viewMessages;
      case 'VIEW_ANALYTICS':
        return Permission.viewAnalytics;
      case 'EXPORT_REPORTS':
        return Permission.exportReports;
      case 'USE_AI_FEATURES':
        return Permission.useAiFeatures;
      case 'REVIEW_AI_HOLDS':
        return Permission.reviewAiHolds;
      case 'MANAGE_DEVICES':
        return Permission.manageDevices;
      case 'MANAGE_NOTIFICATIONS':
        return Permission.manageNotifications;
      case 'VIEW_AUDIT_LOGS':
        return Permission.viewAuditLogs;
      default:
        throw ArgumentError('Unknown permission: $permissionString');
    }
  }

  /// Convert to backend format (SCREAMING_SNAKE_CASE).
  String toBackendString() {
    switch (this) {
      case Permission.viewAllUsers:
        return 'VIEW_ALL_USERS';
      case Permission.manageUsers:
        return 'MANAGE_USERS';
      case Permission.assignRoles:
        return 'ASSIGN_ROLES';
      case Permission.viewAllPatients:
        return 'VIEW_ALL_PATIENTS';
      case Permission.viewAssignedPatients:
        return 'VIEW_ASSIGNED_PATIENTS';
      case Permission.createPatients:
        return 'CREATE_PATIENTS';
      case Permission.updatePatients:
        return 'UPDATE_PATIENTS';
      case Permission.deletePatients:
        return 'DELETE_PATIENTS';
      case Permission.createTasks:
        return 'CREATE_TASKS';
      case Permission.viewTasks:
        return 'VIEW_TASKS';
      case Permission.updateTasks:
        return 'UPDATE_TASKS';
      case Permission.deleteTasks:
        return 'DELETE_TASKS';
      case Permission.completeTasks:
        return 'COMPLETE_TASKS';
      case Permission.viewHealthData:
        return 'VIEW_HEALTH_DATA';
      case Permission.recordHealthData:
        return 'RECORD_HEALTH_DATA';
      case Permission.exportHealthData:
        return 'EXPORT_HEALTH_DATA';
      case Permission.viewMedications:
        return 'VIEW_MEDICATIONS';
      case Permission.manageMedications:
        return 'MANAGE_MEDICATIONS';
      case Permission.viewBilling:
        return 'VIEW_BILLING';
      case Permission.manageSubscriptions:
        return 'MANAGE_SUBSCRIPTIONS';
      case Permission.sendMessages:
        return 'SEND_MESSAGES';
      case Permission.viewMessages:
        return 'VIEW_MESSAGES';
      case Permission.viewAnalytics:
        return 'VIEW_ANALYTICS';
      case Permission.exportReports:
        return 'EXPORT_REPORTS';
      case Permission.useAiFeatures:
        return 'USE_AI_FEATURES';
      case Permission.reviewAiHolds:
        return 'REVIEW_AI_HOLDS';
      case Permission.manageDevices:
        return 'MANAGE_DEVICES';
      case Permission.manageNotifications:
        return 'MANAGE_NOTIFICATIONS';
      case Permission.viewAuditLogs:
        return 'VIEW_AUDIT_LOGS';
    }
  }

  /// Get display name for UI (converts camelCase to Title Case).
  String get displayName {
    final name = toString().split('.').last;
    final result = name.replaceAllMapped(
      RegExp(r'([A-Z])'),
      (match) => ' ${match.group(0)}',
    );
    return result[0].toUpperCase() + result.substring(1);
  }

  /// Get permission description.
  String get description {
    switch (this) {
      case Permission.viewAllUsers:
        return 'View all users in the system';
      case Permission.manageUsers:
        return 'Create, update, and delete users';
      case Permission.assignRoles:
        return 'Assign and modify user roles';
      case Permission.viewAllPatients:
        return 'View all patients in the system';
      case Permission.viewAssignedPatients:
        return 'View assigned patient information';
      case Permission.createPatients:
        return 'Create new patient records';
      case Permission.updatePatients:
        return 'Update existing patient information';
      case Permission.deletePatients:
        return 'Delete patient records';
      case Permission.createTasks:
        return 'Create new tasks';
      case Permission.viewTasks:
        return 'View tasks and care plans';
      case Permission.updateTasks:
        return 'Update existing tasks';
      case Permission.deleteTasks:
        return 'Delete tasks';
      case Permission.completeTasks:
        return 'Mark tasks as complete';
      case Permission.viewHealthData:
        return 'View patient health data';
      case Permission.recordHealthData:
        return 'Record and update health metrics';
      case Permission.exportHealthData:
        return 'Export health data reports';
      case Permission.viewMedications:
        return 'View medication schedules';
      case Permission.manageMedications:
        return 'Add, update, and remove medications';
      case Permission.viewBilling:
        return 'View billing and payment information';
      case Permission.manageSubscriptions:
        return 'Manage subscriptions and plans';
      case Permission.sendMessages:
        return 'Send messages to other users';
      case Permission.viewMessages:
        return 'View messages and communications';
      case Permission.viewAnalytics:
        return 'View analytics and insights';
      case Permission.exportReports:
        return 'Generate and export reports';
      case Permission.useAiFeatures:
        return 'Use AI assistant features';
      case Permission.reviewAiHolds:
        return 'Review and release held Ask AI answers';
      case Permission.manageDevices:
        return 'Connect and manage wearable devices';
      case Permission.manageNotifications:
        return 'Manage notification preferences';
      case Permission.viewAuditLogs:
        return 'View system audit logs';
    }
  }

  /// Check if this permission is admin-only.
  bool get isAdminOnly {
    return this == Permission.viewAllUsers ||
        this == Permission.manageUsers ||
        this == Permission.assignRoles ||
        this == Permission.viewAllPatients ||
        this == Permission.deletePatients ||
        this == Permission.viewAuditLogs;
  }

  /// Get permission category.
  PermissionCategory get category {
    if ([viewAllUsers, manageUsers, assignRoles].contains(this)) {
      return PermissionCategory.userManagement;
    }
    if ([
      viewAllPatients,
      viewAssignedPatients,
      createPatients,
      updatePatients,
      deletePatients,
    ].contains(this)) {
      return PermissionCategory.patientManagement;
    }
    if ([viewHealthData, recordHealthData, exportHealthData].contains(this)) {
      return PermissionCategory.healthData;
    }
    if ([createTasks, viewTasks, updateTasks, deleteTasks, completeTasks]
        .contains(this)) {
      return PermissionCategory.taskManagement;
    }
    if ([viewMedications, manageMedications].contains(this)) {
      return PermissionCategory.medicationManagement;
    }
    if ([viewAnalytics, exportReports].contains(this)) {
      return PermissionCategory.analytics;
    }
    if ([viewMessages, sendMessages].contains(this)) {
      return PermissionCategory.messaging;
    }
    if ([viewBilling, manageSubscriptions].contains(this)) {
      return PermissionCategory.billing;
    }
    if (this == Permission.useAiFeatures || this == Permission.reviewAiHolds) {
      return PermissionCategory.aiAssistant;
    }
    if (this == Permission.manageDevices) {
      return PermissionCategory.deviceIntegration;
    }
    return PermissionCategory.system;
  }
}

/// Permission categories for grouping and display.
enum PermissionCategory {
  userManagement,
  patientManagement,
  healthData,
  taskManagement,
  medicationManagement,
  analytics,
  messaging,
  billing,
  aiAssistant,
  deviceIntegration,
  system;

  String get displayName {
    switch (this) {
      case PermissionCategory.userManagement:
        return 'User Management';
      case PermissionCategory.patientManagement:
        return 'Patient Management';
      case PermissionCategory.healthData:
        return 'Health Data';
      case PermissionCategory.taskManagement:
        return 'Task Management';
      case PermissionCategory.medicationManagement:
        return 'Medication Management';
      case PermissionCategory.analytics:
        return 'Analytics & Reports';
      case PermissionCategory.messaging:
        return 'Messaging';
      case PermissionCategory.billing:
        return 'Billing';
      case PermissionCategory.aiAssistant:
        return 'AI & Assistant';
      case PermissionCategory.deviceIntegration:
        return 'Device Integration';
      case PermissionCategory.system:
        return 'System';
    }
  }
}
