import 'package:flutter_test/flutter_test.dart';

import 'package:care_connect_app/features/admin_users/models/admin_user_model.dart';

void main() {
  group('AdminUser.fromJson', () {
    test('parses user summary fields', () {
      final user = AdminUser.fromJson({
        'id': 2,
        'name': 'Jane Doe',
        'email': 'jane@example.com',
        'role': 'CAREGIVER',
        'emailVerified': true,
        'lastLoginDate': '2026-07-01',
      });

      expect(user.id, 2);
      expect(user.name, 'Jane Doe');
      expect(user.email, 'jane@example.com');
      expect(user.role, 'CAREGIVER');
      expect(user.emailVerified, isTrue);
      expect(user.lastLoginDate, '2026-07-01');
      expect(user.isAdmin, isFalse);
    });

    test('isAdmin is true for ADMIN role', () {
      final user = AdminUser.fromJson({
        'id': 1,
        'name': 'Admin',
        'email': 'admin@test.com',
        'role': 'ADMIN',
        'emailVerified': true,
      });

      expect(user.isAdmin, isTrue);
    });
  });
}
