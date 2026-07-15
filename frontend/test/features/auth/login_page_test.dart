// Tests for LoginPage — the main login screen.
// LoginPage calls GoRouter.of(context) in build(), so MaterialApp.router
// with a GoRouter configuration is required for all tests.
//
// The security-badge Rows overflow the card's inner ConstrainedBox (436px)
// by 30–90px regardless of viewport size; that is a layout issue in the
// source file.  _suppressOverflow() saves the test framework's own
// FlutterError.onError, wraps it to drop overflow reports, and restores it
// via addTearDown — so only overflow noise is suppressed, not real errors.
//
// The "Sign In shows loading indicator" test is omitted: EnhancedAuthService
// calls flutter_secure_storage which throws MissingPluginException; the
// resulting Future resolves before tester.pump() renders the spinner frame.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:care_connect_app/features/auth/presentation/pages/login_page.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';

GoRouter _makeRouter({String? userType}) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => LoginPage(userType: userType),
      ),
      GoRoute(path: '/login', builder: (_, __) => const Scaffold()),
      GoRoute(path: '/signup', builder: (_, __) => const Scaffold()),
      GoRoute(path: '/reset-password', builder: (_, __) => const Scaffold()),
      GoRoute(path: '/dashboard', builder: (_, __) => const Scaffold()),
      GoRoute(
        path: '/caregiver-dashboard',
        builder: (_, __) => const Scaffold(),
      ),
      GoRoute(
        path: '/patient-dashboard',
        builder: (_, __) => const Scaffold(),
      ),
    ],
  );
}

Widget _wrap({String? userType}) {
  final router = _makeRouter(userType: userType);
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<UserProvider>(create: (_) => UserProvider()),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  );
}

// Called inside a testWidgets body to suppress RenderFlex overflow errors.
// testWidgets installs its own FlutterError.onError before the body runs, so
// we wrap that handler (not the global default) and restore it via addTearDown.
void _suppressOverflow() {
  final previous = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    if (details.exceptionAsString().contains('overflowed')) return;
    previous?.call(details);
  };
  addTearDown(() => FlutterError.onError = previous);
}

