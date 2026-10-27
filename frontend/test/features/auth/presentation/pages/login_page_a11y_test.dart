// Accessibility tests for LoginPage's sign-in errors (VPAT final-build pass):
// a blank form says what's missing without calling the server (WCAG 3.3.1),
// a rejected sign-in says how to fix it (3.3.3), and the error sits in a live
// region so screen readers announce it (4.1.3).
import 'dart:ui' show SemanticsFlag;

import 'package:care_connect_app/features/auth/presentation/pages/login_page.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

const _missing = 'Please enter your email and password.';
const _invalid =
    'The username or password is incorrect. Check them and try again.';

Widget _wrap() {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, __) => const LoginPage()),
      GoRoute(path: '/dashboard', builder: (_, __) => const Scaffold()),
    ],
  );
  return ChangeNotifierProvider<UserProvider>(
    create: (_) => UserProvider(),
    child: MaterialApp.router(
      routerConfig: router,
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  );
}

// The security badges overflow the card in tests (a layout issue in the
// page); drop only those reports, as login_page_test.dart does.
void _suppressOverflow() {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exceptionAsString().contains('overflowed')) return;
    previous?.call(details);
  };
  addTearDown(() => FlutterError.onError = previous);
}

Future<void> _submit(WidgetTester tester,
    {String email = '', String password = ''}) async {
  final emailField = find.byType(TextFormField).at(0);
  final pwdField = find.byType(TextFormField).at(1);
  await tester.ensureVisible(emailField);
  await tester.enterText(emailField, email);
  await tester.ensureVisible(pwdField);
  await tester.enterText(pwdField, password);
  final signIn = find.widgetWithText(ElevatedButton, 'Sign In');
  await tester.ensureVisible(signIn);
  await tester.tap(signIn);
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets('a blank form says what is missing without calling the server',
      (tester) async {
    _suppressOverflow();
    var requests = 0;
    ApiService.debugSetHttpClient(MockClient((_) async {
      requests++;
      return http.Response('{}', 200);
    }));
    addTearDown(ApiService.debugResetHttpClient);

    await tester.pumpWidget(_wrap());
    await tester.pump();
    await _submit(tester);

    expect(find.text(_missing), findsOneWidget);
    expect(requests, 0);
  });

  testWidgets('a password alone still asks for both fields', (tester) async {
    _suppressOverflow();
    await tester.pumpWidget(_wrap());
    await tester.pump();
    await _submit(tester, password: 'secret');

    expect(find.text(_missing), findsOneWidget);
  });

  testWidgets(
      'a rejected sign-in says how to fix it, without an "Exception:" prefix',
      (tester) async {
    _suppressOverflow();
    ApiService.debugSetHttpClient(MockClient(
        (_) async => http.Response('{"error":"Invalid credentials"}', 401)));
    addTearDown(ApiService.debugResetHttpClient);

    await tester.pumpWidget(_wrap());
    await tester.pump();
    await _submit(tester, email: 'user@test.com', password: 'wrong');

    expect(find.text(_invalid), findsOneWidget);
    expect(find.textContaining('Exception:'), findsNothing);
  });

  testWidgets('the error is in a live region so screen readers announce it',
      (tester) async {
    _suppressOverflow();
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_wrap());
    await tester.pump();
    await _submit(tester);

    final node = tester.getSemantics(find.text(_missing));
    var current = node;
    var live = false;
    while (true) {
      if (current.hasFlag(SemanticsFlag.isLiveRegion)) {
        live = true;
        break;
      }
      final parent = current.parent;
      if (parent == null) break;
      current = parent;
    }
    expect(live, isTrue, reason: 'the error should be in a live region');
    handle.dispose();
  });
}
