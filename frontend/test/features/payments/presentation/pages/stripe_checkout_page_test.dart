// Tests for StripeCheckoutPage
// (lib/features/payments/presentation/pages/stripe_checkout_page.dart).
//
// StripeCheckoutPage is now a redirect stub — it renders a loading spinner
// and navigates to /select-package on the first frame. Tests verify the
// stub behavior rather than the old Stripe payment UI.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:care_connect_app/features/payments/presentation/pages/stripe_checkout_page.dart';
import 'package:care_connect_app/features/payments/models/package_model.dart';

// ─── Helpers ─────────────────────────────────────────────────────────────────

PackageModel _makePackage({
  String name = 'Basic Plan',
  String description = 'Essential care features',
  int priceCents = 999,
  String id = 'pkg-1',
}) =>
    PackageModel(
      name: name,
      description: description,
      priceCents: priceCents,
      id: id,
    );

Widget _wrap({PackageModel? pkg, String? userId}) {
  final router = GoRouter(
    initialLocation: '/checkout',
    routes: [
      GoRoute(
        path: '/checkout',
        builder: (context, state) => StripeCheckoutPage(
          package: pkg ?? _makePackage(),
          userId: userId ?? '42',
        ),
      ),
      GoRoute(
        path: '/select-package',
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('Package Selection'))),
      ),
    ],
  );
  return MaterialApp.router(routerConfig: router);
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  group('StripeCheckoutPage – redirect stub', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(StripeCheckoutPage), findsOneWidget);
    });

    testWidgets('shows CircularProgressIndicator', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows a Scaffold', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(Scaffold), findsWidgets);
    });

    testWidgets('redirects to /select-package after first frame',
        (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      expect(find.text('Package Selection'), findsOneWidget);
    });

    testWidgets('accepts package and userId parameters', (tester) async {
      await tester.pumpWidget(
        _wrap(pkg: _makePackage(name: 'Pro Plan'), userId: '99'),
      );
      expect(find.byType(StripeCheckoutPage), findsOneWidget);
    });

    testWidgets('accepts fromPortal parameter', (tester) async {
      final router = GoRouter(
        initialLocation: '/checkout',
        routes: [
          GoRoute(
            path: '/checkout',
            builder: (context, state) => StripeCheckoutPage(
              package: _makePackage(),
              fromPortal: true,
            ),
          ),
          GoRoute(
            path: '/select-package',
            builder: (context, state) =>
                const Scaffold(body: Center(child: Text('Packages'))),
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      expect(find.byType(StripeCheckoutPage), findsOneWidget);
    });

    testWidgets('package model fields are accessible', (tester) async {
      final pkg = _makePackage(
        name: 'Test Plan',
        description: 'Desc',
        priceCents: 1999,
        id: 'pkg-test',
      );
      expect(pkg.name, 'Test Plan');
      expect(pkg.description, 'Desc');
      expect(pkg.priceCents, 1999);
      expect(pkg.id, 'pkg-test');
    });

    testWidgets('default fromPortal is false', (tester) async {
      final page = StripeCheckoutPage(
        package: _makePackage(),
      );
      expect(page.fromPortal, isFalse);
    });

    testWidgets('userId defaults to null', (tester) async {
      final page = StripeCheckoutPage(
        package: _makePackage(),
      );
      expect(page.userId, isNull);
    });

    testWidgets('paymentCustomerId defaults to null', (tester) async {
      final page = StripeCheckoutPage(
        package: _makePackage(),
      );
      expect(page.paymentCustomerId, isNull);
    });

    testWidgets('package with zero price', (tester) async {
      await tester.pumpWidget(_wrap(pkg: _makePackage(priceCents: 0)));
      expect(find.byType(StripeCheckoutPage), findsOneWidget);
    });

    testWidgets('package with large price', (tester) async {
      await tester.pumpWidget(_wrap(pkg: _makePackage(priceCents: 99999)));
      expect(find.byType(StripeCheckoutPage), findsOneWidget);
    });
  });
}
