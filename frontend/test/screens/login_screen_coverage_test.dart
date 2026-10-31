// Coverage tests for LoginScreen (lib/screens/login_screen.dart): the login
// handler with a mocked API (rejected credentials, an accepted login whose
// role cannot be routed, a missing AuthService provider) and the inline
// error banner.

import 'dart:convert';

import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/screens/login_screen.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:care_connect_app/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

Widget _app({bool withAuth = true}) {
  final app = MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const LoginScreen(),
  );
  return withAuth
      ? Provider<AuthService>.value(value: AuthService.instance, child: app)
      : app;
}

Future<void> _login(WidgetTester tester) async {
  await tester.enterText(find.byType(TextFormField).at(0), 'caregiver');
  await tester.enterText(find.byType(TextFormField).at(1), 'password123');
  await tester.tap(find.text('Login'));
  await tester.pumpAndSettle();
}

void main() {
  late List<http.Request> requests;

  void mockApi(int status, Object body) {
    requests = [];
    ApiService.debugSetHttpClient(MockClient((r) async {
      requests.add(r);
      return http.Response(jsonEncode(body), status);
    }));
  }

  tearDown(ApiService.debugResetHttpClient);

  testWidgets('rejected credentials show the server error', (tester) async {
    mockApi(401, {'error': 'Invalid credentials'});
    await tester.pumpWidget(_app());
    await _login(tester);

    expect(requests, hasLength(1));
    expect(jsonDecode(requests.single.body)['email'], 'caregiver');
    expect(find.text('Login failed: Exception: Invalid credentials'),
        findsOneWidget);
    expect(find.byIcon(Icons.error), findsOneWidget);
    expect(find.text('Login'), findsOneWidget);
  });

  testWidgets('an unverified login surfaces a routing error', (tester) async {
    mockApi(200, {
      'id': 7,
      'email': 'caregiver',
      'role': 'CAREGIVER',
      'token': 'jwt',
      'emailVerified': false,
    });
    await tester.pumpWidget(_app());
    await _login(tester);

    expect(find.textContaining('Login failed:'), findsOneWidget);
  });

  testWidgets('without an AuthService provider login fails gracefully',
      (tester) async {
    mockApi(200, {});
    await tester.pumpWidget(_app(withAuth: false));
    await _login(tester);

    expect(requests, isEmpty);
    expect(find.textContaining('Login failed:'), findsOneWidget);
  });

  testWidgets('submitting the password field triggers login',
      (tester) async {
    mockApi(401, {'error': 'Nope'});
    await tester.pumpWidget(_app());
    await tester.enterText(find.byType(TextFormField).at(0), 'patient');
    await tester.enterText(find.byType(TextFormField).at(1), 'pw');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.text('Login failed: Exception: Nope'), findsOneWidget);
  });
}
