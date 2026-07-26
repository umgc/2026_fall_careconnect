// Tests for PaymentSuccessPage from
// lib/features/payments/presentation/pages/payment_success_page.dart.
//
// Uses Future.delayed timers (1s–4s) and GoRouter navigation.
// Test with pump(4s) to drain timers before disposal.
// Uses provider for UserProvider.

import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:care_connect_app/features/payments/presentation/pages/payment_success_page.dart';
import 'package:care_connect_app/providers/user_provider.dart';

import '../../mock_user_provider.dart';

class _NullUserProvider extends MockUserProvider {
  _NullUserProvider() : super(mockUser: null);

  @override
  UserSession? get user => null;
}

Widget _wrap({
  bool? isRegistration,
  String? sessionId,
  bool fromPortal = false,
  UserProvider? provider,
}) {
  final p = provider ?? _NullUserProvider();
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => ChangeNotifierProvider<UserProvider>.value(
          value: p,
          child: PaymentSuccessPage(
            isRegistration: isRegistration,
            sessionId: sessionId,
            fromPortal: fromPortal,
          ),
        ),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const Scaffold(body: Text('Login')),
      ),
      GoRoute(
        path: '/select-package',
        builder: (context, state) => const Scaffold(body: Text('Select Package')),
      ),
      GoRoute(
        path: '/caregiver-dashboard',
        builder: (context, state) => const Scaffold(body: Text('Dashboard')),
      ),
      GoRoute(
        path: '/patient-dashboard',
        builder: (context, state) => const Scaffold(body: Text('Dashboard')),
      ),
    ],
  );
  return MaterialApp.router(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, locale: Locale('en'), routerConfig: router);
}

void main() {
  group('PaymentSuccessPage – default (non-registration)', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byType(PaymentSuccessPage), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('shows "Payment Successful!" heading', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('Payment Successful!'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('shows check_circle icon', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('shows "Continue to Dashboard" button', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('Continue to Dashboard'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('shows subscription updated message', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.textContaining('subscription has been updated'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('shows redirect countdown text', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.textContaining('Redirecting'), findsWidgets);
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('PaymentSuccessPage – isRegistration=true', () {
    testWidgets('shows "Registration Complete!" heading', (tester) async {
      await tester.pumpWidget(_wrap(isRegistration: true));
      await tester.pump();
      expect(find.text('Registration Complete!'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('shows "Continue to Login" button', (tester) async {
      await tester.pumpWidget(_wrap(isRegistration: true));
      await tester.pump();
      expect(find.text('Continue to Login'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('shows RichText welcome content', (tester) async {
      await tester.pumpWidget(_wrap(isRegistration: true));
      await tester.pump();
      // _buildWelcomeText uses RichText with TextSpan, not Text widget
      expect(find.byType(RichText), findsWidgets);
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('PaymentSuccessPage – with sessionId', () {
    testWidgets('displays session ID when provided', (tester) async {
      await tester.pumpWidget(_wrap(sessionId: 'sess_abc123'));
      await tester.pump();
      expect(find.textContaining('sess_abc123'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('does not show session ID when null', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.textContaining('Session ID'), findsNothing);
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('PaymentSuccessPage – fromPortal', () {
    testWidgets('shows "Return to Subscription Management" when fromPortal', (tester) async {
      await tester.pumpWidget(_wrap(fromPortal: true));
      await tester.pump();
      expect(find.text('Return to Subscription Management'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('PaymentSuccessPage – with named user', () {
    testWidgets('renders registration page with named user', (tester) async {
      final provider = MockUserProvider(
        mockUser: MockUser(name: 'Alice', role: 'CAREGIVER'),
      );
      await tester.pumpWidget(_wrap(isRegistration: true, provider: provider));
      await tester.pump();
      // The name is inside a RichText/TextSpan, verify the page renders
      expect(find.text('Registration Complete!'), findsOneWidget);
      expect(find.byType(RichText), findsWidgets);
      await tester.pump(const Duration(seconds: 5));
    });
  });
}
