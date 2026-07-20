// Tests for PasswordResetConfirmScreen
// (lib/features/auth/presentation/pages/password_reset_confirm_screen.dart).
//
// StatefulWidget — the API call (AuthService.resetPassword) is only triggered
// after all validations pass.  Validation is client-side setState only, so
// these tests never touch the network.
//
// context.go('/login') is called only on API success, so a plain MaterialApp
// (without GoRouter) is fine for the validation-only tests below.
//
// TextFormFields are found by index: 0 = New Password, 1 = Confirm New Password.
// The submit ElevatedButton is found by type (only one on the page).

import 'package:flutter/material.dart';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:care_connect_app/features/auth/presentation/pages/password_reset_confirm_screen.dart';

import '../../helpers/fake_http_overrides.dart';

Widget _wrap() => MaterialApp(
      home: const PasswordResetConfirmScreen(
        token: 'test-token-123',
        email: 'user@example.com',
      ),
    );

// Router-backed wrap for the success path, which calls context.go('/login').
Widget _wrapRouter() {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const PasswordResetConfirmScreen(
          token: 'test-token-123',
          email: 'user@example.com',
        ),
      ),
      GoRoute(path: '/login', builder: (_, __) => const Scaffold()),
    ],
  );
  return MaterialApp.router(routerConfig: router);
}

// Helpers to find the two password fields by index.
Finder get _newPasswordField => find.byType(TextFormField).at(0);
Finder get _confirmPasswordField => find.byType(TextFormField).at(1);
Finder get _submitButton => find.byType(ElevatedButton);

