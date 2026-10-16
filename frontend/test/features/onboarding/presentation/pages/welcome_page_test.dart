// Tests for WelcomePage
// (lib/features/onboarding/presentation/pages/welcome_page.dart).
//
// Pure StatelessWidget — no Provider, no API calls.
// Uses AppBarHelper.createAppBar() and context.go('/login') from go_router,
// so tests wrap with MaterialApp.router + GoRouter.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:care_connect_app/features/onboarding/presentation/pages/welcome_page.dart';

Widget _wrap() => MaterialApp.router(
      routerConfig: GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, __) => const WelcomePage(),
          ),
          GoRoute(
            path: '/login',
            builder: (_, __) => const Scaffold(body: Text('Login')),
          ),
        ],
      ),
    );

void main() {
  group('WelcomePage', () {
    testWidgets('renders without crashing', (tester) async {
      // Verifies the page builds without error.
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      expect(find.byType(WelcomePage), findsOneWidget);
    });

    testWidgets('shows "Welcome" in the AppBar', (tester) async {
      // AppBarHelper.createAppBar is called with title "Welcome".
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      expect(find.text('Welcome'), findsOneWidget);
    });

    testWidgets('shows "Welcome to CareConnect" heading', (tester) async {
      // The hero text must be visible in the page body.
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      expect(find.text('Welcome to CareConnect'), findsOneWidget);
    });

    testWidgets('shows "Get started" button', (tester) async {
      // The primary action button must be visible.
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      expect(find.text('Get started'), findsOneWidget);
    });

    testWidgets('shows FilledButton', (tester) async {
      // The CTA uses a FilledButton (not ElevatedButton).
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      expect(find.byType(FilledButton), findsOneWidget);
    });

    testWidgets('shows favorite icon', (tester) async {
      // A large Icons.favorite icon serves as the brand mark.
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.favorite), findsOneWidget);
    });

    testWidgets('tapping "Get started" navigates to login', (tester) async {
      // context.go("/login") must navigate away from WelcomePage.
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Get started'));
      await tester.pumpAndSettle();
      expect(find.text('Login'), findsOneWidget);
      expect(find.byType(WelcomePage), findsNothing);
    });
  });
}
