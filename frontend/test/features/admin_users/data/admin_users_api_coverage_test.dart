// Coverage tests for AdminUsersApi (fetchUsers / promoteToAdmin and the
// error-message parser). HTTP is intercepted with http.runWithClient.

import 'dart:convert';

import 'package:care_connect_app/features/admin_users/data/admin_users_api.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Future<T> _withClient<T>(
  Future<T> Function() body,
  Future<http.Response> Function(http.Request) handler,
) {
  return http.runWithClient(body, () => MockClient(handler));
}

Matcher _apiError(String message, int? status) =>
    isA<AdminUsersApiException>()
        .having((e) => e.message, 'message', message)
        .having((e) => e.statusCode, 'statusCode', status)
        .having((e) => e.toString(), 'toString', message);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const api = AdminUsersApi();

  setUp(() {
    final expiry = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
    FlutterSecureStorage.setMockInitialValues({
      'jwt_token': 'admin-jwt',
      'token_expiry': '$expiry',
    });
  });

  group('fetchUsers', () {
    test('parses a list of users and skips non-map rows', () async {
      late http.Request seen;
      final users = await _withClient(
        () => api.fetchUsers(),
        (req) async {
          seen = req;
          return http.Response(
            jsonEncode([
              {
                'id': 1,
                'name': 'Ann',
                'email': 'a@x.com',
                'role': 'ADMIN',
                'emailVerified': true,
              },
              'garbage',
              {'id': 2, 'name': 'Bob'},
            ]),
            200,
          );
        },
      );
      expect(users.map((u) => u.id), [1, 2]);
      expect(users.first.role, 'ADMIN');
      expect(seen.url.path, endsWith('/v1/api/admin/users'));
      expect(seen.headers['Authorization'], 'Bearer admin-jwt');
    });

    test('throws when the 200 body is not a list', () async {
      await expectLater(
        _withClient(
          () => api.fetchUsers(),
          (_) async => http.Response(jsonEncode({'users': []}), 200),
        ),
        throwsA(_apiError('Invalid users response format', null)),
      );
    });

    test('403 maps to admin access required', () async {
      await expectLater(
        _withClient(
          () => api.fetchUsers(),
          (_) async => http.Response('{"message":"ignored"}', 403),
        ),
        throwsA(_apiError('Admin access required', 403)),
      );
    });

    test('empty error body falls back to default message', () async {
      await expectLater(
        _withClient(
          () => api.fetchUsers(),
          (_) async => http.Response('', 500),
        ),
        throwsA(_apiError('Failed to load users', 500)),
      );
    });

    test('uses message field from JSON error body', () async {
      await expectLater(
        _withClient(
          () => api.fetchUsers(),
          (_) async =>
              http.Response(jsonEncode({'message': 'Bad thing'}), 400),
        ),
        throwsA(_apiError('Bad thing', 400)),
      );
    });

    test('uses error field when message is absent', () async {
      await expectLater(
        _withClient(
          () => api.fetchUsers(),
          (_) async => http.Response(jsonEncode({'error': 'Oops'}), 422),
        ),
        throwsA(_apiError('Oops', 422)),
      );
    });

    test('non-JSON error body falls back to default', () async {
      await expectLater(
        _withClient(
          () => api.fetchUsers(),
          (_) async => http.Response('<html>', 502),
        ),
        throwsA(_apiError('Failed to load users', 502)),
      );
    });

    test('JSON list error body falls back to default', () async {
      await expectLater(
        _withClient(
          () => api.fetchUsers(),
          (_) async => http.Response('[1,2]', 500),
        ),
        throwsA(_apiError('Failed to load users', 500)),
      );
    });

    test('map error body without message/error falls back', () async {
      await expectLater(
        _withClient(
          () => api.fetchUsers(),
          (_) async => http.Response('{"other":1}', 500),
        ),
        throwsA(_apiError('Failed to load users', 500)),
      );
    });
  });

  group('promoteToAdmin', () {
    test('posts ADMIN role and parses the updated user', () async {
      late http.Request seen;
      final user = await _withClient(
        () => api.promoteToAdmin(7),
        (req) async {
          seen = req;
          return http.Response(
            jsonEncode({'id': 7, 'name': 'Cy', 'role': 'ADMIN'}),
            200,
          );
        },
      );
      expect(user.id, 7);
      expect(user.role, 'ADMIN');
      expect(seen.method, 'POST');
      expect(seen.url.path, endsWith('/admin/users/7/role'));
      expect(jsonDecode(seen.body), {'role': 'ADMIN'});
      expect(seen.headers['Content-Type'], startsWith('application/json'));
    });

    test('throws when the 200 body is not an object', () async {
      await expectLater(
        _withClient(
          () => api.promoteToAdmin(7),
          (_) async => http.Response('[]', 200),
        ),
        throwsA(_apiError('Invalid role update response format', null)),
      );
    });

    test('non-200 uses role-update fallback', () async {
      await expectLater(
        _withClient(
          () => api.promoteToAdmin(7),
          (_) async => http.Response('', 404),
        ),
        throwsA(_apiError('Failed to update user role', 404)),
      );
    });

    test('403 maps to admin access required', () async {
      await expectLater(
        _withClient(
          () => api.promoteToAdmin(7),
          (_) async => http.Response('', 403),
        ),
        throwsA(_apiError('Admin access required', 403)),
      );
    });
  });
}
