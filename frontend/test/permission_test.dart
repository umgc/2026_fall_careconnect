import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/models/permission.dart';

void main() {
  group('Permission Enum Tests', () {
    test('Permission.fromString parses correctly', () {
      expect(
        Permission.fromString('VIEW_ALL_USERS'),
        Permission.viewAllUsers,
      );
      expect(
        Permission.fromString('CREATE_PATIENTS'),
        Permission.createPatients,
      );
      expect(
        Permission.fromString('DELETE_TASKS'),
        Permission.deleteTasks,
      );
      expect(
        Permission.fromString('USE_AI_FEATURES'),
        Permission.useAiFeatures,
      );
    });

    test('Permission.fromString throws on invalid permission', () {
      expect(() => Permission.fromString('INVALID'), throwsArgumentError);
      expect(() => Permission.fromString(''), throwsArgumentError);
    });

    test('isAdminOnly identifies admin permissions correctly', () {
      expect(Permission.viewAllUsers.isAdminOnly, true);
      expect(Permission.manageUsers.isAdminOnly, true);
      expect(Permission.assignRoles.isAdminOnly, true);
      expect(Permission.viewAllPatients.isAdminOnly, true);
      expect(Permission.deletePatients.isAdminOnly, true);
      expect(Permission.viewAuditLogs.isAdminOnly, true);

      expect(Permission.viewTasks.isAdminOnly, false);
      expect(Permission.createPatients.isAdminOnly, false);
      expect(Permission.sendMessages.isAdminOnly, false);
      expect(Permission.viewHealthData.isAdminOnly, false);
      expect(Permission.useAiFeatures.isAdminOnly, false);
    });

    test('displayName formats correctly', () {
      expect(
        Permission.viewAllUsers.displayName,
        'View All Users',
      );
      expect(
        Permission.createPatients.displayName,
        'Create Patients',
      );
      expect(
        Permission.viewHealthData.displayName,
        'View Health Data',
      );
    });

    test('description returns non-empty string', () {
      for (var permission in Permission.values) {
        expect(permission.description.isNotEmpty, true,
            reason: '${permission.name} should have a description');
      }
    });

    test('toBackendString returns correct enum name', () {
      expect(Permission.viewAllUsers.toBackendString(), 'VIEW_ALL_USERS');
      expect(Permission.createTasks.toBackendString(), 'CREATE_TASKS');
      expect(Permission.viewHealthData.toBackendString(), 'VIEW_HEALTH_DATA');
      expect(Permission.useAiFeatures.toBackendString(), 'USE_AI_FEATURES');
    });

    test('all 28 permissions exist', () {
      expect(Permission.values.length, 28,
          reason: 'Should have exactly 28 permissions matching backend');
    });

    test('permission categories are correct', () {
      expect(Permission.values.contains(Permission.viewAllPatients), true);
      expect(Permission.values.contains(Permission.useAiFeatures), true);
      expect(Permission.values.contains(Permission.manageDevices), true);
      expect(Permission.values.contains(Permission.manageNotifications), true);
      expect(Permission.values.contains(Permission.viewAuditLogs), true);
    });

    test('permission enum names match backend format', () {
      final testCases = {
        Permission.viewAllUsers: 'VIEW_ALL_USERS',
        Permission.createPatients: 'CREATE_PATIENTS',
        Permission.recordHealthData: 'RECORD_HEALTH_DATA',
        Permission.useAiFeatures: 'USE_AI_FEATURES',
        Permission.manageNotifications: 'MANAGE_NOTIFICATIONS',
        Permission.viewAuditLogs: 'VIEW_AUDIT_LOGS',
      };

      testCases.forEach((permission, expectedBackendName) {
        expect(
          permission.toBackendString(),
          expectedBackendName,
          reason: '${permission.name} should convert to $expectedBackendName',
        );
      });
    });
  });
}
