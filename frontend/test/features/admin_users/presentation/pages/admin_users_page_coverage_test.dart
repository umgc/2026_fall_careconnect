// Coverage tests for AdminUsersPage
// (lib/features/admin_users/presentation/pages/admin_users_page.dart):
// load errors (API error with Retry, malformed body), the empty list, the
// refresh action, cancelling the promote dialog and failed promotions.

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

const _secureStorage =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

final _users = [
  {
    'id': 2,
    'name': '',
    'email': 'jane@example.com',
    'role': 'CAREGIVER',
    'emailVerified': true,
  },
];

Widget _wrap() {
  final provider = UserProvider()
    ..setUser(UserSession(
      id: 1,
      email: 'admin@test.com',
      role: 'ADMIN',
      token: 'mock_token',
      name: 'Test Admin',
    ));
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

Future<void> _run(WidgetTester tester,
    Future<http.Response> Function(http.Request) handler,
    [Future<void> Function()? then]) async {
  await http.runWithClient(() async {
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();
    if (then != null) await then();
  }, () => MockClient(handler));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorage, (call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorage, null);
  });

  testWidgets('a forbidden load shows the error and Retry', (tester) async {
    var calls = 0;
    await _run(tester, (r) async {
      calls++;
      return http.Response('{"error":"nope"}', 403);
    }, () async {
      expect(find.text('Admin access required'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
    });
    expect(calls, 2);
  });

  testWidgets('a malformed body shows the generic load error',
      (tester) async {
    await _run(tester, (r) async => http.Response('not json', 200));
    expect(find.text('Failed to load users'), findsOneWidget);
  });

  testWidgets('an empty list shows the placeholder and can refresh',
      (tester) async {
    var calls = 0;
    await _run(tester, (r) async {
      calls++;
      return http.Response('[]', 200);
    }, () async {
      expect(find.text('No users found'), findsOneWidget);
      await tester.tap(find.byTooltip('Refresh'));
      await tester.pumpAndSettle();
    });
    expect(calls, 2);
  });

  testWidgets('cancelling the promote dialog changes nothing',
      (tester) async {
    final methods = <String>[];
    await _run(tester, (r) async {
      methods.add(r.method);
      return http.Response(jsonEncode(_users), 200);
    }, () async {
      await tester.tap(find.text('Promote to Admin'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Grant admin access to jane@example.com'),
          findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
    expect(methods, ['GET']);
  });

  testWidgets('a rejected promotion shows the API message', (tester) async {
    await _run(tester, (r) async {
      if (r.method == 'POST') return http.Response('{}', 403);
      return http.Response(jsonEncode(_users), 200);
    }, () async {
      await tester.tap(find.text('Promote to Admin'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Promote'));
      await tester.pumpAndSettle();
    });
    expect(find.text('Admin access required'), findsOneWidget);
  });

  testWidgets('a malformed promotion response shows a generic failure',
      (tester) async {
    await _run(tester, (r) async {
      if (r.method == 'POST') return http.Response('garbage', 200);
      return http.Response(jsonEncode(_users), 200);
    }, () async {
      await tester.tap(find.text('Promote to Admin'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Promote'));
      await tester.pumpAndSettle();
    });
    expect(find.text('Failed to promote user'), findsOneWidget);
  });
}
