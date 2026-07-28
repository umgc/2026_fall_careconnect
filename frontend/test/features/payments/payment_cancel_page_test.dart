// Tests for PaymentCancelPage widget
// (lib/features/payments/presentation/pages/payment_cancel_page.dart).
//
// Pure StatelessWidget — no API calls or Provider usage at render time.
// Provider.of<UserProvider> is accessed only inside onPressed callbacks,
// so render-only tests work with a plain MaterialApp wrapper.

import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:care_connect_app/features/payments/presentation/pages/payment_cancel_page.dart';
import 'package:care_connect_app/providers/user_provider.dart';

import '../../mock_user_provider.dart';

Widget _wrap(Widget child) => MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, locale: Locale('en'), home: child);

Widget _wrapWithRouter({
  bool? isRegistration,
  UserProvider? provider,
}) {
  final p = provider ?? MockUserProvider(mockUser: null);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => ChangeNotifierProvider<UserProvider>.value(
          value: p,
          child: PaymentCancelPage(isRegistration: isRegistration),
        ),
      ),
      GoRoute(
        path: '/select-package',
        builder: (context, state) => const Scaffold(body: Text('Select Package')),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const Scaffold(body: Text('Login')),
      ),
    ],
  );
  return MaterialApp.router(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, locale: Locale('en'), routerConfig: router);
}

void main() {
  group('PaymentCancelPage – default (isRegistration=false)', () {
    testWidgets('renders without crashing', (tester) async {
      // Verifies the page builds without error for the standard cancel case.
      await tester.pumpWidget(_wrap(const PaymentCancelPage()));
      expect(find.byType(PaymentCancelPage), findsOneWidget);
    });

    testWidgets('shows "Payment Cancelled" heading', (tester) async {
      // The main heading must be visible in the standard cancel case.
      await tester.pumpWidget(_wrap(const PaymentCancelPage()));
      expect(find.text('Payment Cancelled'), findsWidgets);
    });

    testWidgets('shows cancel_outlined icon', (tester) async {
      // The large red cancel icon must be present.
      await tester.pumpWidget(_wrap(const PaymentCancelPage()));
      expect(find.byIcon(Icons.cancel_outlined), findsOneWidget);
    });

    testWidgets('shows "no charges were made" message', (tester) async {
      // The body text should reassure the user no charges were made.
      await tester.pumpWidget(_wrap(const PaymentCancelPage()));
      expect(
        find.textContaining('No charges were made'),
        findsWidgets,
      );
    });

    testWidgets('shows "Return to Dashboard" button', (tester) async {
      // The primary action for standard cancel is returning to the dashboard.
      await tester.pumpWidget(_wrap(const PaymentCancelPage()));
      expect(find.text('Return to Dashboard'), findsOneWidget);
    });

    testWidgets('shows "Go to Home" secondary link', (tester) async {
      // The secondary TextButton lets the user navigate home.
      await tester.pumpWidget(_wrap(const PaymentCancelPage()));
      expect(find.text('Go to Home'), findsOneWidget);
    });

    testWidgets('shows ElevatedButton', (tester) async {
      // An ElevatedButton is the primary CTA on this page.
      await tester.pumpWidget(_wrap(const PaymentCancelPage()));
      expect(find.byType(ElevatedButton), findsOneWidget);
    });
  });

  group('PaymentCancelPage – isRegistration=true', () {
    testWidgets('renders without crashing', (tester) async {
      // Verifies the registration-cancel variant builds without error.
      await tester.pumpWidget(
          _wrap(const PaymentCancelPage(isRegistration: true)));
      expect(find.byType(PaymentCancelPage), findsOneWidget);
    });

    testWidgets('shows "Try Payment Again" button for registration', (tester) async {
      // Registration cancel redirects the user to retry payment.
      await tester.pumpWidget(
          _wrap(const PaymentCancelPage(isRegistration: true)));
      expect(find.text('Try Payment Again'), findsOneWidget);
    });

    testWidgets('shows "Skip for Now" secondary link for registration',
        (tester) async {
      // Registration cancel has a "Skip" option to go to login.
      await tester.pumpWidget(
          _wrap(const PaymentCancelPage(isRegistration: true)));
      expect(find.text('Skip for Now (Go to Login)'), findsOneWidget);
    });

    testWidgets('shows registration-specific body message', (tester) async {
      // Registration cancel text explains payment is needed to complete setup.
      await tester.pumpWidget(
          _wrap(const PaymentCancelPage(isRegistration: true)));
      expect(
        find.textContaining('registration is not complete'),
        findsOneWidget,
      );
    });
  });

  group('PaymentCancelPage – navigation (isRegistration=true)', () {
    testWidgets('Try Payment Again navigates to /select-package', (tester) async {
      await tester.pumpWidget(_wrapWithRouter(isRegistration: true));
      await tester.pump();
      await tester.tap(find.text('Try Payment Again'));
      await tester.pumpAndSettle();
      expect(find.text('Select Package'), findsOneWidget);
    });

    testWidgets('Skip for Now navigates to /login with null user', (tester) async {
      await tester.pumpWidget(_wrapWithRouter(
        isRegistration: true,
        provider: MockUserProvider(mockUser: null),
      ));
      await tester.pump();
      await tester.tap(find.text('Skip for Now (Go to Login)'));
      await tester.pumpAndSettle();
      expect(find.text('Login'), findsOneWidget);
    });

    testWidgets('Skip for Now navigates to /login with named user', (tester) async {
      await tester.pumpWidget(_wrapWithRouter(
        isRegistration: true,
        provider: MockUserProvider(
          mockUser: MockUser(name: 'Alice', role: 'CAREGIVER'),
        ),
      ));
      await tester.pump();
      await tester.tap(find.text('Skip for Now (Go to Login)'));
      await tester.pumpAndSettle();
      expect(find.text('Login'), findsOneWidget);
    });
  });

  group('PaymentCancelPage – layout details', () {
    testWidgets('shows SafeArea', (tester) async {
      await tester.pumpWidget(_wrap(const PaymentCancelPage()));
      expect(find.byType(SafeArea), findsWidgets);
    });

    testWidgets('shows TextButton for secondary action', (tester) async {
      await tester.pumpWidget(_wrap(const PaymentCancelPage()));
      expect(find.byType(TextButton), findsOneWidget);
    });

    testWidgets('isRegistration defaults to false', (tester) async {
      await tester.pumpWidget(_wrap(const PaymentCancelPage()));
      expect(find.text('Return to Dashboard'), findsOneWidget);
      expect(find.text('Go to Home'), findsOneWidget);
    });

    testWidgets('shows cancel icon with correct size', (tester) async {
      await tester.pumpWidget(_wrap(const PaymentCancelPage()));
      final icon = tester.widget<Icon>(find.byIcon(Icons.cancel_outlined));
      expect(icon.size, 80);
    });
  });
}
