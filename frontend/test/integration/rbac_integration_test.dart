import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/utils/role_helper.dart';
import 'package:care_connect_app/utils/permission_helper.dart';

void main() {
  group('RBAC Integration Tests', () {
    test('Complete role and permission flow for Admin', () {
      const role = 'ADMIN';

      // Role checks
      expect(RoleHelper.isAdmin(role), true);
      expect(RoleHelper.isCaregiverOrAdmin(role), true);
      expect(RoleHelper.canManagePatients(role), true);
      expect(RoleHelper.canModifyData(role), true);

      // Permission checks
      expect(PermissionHelper.hasPermission(role, 'VIEW_ALL_USERS'), true);
      expect(PermissionHelper.hasPermission(role, 'DELETE_PATIENTS'), true);
      expect(PermissionHelper.hasPermission(role, 'VIEW_AUDIT_LOGS'), true);

      // Verify permission count
      expect(PermissionHelper.getPermissionCount(role), 26);
    });

    test('Complete role and permission flow for Caregiver', () {
      const role = 'CAREGIVER';

      // Role checks
      expect(RoleHelper.isAdmin(role), false);
      expect(RoleHelper.isCaregiver(role), true);
      expect(RoleHelper.isCaregiverOrAdmin(role), true);
      expect(RoleHelper.canManagePatients(role), true);
      expect(RoleHelper.canModifyData(role), true);

      // Has permissions
      expect(PermissionHelper.hasPermission(role, 'CREATE_PATIENTS'), true);
      expect(PermissionHelper.hasPermission(role, 'DELETE_TASKS'), true);

      // Doesn't have admin permissions
      expect(PermissionHelper.hasPermission(role, 'VIEW_ALL_USERS'), false);
      expect(PermissionHelper.hasPermission(role, 'DELETE_PATIENTS'), false);

      // Verify permission count
      expect(PermissionHelper.getPermissionCount(role), 19);
    });

    test('Complete role and permission flow for Patient', () {
      const role = 'PATIENT';

      // Role checks
      expect(RoleHelper.isPatient(role), true);
      expect(RoleHelper.isCaregiverOrAdmin(role), false);
      expect(RoleHelper.canManagePatients(role), false);
      expect(RoleHelper.canModifyData(role), true);

      // Has limited permissions
      expect(PermissionHelper.hasPermission(role, 'VIEW_TASKS'), true);
      expect(PermissionHelper.hasPermission(role, 'VIEW_HEALTH_DATA'), true);
      expect(PermissionHelper.hasPermission(role, 'USE_AI_FEATURES'), true);

      // Doesn't have create/delete permissions
      expect(PermissionHelper.hasPermission(role, 'CREATE_TASKS'), false);
      expect(PermissionHelper.hasPermission(role, 'DELETE_PATIENTS'), false);

      // Verify permission count
      expect(PermissionHelper.getPermissionCount(role), 7);
    });

    test('Complete role and permission flow for Family Member', () {
      const role = 'FAMILY_MEMBER';

      // Role checks
      expect(RoleHelper.isFamilyMember(role), true);
      expect(RoleHelper.canModifyData(role), false);
      expect(RoleHelper.canManagePatients(role), false);

      // Has read-only permissions
      expect(PermissionHelper.hasPermission(role, 'VIEW_TASKS'), true);
      expect(PermissionHelper.hasPermission(role, 'VIEW_HEALTH_DATA'), true);

      // Cannot modify anything
      expect(PermissionHelper.hasPermission(role, 'COMPLETE_TASKS'), false);
      expect(PermissionHelper.hasPermission(role, 'RECORD_HEALTH_DATA'), false);

      // Verify permission count
      expect(PermissionHelper.getPermissionCount(role), 3);
    });

    test('Permission counts match backend exactly', () {
      expect(PermissionHelper.getPermissionCount('ADMIN'), 26);
      expect(PermissionHelper.getPermissionCount('CAREGIVER'), 19);
      expect(PermissionHelper.getPermissionCount('FAMILY_LINK'), 19);
      expect(PermissionHelper.getPermissionCount('PATIENT'), 7);
      expect(PermissionHelper.getPermissionCount('FAMILY_MEMBER'), 3);
    });

    test('All roles have correct login routes', () {
      expect(RoleHelper.getLoginRoute('ADMIN'), '/login/caregiver');
      expect(RoleHelper.getLoginRoute('CAREGIVER'), '/login/caregiver');
      expect(RoleHelper.getLoginRoute('FAMILY_LINK'), '/login/caregiver');
      expect(RoleHelper.getLoginRoute('PATIENT'), '/login/patient');
      expect(RoleHelper.getLoginRoute('FAMILY_MEMBER'), '/login/patient');
    });
  });
}