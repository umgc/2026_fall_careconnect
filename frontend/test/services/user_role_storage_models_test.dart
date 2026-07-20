// Tests for UserData model.
// (lib/services/user_role_storage_service.dart)
//
// Pure Dart model tests — constructor, toString, copyWith.

import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/services/user_role_storage_service.dart'
    show UserData;

void main() {
  group('UserData', () {
    test('constructor stores all required fields', () {
      // Arrange + Act
      const data = UserData(
        role: 'CAREGIVER',
        userId: 42,
        isLoggedIn: true,
      );

      // Assert
      expect(data.role, 'CAREGIVER');
      expect(data.userId, 42);
      expect(data.isLoggedIn, true);
      expect(data.patientId, isNull);
      expect(data.caregiverId, isNull);
    });

    test('constructor with all optional fields', () {
      const data = UserData(
        role: 'PATIENT',
        userId: 10,
        patientId: 100,
        caregiverId: 200,
        isLoggedIn: true,
      );

      expect(data.patientId, 100);
      expect(data.caregiverId, 200);
    });

    test('toString includes all fields', () {
      const data = UserData(
        role: 'ADMIN',
        userId: 1,
        patientId: null,
        caregiverId: 5,
        isLoggedIn: true,
      );

      final str = data.toString();
      expect(str, contains('ADMIN'));
      expect(str, contains('1'));
      expect(str, contains('5'));
      expect(str, contains('true'));
    });

    test('copyWith updates specified fields', () {
      // Arrange
      const original = UserData(
        role: 'PATIENT',
        userId: 10,
        patientId: 100,
        isLoggedIn: true,
      );

      // Act
      final updated = original.copyWith(role: 'CAREGIVER', caregiverId: 50);

      // Assert
      expect(updated.role, 'CAREGIVER');
      expect(updated.userId, 10);
      expect(updated.patientId, 100);
      expect(updated.caregiverId, 50);
      expect(updated.isLoggedIn, true);
    });

    test('copyWith preserves unchanged fields', () {
      const original = UserData(
        role: 'CAREGIVER',
        userId: 42,
        caregiverId: 10,
        isLoggedIn: true,
      );

      final copy = original.copyWith();
      expect(copy.role, 'CAREGIVER');
      expect(copy.userId, 42);
      expect(copy.caregiverId, 10);
      expect(copy.isLoggedIn, true);
    });

    test('copyWith can change isLoggedIn', () {
      const data = UserData(
        role: 'PATIENT',
        userId: 1,
        isLoggedIn: true,
      );

      final loggedOut = data.copyWith(isLoggedIn: false);
      expect(loggedOut.isLoggedIn, false);
      expect(loggedOut.role, 'PATIENT');
    });

    test('constructor with FAMILY_MEMBER role', () {
      const data = UserData(
        role: 'FAMILY_MEMBER',
        userId: 99,
        isLoggedIn: true,
      );
      expect(data.role, 'FAMILY_MEMBER');
    });

    test('constructor with isLoggedIn false', () {
      const data = UserData(
        role: '',
        userId: 0,
        isLoggedIn: false,
      );
      expect(data.isLoggedIn, false);
      expect(data.userId, 0);
    });

    test('toString with null optional fields', () {
      const data = UserData(
        role: 'PATIENT',
        userId: 5,
        isLoggedIn: true,
      );
      expect(data.toString(), contains('null'));
    });

    test('copyWith can change userId', () {
      const data = UserData(
        role: 'CAREGIVER',
        userId: 1,
        isLoggedIn: true,
      );
      final updated = data.copyWith(userId: 999);
      expect(updated.userId, 999);
    });
  });
}
