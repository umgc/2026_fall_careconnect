// Tests for ResetPasswordScreen — the "enter email to receive reset link" screen.
// No network is needed for form-rendering and validation tests.
// tester.runAsync is used for the submit path to allow real HTTP to fail fast.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/auth/presentation/pages/reset_password_screen.dart';

import '../../helpers/fake_http_overrides.dart';

Widget _wrap(Widget child) => MaterialApp(home: child);

void main() {
  group('ResetPasswordScreen', () {
    testWidgets('renders Scaffold with AppBar Reset Password', (tester) async {
      // Verifies the screen renders with the correct AppBar title
      await tester.pumpWidget(_wrap(const ResetPasswordScreen()));
      await tester.pump();
      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.text('Reset Password'), findsWidgets);
    });

    testWidgets('shows Care Connect brand text', (tester) async {
      // Verifies branding text is visible on the screen
      await tester.pumpWidget(_wrap(const ResetPasswordScreen()));
      await tester.pump();
      expect(find.text('Care Connect'), findsOneWidget);
    });

    testWidgets('shows Closer Connections tagline', (tester) async {
      // Verifies the tagline is shown below the brand name
      await tester.pumpWidget(_wrap(const ResetPasswordScreen()));
      await tester.pump();
      expect(find.text('Closer Connections. Better Care.'), findsOneWidget);
    });

    testWidgets('shows instruction text', (tester) async {
      // Verifies the instruction text for the user is shown
      await tester.pumpWidget(_wrap(const ResetPasswordScreen()));
      await tester.pump();
      expect(
        find.text('Enter your email to receive a password reset link'),
        findsOneWidget,
      );
    });

    testWidgets('shows email icon', (tester) async {
      // Verifies the email icon is present
      await tester.pumpWidget(_wrap(const ResetPasswordScreen()));
      await tester.pump();
      expect(find.byIcon(Icons.email), findsOneWidget);
    });

    testWidgets('shows email TextFormField', (tester) async {
      // Verifies the email input field is present
      await tester.pumpWidget(_wrap(const ResetPasswordScreen()));
      await tester.pump();
      expect(find.byType(TextFormField), findsOneWidget);
    });

    testWidgets('shows Send Reset Link button', (tester) async {
      // Verifies the submit button is present
      await tester.pumpWidget(_wrap(const ResetPasswordScreen()));
      await tester.pump();
      expect(find.text('Send Reset Link'), findsOneWidget);
    });

    testWidgets('empty email shows Please enter your email validation error',
        (tester) async {
      // Verifies the form validator rejects an empty email field
      await tester.pumpWidget(_wrap(const ResetPasswordScreen()));
      await tester.pump();
      await tester.tap(find.text('Send Reset Link'));
      await tester.pump();
      expect(find.text('Please enter your email'), findsOneWidget);
    });

    testWidgets('invalid email shows Please enter a valid email address',
        (tester) async {
      // Verifies the form validator rejects a malformed email address
      await tester.pumpWidget(_wrap(const ResetPasswordScreen()));
      await tester.pump();
      await tester.enterText(find.byType(TextFormField), 'notanemail');
      await tester.tap(find.text('Send Reset Link'));
      await tester.pump();
      expect(find.text('Please enter a valid email address'), findsOneWidget);
    });

    testWidgets('valid email submit shows status container with error icon',
        (tester) async {
      // When a valid email is submitted, the real HTTP call fails (no server in test).
      // The catch block sets _status and _isError = true, showing the error icon.
      await tester.pumpWidget(_wrap(const ResetPasswordScreen()));
      await tester.pump();
      await tester.enterText(
          find.byType(TextFormField), 'valid@example.com');
      await tester.runAsync(() async {
        await tester.tap(find.text('Send Reset Link'));
        await Future.delayed(const Duration(milliseconds: 500));
      });
      await tester.pumpAndSettle();
      // After API failure, the status container is shown with an error icon
      expect(find.byIcon(Icons.error), findsAtLeastNWidgets(1));
    });

    testWidgets('form submits without crashing when email entered',
        (tester) async {
      // Enter a valid email and tap submit — should not throw.
      await tester.pumpWidget(_wrap(const ResetPasswordScreen()));
      await tester.pump();
      await tester.enterText(
          find.byType(TextFormField), 'valid@example.com');
      await tester.tap(find.text('Send Reset Link'));
      await tester.pump(const Duration(seconds: 2));
      // The screen should still be rendered after submission.
      expect(find.byType(ResetPasswordScreen), findsOneWidget);
    });

    testWidgets('successful request shows the backend success message',
        (tester) async {
      HttpOverrides.global = FakeHttpOverrides(
        (method, uri) => FakeResponse(200, '{"message":"Reset link sent"}'),
      );
      addTearDown(() => HttpOverrides.global = null);

      await tester.pumpWidget(_wrap(const ResetPasswordScreen()));
      await tester.pump();
      await tester.enterText(
          find.byType(TextFormField), 'valid@example.com');
      await tester.tap(find.text('Send Reset Link'));
      await tester.pump(); // start the async request
      await tester.pump(const Duration(seconds: 1)); // let it resolve

      expect(find.text('Reset link sent'), findsOneWidget);
    });
  });
}
