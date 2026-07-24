// Tests for Permission enum (lib/models/permission.dart).

import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/models/permission.dart';

void main() {
  group('Permission.fromString', () {
    test('parses VIEW_ALL_USERS (case-insensitive)', () {
      expect(Permission.fromString('VIEW_ALL_USERS'), Permission.viewAllUsers);
      expect(Permission.fromString('view_all_users'), Permission.viewAllUsers);
    });

    test('parses USE_AI_FEATURES', () {
      expect(
        Permission.fromString('USE_AI_FEATURES'),
        Permission.useAiFeatures,
      );
      expect(
        Permission.fromString('use_ai_features'),
        Permission.useAiFeatures,
      );
    });

    test('parses REVIEW_AI_HOLDS', () {
      expect(
        Permission.fromString('REVIEW_AI_HOLDS'),
        Permission.reviewAiHolds,
      );
    });

    test('parses VIEW_ALL_PATIENTS', () {
      expect(
        Permission.fromString('VIEW_ALL_PATIENTS'),
        Permission.viewAllPatients,
      );
    });

    test('parses MANAGE_DEVICES and MANAGE_NOTIFICATIONS', () {
      expect(
        Permission.fromString('MANAGE_DEVICES'),
        Permission.manageDevices,
      );
      expect(
        Permission.fromString('MANAGE_NOTIFICATIONS'),
        Permission.manageNotifications,
      );
    });

    test('throws ArgumentError for unknown permission', () {
      expect(() => Permission.fromString('UNKNOWN_PERM'), throwsArgumentError);
      expect(() => Permission.fromString(''), throwsArgumentError);
      expect(
        () => Permission.fromString('MANAGE_SYSTEM_SETTINGS'),
        throwsArgumentError,
      );
    });
  });

  group('Permission.toBackendString', () {
    test('useAiFeatures → USE_AI_FEATURES', () {
      expect(Permission.useAiFeatures.toBackendString(), 'USE_AI_FEATURES');
    });

    test('round-trips all 29 permissions', () {
      expect(Permission.values.length, 29);
      for (final perm in Permission.values) {
        expect(Permission.fromString(perm.toBackendString()), perm);
      }
    });
  });

  group('Permission.displayName', () {
    test('all permissions have non-empty display names', () {
      for (final perm in Permission.values) {
        expect(perm.displayName, isNotEmpty);
      }
    });
  });

  group('Permission.description', () {
    test('all permissions have non-empty descriptions', () {
      for (final perm in Permission.values) {
        expect(perm.description, isNotEmpty);
      }
    });
  });

  group('Permission.isAdminOnly', () {
    test('viewAllPatients is admin-only', () {
      expect(Permission.viewAllPatients.isAdminOnly, isTrue);
    });

    test('useAiFeatures is NOT admin-only', () {
      expect(Permission.useAiFeatures.isAdminOnly, isFalse);
    });

    test('viewHealthData is NOT admin-only', () {
      expect(Permission.viewHealthData.isAdminOnly, isFalse);
    });
  });

  group('Permission.category', () {
    test('useAiFeatures → aiAssistant', () {
      expect(Permission.useAiFeatures.category, PermissionCategory.aiAssistant);
    });

    test('manageDevices → deviceIntegration', () {
      expect(
        Permission.manageDevices.category,
        PermissionCategory.deviceIntegration,
      );
    });

    test('manageNotifications → system', () {
      expect(
        Permission.manageNotifications.category,
        PermissionCategory.system,
      );
    });
  });

  group('PermissionCategory.displayName', () {
    test('all categories have non-empty display names', () {
      for (final cat in PermissionCategory.values) {
        expect(cat.displayName, isNotEmpty);
      }
    });
  });
}