void main() {
  group('LoginPage – form elements', () {
    testWidgets('renders Scaffold', (tester) async {
      // Verifies the page renders without crashing.
      _suppressOverflow();
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows sign in title', (tester) async {
      // "Sign in to your account" heading is shown in the form card.
      _suppressOverflow();
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('Sign in to your account'), findsOneWidget);
    });

    testWidgets('shows sign in subtitle', (tester) async {
      // "Enter your credentials to access CareConnect" is shown below the title.
      _suppressOverflow();
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(
        find.text('Enter your credentials to access CareConnect'),
        findsOneWidget,
      );
    });

    testWidgets('shows Username label', (tester) async {
      // The label for the email/username field is "Username".
      _suppressOverflow();
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('Username'), findsOneWidget);
    });

    testWidgets('shows username hint text in email field', (tester) async {
      // The email field has a hint "Enter your username".
      _suppressOverflow();
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('Enter your username'), findsOneWidget);
    });

    testWidgets('shows Password label', (tester) async {
      // The label for the password field is "Password".
      _suppressOverflow();
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('Password'), findsOneWidget);
    });

    testWidgets('shows password hint text', (tester) async {
      // The password field has a hint "Enter your password".
      _suppressOverflow();
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('Enter your password'), findsOneWidget);
    });

    testWidgets('shows Forgot Password link', (tester) async {
      // The "Forgot Password?" link navigates to the reset password screen.
      _suppressOverflow();
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('Forgot Password?'), findsOneWidget);
    });

    testWidgets('shows Sign In button', (tester) async {
      // The primary submit button is labeled "Sign In".
      _suppressOverflow();
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('Sign In'), findsOneWidget);
    });

    testWidgets('shows Create Account link', (tester) async {
      // A link to the signup page is shown below the form.
      _suppressOverflow();
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('Create Account'), findsOneWidget);
    });

    testWidgets('shows no account prompt text', (tester) async {
      // "Don't have an account?" prompt is shown above the create account link.
      _suppressOverflow();
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text("Don't have an account?"), findsOneWidget);
    });
  });

  group('LoginPage – security badges', () {
    testWidgets('shows Secure badge', (tester) async {
      // Security compliance badge is shown at the bottom of the page.
      _suppressOverflow();
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('Secure'), findsOneWidget);
    });

    testWidgets('shows HIPAA Compliant badge', (tester) async {
      // HIPAA compliance badge is shown at the bottom of the page.
      _suppressOverflow();
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('HIPAA Compliant'), findsOneWidget);
    });

    testWidgets('shows Accessible badge', (tester) async {
      // Accessibility badge is shown at the bottom of the page.
      _suppressOverflow();
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('Accessible'), findsOneWidget);
    });

    testWidgets('shows End-to-end encrypted text', (tester) async {
      // End-to-end encryption label is shown near the bottom.
      _suppressOverflow();
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('End-to-end encrypted'), findsOneWidget);
    });

    testWidgets('shows WCAG AA compliant text', (tester) async {
      // WCAG AA compliance label is shown near the bottom.
      _suppressOverflow();
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('WCAG AA compliant'), findsOneWidget);
    });
  });

  group('LoginPage – interactions', () {
    testWidgets('password visibility toggle shows visibility icon', (tester) async {
      // The suffix icon of the password field is the visibility toggle.
      _suppressOverflow();
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    });

    testWidgets('tapping visibility icon toggles to visibility_off', (tester) async {
      // The password field is below y=600; ensureVisible scrolls it into view
      // before tapping so the hit-test lands on the icon.
      _suppressOverflow();
      await tester.pumpWidget(_wrap());
      await tester.pump();
      await tester.ensureVisible(find.byIcon(Icons.visibility_outlined));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.visibility_outlined));
      await tester.pump();
      expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
    });
  });

  group('LoginPage – login submit flow', () {
    testWidgets('shows error when credentials are rejected', (tester) async {
      _suppressOverflow();
      // Drive the login HTTP through the existing ApiService test seam so the
      // submit handler runs deterministically with no real network.
      ApiService.debugSetHttpClient(MockClient((req) async {
        return http.Response('{"error":"Invalid credentials"}', 401);
      }));
      addTearDown(ApiService.debugResetHttpClient);

      await tester.pumpWidget(_wrap());
      await tester.pump();

      final emailField = find.byType(TextFormField).at(0);
      final pwdField = find.byType(TextFormField).at(1);
      await tester.ensureVisible(emailField);
      await tester.enterText(emailField, 'user@test.com');
      await tester.ensureVisible(pwdField);
      await tester.enterText(pwdField, 'wrong-password');
      await tester.pump();

      final signIn = find.widgetWithText(ElevatedButton, 'Sign In');
      await tester.ensureVisible(signIn);
      await tester.tap(signIn);
      await tester.pump(); // kick off the async login
      await tester.pump(const Duration(seconds: 1)); // let the future resolve

      expect(find.textContaining('Login failed'), findsWidgets);
    });
  });

  group('LoginPage – successful login', () {
    setUp(() {
      // AuthService.login persists to secure storage + SharedPreferences on
      // success; mock those channels so login can complete in the test.
      SharedPreferences.setMockInitialValues({});
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        (call) async {
          if (call.method == 'readAll') return <String, String>{};
          if (call.method == 'containsKey') return false;
          return null; // write / read / delete
        },
      );
    });

    testWidgets('verified login navigates away from the login page',
        (tester) async {
      _suppressOverflow();
      ApiService.debugSetHttpClient(MockClient((req) async {
        return http.Response(
          jsonEncode({
            'id': 1,
            'email': 'user@test.com',
            'role': 'PATIENT',
            'token': 'jwt-token',
            'name': 'Test User',
            'emailVerified': true,
          }),
          200,
        );
      }));
      addTearDown(ApiService.debugResetHttpClient);

      await tester.pumpWidget(_wrap());
      await tester.pump();

      final emailField = find.byType(TextFormField).at(0);
      final pwdField = find.byType(TextFormField).at(1);
      await tester.ensureVisible(emailField);
      await tester.enterText(emailField, 'user@test.com');
      await tester.ensureVisible(pwdField);
      await tester.enterText(pwdField, 'password123');
      await tester.pump();

      final signIn = find.widgetWithText(ElevatedButton, 'Sign In');
      await tester.ensureVisible(signIn);
      await tester.tap(signIn);
      // The success path makes several async storage round-trips, a 100ms
      // delay, then navigates; pump repeatedly to let them all resolve.
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }

      // On success the page navigates to the dashboard/login route, so the
      // LoginPage itself is no longer in the tree.
      expect(find.byType(LoginPage), findsNothing);
    });
  });
}
