import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/features/admin_users/presentation/pages/admin_users_page.dart';
import 'package:care_connect_app/providers/user_provider.dart';

void _setupMocks() {
  SharedPreferences.setMockInitialValues({});
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    (call) async {
      if (call.method == 'readAll') {
        return <String, String>{'jwt_token': 'mock_token'};
      }
      if (call.method == 'read') return 'mock_token';
      if (call.method == 'containsKey') return true;
      return null;
    },
  );
}

Widget _wrap({required MockClient client}) {
  final provider = UserProvider();
  provider.setUser(
    UserSession(
      id: 1,
      email: 'admin@test.com',
      role: 'ADMIN',
      token: 'mock_token',
      name: 'Test Admin',
    ),
  );
  provider.userSession = provider.user;

  return MaterialApp(
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en')],
    home: ChangeNotifierProvider<UserProvider>.value(
      value: provider,
      child: const AdminUsersPage(),
    ),
  );
}

List<Map<String, dynamic>> _sampleUsers() {
  return [
    {
      'id': 1,
      'name': 'Admin User',
      'email': 'admin@test.com',
      'role': 'ADMIN',
      'emailVerified': true,
    },
    {
      'id': 2,
      'name': 'Jane Doe',
      'email': 'jane@example.com',
      'role': 'CAREGIVER',
      'emailVerified': true,
    },
  ];
}

void main() {
  setUp(_setupMocks);

  testWidgets('renders user list without promote button for admins', (tester) async {
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/admin/users') &&
          request.method == 'GET') {
        return http.Response(json.encode(_sampleUsers()), 200);
      }
      return http.Response('Not found', 404);
    });

    await http.runWithClient(() async {
      await tester.pumpWidget(_wrap(client: client));
      await tester.pumpAndSettle();

      expect(find.text('User Management'), findsOneWidget);
      expect(find.text('Jane Doe'), findsOneWidget);
      expect(find.text('Promote to Admin'), findsOneWidget);
      expect(find.text('Admin User'), findsOneWidget);
    }, () => client);
  });

  testWidgets('promote button opens confirmation dialog', (tester) async {
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/admin/users') &&
          request.method == 'GET') {
        return http.Response(json.encode(_sampleUsers()), 200);
      }
      return http.Response('Not found', 404);
    });

    await http.runWithClient(() async {
      await tester.pumpWidget(_wrap(client: client));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Promote to Admin'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Grant admin access to Jane Doe'), findsOneWidget);
      expect(find.text('Promote'), findsOneWidget);
    }, () => client);
  });

  testWidgets('confirming promote calls role endpoint and refreshes list',
      (tester) async {
    var promoteCalled = false;

    final client = MockClient((request) async {
      if (request.url.path.endsWith('/admin/users') &&
          request.method == 'GET') {
        final users = _sampleUsers();
        if (promoteCalled) {
          users[1]['role'] = 'ADMIN';
        }
        return http.Response(json.encode(users), 200);
      }
      if (request.url.path.endsWith('/role') && request.method == 'POST') {
        promoteCalled = true;
        return http.Response(
          json.encode({
            'id': 2,
            'name': 'Jane Doe',
            'email': 'jane@example.com',
            'role': 'ADMIN',
            'emailVerified': true,
          }),
          200,
        );
      }
      return http.Response('Not found', 404);
    });

    await http.runWithClient(() async {
      await tester.pumpWidget(_wrap(client: client));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Promote to Admin'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Promote'));
      await tester.pumpAndSettle();

      expect(promoteCalled, isTrue);
      expect(find.text('Jane Doe is now an admin'), findsOneWidget);
      expect(find.text('Promote to Admin'), findsNothing);
    }, () => client);
  });
}
