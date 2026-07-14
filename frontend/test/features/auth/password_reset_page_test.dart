// Tests for PasswordResetPage — handles both password reset (short token/no token)
// and initial password setup (long token with dash, for family members).
// No live server needed for form rendering and local validation tests.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/auth/presentation/pages/password_reset_page.dart';
import 'package:go_router/go_router.dart';

import '../../helpers/fake_http_overrides.dart';

Widget _wrap(Widget child) {
  // GoRouter is needed because the "Back to Login" TextButton uses context.go.
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, __) => child),
      GoRoute(path: '/login', builder: (_, __) => const Scaffold()),
    ],
  );
  return MaterialApp.router(routerConfig: router);
}

void main() {
  group('PasswordResetPage – reset mode (no token)', () {
    testWidgets('shows Reset Your Password title without token', (tester) async {
      // When no token is provided, the page operates in reset mode.
      await tester.pumpWidget(_wrap(const PasswordResetPage()));
      await tester.pump();
      expect(find.text('Reset Your Password'), findsWidgets);
    });

    testWidgets('shows Care Connect brand text', (tester) async {
      // The Care Connect brand name is always shown at the top.
      await tester.pumpWidget(_wrap(const PasswordResetPage()));
      await tester.pump();
      expect(find.text('Care Connect'), findsOneWidget);
    });

    testWidgets('shows Closer Connections tagline', (tester) async {
      // The app tagline is shown below the brand name.
      await tester.pumpWidget(_wrap(const PasswordResetPage()));
      await tester.pump();
      expect(find.text('Closer Connections. Better Care.'), findsOneWidget);
    });

    testWidgets('shows lock icon', (tester) async {
      // A lock icon is displayed as a visual cue for the password flow.
      await tester.pumpWidget(_wrap(const PasswordResetPage()));
      await tester.pump();
      expect(find.byIcon(Icons.lock), findsAtLeastNWidgets(1));
    });

    testWidgets('shows three TextFormFields', (tester) async {
      // Email Address, New Password, and Confirm New Password fields must exist.
      await tester.pumpWidget(_wrap(const PasswordResetPage()));
      await tester.pump();
      expect(find.byType(TextFormField), findsNWidgets(3));
    });

    testWidgets('shows Reset Password button', (tester) async {
      // The primary action button is labeled "Reset Password" in reset mode.
      await tester.pumpWidget(_wrap(const PasswordResetPage()));
      await tester.pump();
      expect(find.text('Reset Password'), findsOneWidget);
    });

    testWidgets('shows Back to Login link', (tester) async {
      // A TextButton link to navigate back to the login page is always visible.
      await tester.pumpWidget(_wrap(const PasswordResetPage()));
      await tester.pump();
      expect(find.text('Back to Login'), findsOneWidget);
    });

    testWidgets('empty email shows Please enter your email', (tester) async {
      // Tapping submit with an empty email field triggers the email validator.
      await tester.pumpWidget(_wrap(const PasswordResetPage()));
      await tester.pump();
      await tester.ensureVisible(find.text('Reset Password'));
      await tester.pump();
      await tester.tap(find.text('Reset Password'));
      await tester.pump();
      expect(find.text('Please enter your email'), findsOneWidget);
    });

    testWidgets('invalid email shows Please enter a valid email address',
        (tester) async {
      // A malformed email address triggers the email format validator.
      await tester.pumpWidget(_wrap(const PasswordResetPage()));
      await tester.pump();
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'bad-email');
      await tester.ensureVisible(find.text('Reset Password'));
      await tester.pump();
      await tester.tap(find.text('Reset Password'));
      await tester.pump();
      expect(find.text('Please enter a valid email address'), findsOneWidget);
    });

    testWidgets('empty password shows Please enter a password', (tester) async {
      // A valid email but empty password triggers the password validator.
      await tester.pumpWidget(_wrap(const PasswordResetPage()));
      await tester.pump();
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'valid@example.com');
      await tester.ensureVisible(find.text('Reset Password'));
      await tester.pump();
      await tester.tap(find.text('Reset Password'));
      await tester.pump();
      expect(find.text('Please enter a password'), findsOneWidget);
    });

    testWidgets('short password shows Password must be at least 6 characters',
        (tester) async {
      // A password under 6 characters triggers the length validator.
      await tester.pumpWidget(_wrap(const PasswordResetPage()));
      await tester.pump();
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'valid@example.com');
      await tester.enterText(fields.at(1), 'abc');
      await tester.ensureVisible(find.text('Reset Password'));
      await tester.pump();
      await tester.tap(find.text('Reset Password'));
      await tester.pump();
      expect(
        find.text('Password must be at least 6 characters'),
        findsOneWidget,
      );
    });

    testWidgets('mismatched passwords show Passwords do not match',
        (tester) async {
      // When the password and confirm password don't match,
      // _setPassword() (not form validator) shows the mismatch error.
      await tester.pumpWidget(_wrap(const PasswordResetPage()));
      await tester.pump();
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'valid@example.com');
      await tester.enterText(fields.at(1), 'password123');
      await tester.enterText(fields.at(2), 'differentPassword');
      await tester.ensureVisible(find.text('Reset Password'));
      await tester.pump();
      await tester.tap(find.text('Reset Password'));
      await tester.pump();
      expect(find.text('Passwords do not match'), findsOneWidget);
    });

    testWidgets('empty confirm shows Please confirm your password',
        (tester) async {
      // A non-empty password but empty confirm field triggers the confirm validator.
      await tester.pumpWidget(_wrap(const PasswordResetPage()));
      await tester.pump();
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'valid@example.com');
      await tester.enterText(fields.at(1), 'validPassword');
      await tester.ensureVisible(find.text('Reset Password'));
      await tester.pump();
      await tester.tap(find.text('Reset Password'));
      await tester.pump();
      expect(find.text('Please confirm your password'), findsOneWidget);
    });
  });

  group('PasswordResetPage – setup mode (long token with dash)', () {
    const setupToken = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890';

    testWidgets('shows Set Your Password title with setup token', (tester) async {
      // A token longer than 20 chars containing a dash enables setup mode.
      await tester.pumpWidget(_wrap(const PasswordResetPage(token: setupToken)));
      await tester.pump();
      expect(find.text('Set Your Password'), findsWidgets);
    });

    testWidgets('shows Set Password button in setup mode', (tester) async {
      // The button label changes to "Set Password" in setup mode.
      await tester.pumpWidget(_wrap(const PasswordResetPage(token: setupToken)));
      await tester.pump();
      expect(find.text('Set Password'), findsOneWidget);
    });

    testWidgets('shows Welcome description in setup mode', (tester) async {
      // A welcome message is displayed in setup mode.
      await tester.pumpWidget(_wrap(const PasswordResetPage(token: setupToken)));
      await tester.pump();
      expect(
        find.text('Welcome! Please set your password to access your account.'),
        findsOneWidget,
      );
    });
  });

  group('PasswordResetPage – submit network paths', () {
    Future<void> fillValidForm(WidgetTester tester) async {
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'user@test.com');
      await tester.enterText(fields.at(1), 'password123');
      await tester.enterText(fields.at(2), 'password123');
      await tester.pump();
    }

    Future<void> submit(WidgetTester tester) async {
      await tester.ensureVisible(find.text('Reset Password'));
      await tester.tap(find.text('Reset Password'));
      await tester.pump(); // start the async request
      await tester.pump(const Duration(seconds: 1)); // let it resolve
    }

    testWidgets('successful reset shows the backend message', (tester) async {
      HttpOverrides.global = FakeHttpOverrides(
        (method, uri) => FakeResponse(200, '{"message":"Password updated"}'),
      );
      addTearDown(() => HttpOverrides.global = null);

      await tester.pumpWidget(_wrap(const PasswordResetPage()));
      await tester.pump();
      await fillValidForm(tester);
      await submit(tester);

      expect(find.text('Password updated'), findsOneWidget);

      // _setPassword schedules a delayed redirect to /login; advance past it so
      // no Timer is left pending when the test ends.
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('backend failure shows "Failed to set password"',
        (tester) async {
      HttpOverrides.global = FakeHttpOverrides(
        (method, uri) => FakeResponse(400, '{"error":"Bad token"}'),
      );
      addTearDown(() => HttpOverrides.global = null);

      await tester.pumpWidget(_wrap(const PasswordResetPage()));
      await tester.pump();
      await fillValidForm(tester);
      await submit(tester);

      expect(find.textContaining('Failed to set password'), findsOneWidget);
    });
  });
}