void main() {
  group('PasswordResetConfirmScreen – initial render', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(PasswordResetConfirmScreen), findsOneWidget);
    });

    testWidgets('shows "Reset Password" in the AppBar', (tester) async {
      await tester.pumpWidget(_wrap());
      // AppBar title is "Reset Password".
      expect(find.text('Reset Password'), findsWidgets);
    });

    testWidgets('shows "Set New Password" heading', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Set New Password'), findsOneWidget);
    });

    testWidgets('shows two TextFormFields', (tester) async {
      // One for new password, one for confirm.
      await tester.pumpWidget(_wrap());
      expect(find.byType(TextFormField), findsNWidgets(2));
    });

    testWidgets('shows "Care Connect" brand text', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Care Connect'), findsOneWidget);
    });

    testWidgets('shows submit ElevatedButton', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(_submitButton, findsOneWidget);
    });

    testWidgets('does NOT show error icon on initial render', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byIcon(Icons.error_outline), findsNothing);
    });
  });

  group('PasswordResetConfirmScreen – validation (client-side, no network)', () {
    testWidgets('shows error when password field is empty', (tester) async {
      // Tapping submit without entering text triggers the empty-password error.
      await tester.pumpWidget(_wrap());
      await tester.tap(_submitButton);
      await tester.pump();
      expect(find.text('Please enter a new password'), findsOneWidget);
    });

    testWidgets('shows error when passwords do not match', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.enterText(_newPasswordField, 'password123');
      await tester.enterText(_confirmPasswordField, 'different456');
      await tester.tap(_submitButton);
      await tester.pump();
      expect(find.text('Passwords do not match'), findsOneWidget);
    });

    testWidgets('shows error when password is fewer than 6 characters',
        (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.enterText(_newPasswordField, 'abc');
      await tester.enterText(_confirmPasswordField, 'abc');
      await tester.tap(_submitButton);
      await tester.pump();
      expect(
        find.text('Password must be at least 6 characters'),
        findsOneWidget,
      );
    });

    testWidgets('shows error icon when validation fails', (tester) async {
      // error_outline icon appears inside the error container.
      await tester.pumpWidget(_wrap());
      await tester.tap(_submitButton);
      await tester.pump();
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('error message is replaced when a new validation fails',
        (tester) async {
      await tester.pumpWidget(_wrap());

      // First: trigger empty-password error.
      await tester.tap(_submitButton);
      await tester.pump();
      expect(find.text('Please enter a new password'), findsOneWidget);

      // Now supply mismatched passwords — a different error should replace it.
      await tester.enterText(_newPasswordField, 'hello123');
      await tester.enterText(_confirmPasswordField, 'world456');
      await tester.tap(_submitButton);
      await tester.pump();
      expect(find.text('Passwords do not match'), findsOneWidget);
      expect(find.text('Please enter a new password'), findsNothing);
    });

    testWidgets('whitespace-only password triggers empty error', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.enterText(_newPasswordField, '   ');
      await tester.enterText(_confirmPasswordField, '   ');
      await tester.tap(_submitButton);
      await tester.pump();
      expect(find.text('Please enter a new password'), findsOneWidget);
    });

    testWidgets('exactly 6 char password with match does not show short error',
        (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.enterText(_newPasswordField, 'abcdef');
      await tester.enterText(_confirmPasswordField, 'abcdef');
      await tester.tap(_submitButton);
      await tester.pump();
      // Should NOT show the "at least 6 characters" error
      expect(find.text('Password must be at least 6 characters'), findsNothing);
      // Should NOT show the "do not match" error
      expect(find.text('Passwords do not match'), findsNothing);
      // Should NOT show the empty password error
      expect(find.text('Please enter a new password'), findsNothing);
    });
  });

  group('PasswordResetConfirmScreen – layout & labels', () {
    testWidgets('shows "Closer Connections. Better Care." subtitle',
        (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Closer Connections. Better Care.'), findsOneWidget);
    });

    testWidgets('button text is "Reset Password"', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(
        find.descendant(
          of: find.byType(ElevatedButton),
          matching: find.text('Reset Password'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('password fields are obscured', (tester) async {
      await tester.pumpWidget(_wrap());
      // TextFormField wraps a TextField; check obscureText on the inner TextField
      final textFields = tester.widgetList<TextField>(find.byType(TextField));
      for (final tf in textFields) {
        expect(tf.obscureText, isTrue);
      }
    });

    testWidgets('page is scrollable via SingleChildScrollView', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });

    testWidgets('has a Container with max width constraint', (tester) async {
      await tester.pumpWidget(_wrap());
      final containers = tester.widgetList<Container>(find.byType(Container));
      final constrained = containers.where(
        (c) => c.constraints?.maxWidth == 500,
      );
      expect(constrained, isNotEmpty);
    });

    testWidgets('shows Scaffold with AppBar', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
    });
  });

  group('PasswordResetConfirmScreen – submit network paths', () {
    Future<void> fillAndSubmit(WidgetTester tester) async {
      await tester.enterText(find.byType(TextFormField).at(0), 'password123');
      await tester.enterText(find.byType(TextFormField).at(1), 'password123');
      await tester.pump();
      final btn = find.byType(ElevatedButton);
      await tester.ensureVisible(btn);
      await tester.tap(btn);
      await tester.pump(); // start the async request
      await tester.pump(const Duration(seconds: 1)); // let it resolve
    }

    testWidgets('successful reset shows the backend message', (tester) async {
      HttpOverrides.global = FakeHttpOverrides(
        (method, uri) => FakeResponse(200, '{"message":"All set"}'),
      );
      addTearDown(() => HttpOverrides.global = null);

      await tester.pumpWidget(_wrapRouter());
      await tester.pump();
      await fillAndSubmit(tester);

      expect(find.text('All set'), findsOneWidget);
      // Advance past the delayed redirect so no Timer is left pending.
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('backend failure shows "Failed to reset password"',
        (tester) async {
      HttpOverrides.global = FakeHttpOverrides(
        (method, uri) => FakeResponse(400, '{"error":"nope"}'),
      );
      addTearDown(() => HttpOverrides.global = null);

      await tester.pumpWidget(_wrapRouter());
      await tester.pump();
      await fillAndSubmit(tester);

      expect(find.textContaining('Failed to reset password'), findsOneWidget);
    });
  });
}
