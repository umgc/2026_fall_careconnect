// Tests for OAuthCallbackPage — processes OAuth redirect parameters.
// The page has a 500ms delay in initState before processing.
// pump(600ms) advances past this delay, triggering state changes.
// _redirectToLogin() schedules a 3-second timer; each error test drains it
// with pump(4s) to prevent "Timer still pending" assertion failures.
// GoRouter is required because _redirectToLogin() calls context.go('/login').

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:care_connect_app/features/auth/presentation/pages/oauth_callback_page.dart';
import 'package:care_connect_app/providers/user_provider.dart';

Widget _wrap(Widget child) {
  // GoRouter is required: _redirectToLogin() calls context.go('/login').
  final provider = UserProvider();
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, __) => child),
      GoRoute(path: '/login', builder: (_, __) => const Scaffold()),
    ],
  );
  return ChangeNotifierProvider<UserProvider>.value(
    value: provider,
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  group('OAuthCallbackPage – processing state', () {
    testWidgets('shows Care Connect brand text initially', (tester) async {
      // The brand name is shown at the top of the page from the start.
      await tester.pumpWidget(
        _wrap(const OAuthCallbackPage()),
      );
      await tester.pump();
      expect(find.text('Care Connect'), findsOneWidget);
      // Drain the 500ms processing delay and the 3s redirect timer to prevent
      // "Timer still pending after widget tree disposed" assertion failures.
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(seconds: 4));
      await tester.pump();
    });

    testWidgets('shows CircularProgressIndicator during processing', (tester) async {
      // Before the 500ms async delay, the page shows a progress indicator.
      await tester.pumpWidget(
        _wrap(const OAuthCallbackPage()),
      );
      await tester.pump(); // one frame: sync part of _processOAuthCallback runs
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // Drain the 500ms processing delay and the 3s redirect timer.
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(seconds: 4));
      await tester.pump();
    });

    testWidgets('shows Processing authentication status text', (tester) async {
      // The status text is updated synchronously before the first await.
      await tester.pumpWidget(
        _wrap(const OAuthCallbackPage()),
      );
      await tester.pump();
      expect(find.text('Processing authentication...'), findsOneWidget);
      // Drain the 500ms processing delay and the 3s redirect timer.
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(seconds: 4));
      await tester.pump();
    });
  });

  group('OAuthCallbackPage – error param (oauth_failed)', () {
    testWidgets('shows oauth_failed error message after delay', (tester) async {
      // After the 500ms delay, the error param triggers the _getErrorMessage switch
      // and renders the human-readable error text.
      await tester.pumpWidget(
        _wrap(const OAuthCallbackPage(error: 'oauth_failed')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(
        find.text('OAuth authentication failed. Please try again.'),
        findsOneWidget,
      );
      // Drain the 3-second redirect timer to prevent "Timer still pending".
      await tester.pump(const Duration(seconds: 4));
      await tester.pump();
    });

    testWidgets('shows error outline icon on error', (tester) async {
      // When _isError is true, an error icon is shown instead of the spinner.
      await tester.pumpWidget(
        _wrap(const OAuthCallbackPage(error: 'oauth_failed')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      await tester.pump();
    });

    testWidgets('shows Back to Login button on error', (tester) async {
      // An ElevatedButton to go back to login is shown when there is an error.
      await tester.pumpWidget(
        _wrap(const OAuthCallbackPage(error: 'oauth_failed')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(find.text('Back to Login'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      await tester.pump();
    });

    testWidgets('access_denied shows Access was denied message', (tester) async {
      // Covers the 'access_denied' case in _getErrorMessage switch.
      await tester.pumpWidget(
        _wrap(const OAuthCallbackPage(error: 'access_denied')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(
        find.text('Access was denied. Please grant permission to continue.'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 4));
      await tester.pump();
    });

    testWidgets('server_error shows Server error message', (tester) async {
      // Covers the 'server_error' case in _getErrorMessage switch.
      await tester.pumpWidget(
        _wrap(const OAuthCallbackPage(error: 'server_error')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(
        find.text('Server error occurred. Please try again later.'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 4));
      await tester.pump();
    });

    testWidgets('unknown error shows Authentication error fallback', (tester) async {
      // Covers the default case in _getErrorMessage for unrecognized error codes.
      await tester.pumpWidget(
        _wrap(const OAuthCallbackPage(error: 'some_unknown_error')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(
        find.text('Authentication error: some_unknown_error'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 4));
      await tester.pump();
    });
  });

  group('OAuthCallbackPage – missing params', () {
    testWidgets('null token and user shows Missing authentication data error',
        (tester) async {
      // When both token and user are null, the missing-params branch fires
      // and sets the appropriate error message.
      await tester.pumpWidget(
        _wrap(const OAuthCallbackPage(token: null, user: null)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(
        find.text('Missing authentication data. Please try signing in again.'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 4));
      await tester.pump();
    });

    testWidgets('missing params also shows Back to Login button', (tester) async {
      // Error state always renders the Back to Login button.
      await tester.pumpWidget(
        _wrap(const OAuthCallbackPage(token: null, user: null)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(find.text('Back to Login'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      await tester.pump();
    });
  });

  group('OAuthCallbackPage – token+user processing', () {
    testWidgets('malformed user data shows processing failure', (tester) async {
      // token + user present, but user is not valid JSON -> jsonDecode throws
      // -> catch block sets the failure status and redirects.
      await tester.pumpWidget(
        _wrap(const OAuthCallbackPage(token: 'jwt-token', user: 'not-json')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600)); // past the 500ms delay
      await tester.pump();

      expect(
        find.textContaining('Failed to process authentication'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 4)); // drain the 3s redirect timer
      await tester.pump();
    });

    testWidgets('Back to Login button navigates away', (tester) async {
      await tester.pumpWidget(
        _wrap(const OAuthCallbackPage(error: 'oauth_failed')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();

      await tester.tap(find.text('Back to Login')); // covers onPressed -> context.go
      await tester.pumpAndSettle();
      expect(find.byType(OAuthCallbackPage), findsNothing);

      await tester.pump(const Duration(seconds: 4)); // drain the pending redirect timer
      await tester.pump();
    });
  });
}
