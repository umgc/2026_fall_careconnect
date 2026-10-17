// Tests for DashboardAppHeader widget
// (lib/shared/widgets/dashboard_appheader_widget.dart).
//
// DashboardAppHeader is a PreferredSizeWidget that renders a custom AppBar.
// Since PR #344 (1fc33583) the emergency icon opens /medical-passport through
// GoRouter; no Provider is needed, so a plain MaterialApp suffices for render
// tests and _routed() for the icon.
//
// Test Plan §3.28: TC-HDR-001...012 are the existing tests (labels only; 008 and
// 009 are PR #344's); TC-HDR-013...015 are the Testing Lead's.

import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:care_connect_app/shared/widgets/dashboard_appheader_widget.dart';

Widget _wrap(DashboardAppHeader header) =>
    MaterialApp(locale: const Locale('en'), localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, home: Scaffold(appBar: header));

/// Puts the header in a GoRouter app with a stand-in /medical-passport page.
Widget _routed(DashboardAppHeader header) => MaterialApp.router(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: GoRouter(routes: [
        GoRoute(path: '/', builder: (_, __) => Scaffold(appBar: header)),
        GoRoute(path: '/medical-passport', builder: (_, __) => const Text('passport page')),
      ]),
    );

/// As _routed, with the router returned so a test can read where it is.
(Widget, GoRouter) _routedWith(DashboardAppHeader header) {
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, __) => Scaffold(appBar: header)),
    GoRoute(
      path: '/medical-passport',
      builder: (context, __) => Scaffold(
        body: TextButton(onPressed: () => context.pop(), child: const Text('passport page')),
      ),
    ),
  ]);
  return (
    MaterialApp.router(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
    router,
  );
}

void main() {
  group('DashboardAppHeader', () {
    testWidgets('TC-HDR-001: renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap(const DashboardAppHeader(
        userName: 'Alice',
        role: 'CAREGIVER',
      )));
      expect(find.byType(DashboardAppHeader), findsOneWidget);
    });

    testWidgets('TC-HDR-002: shows CARECONNECT logo text', (tester) async {
      await tester.pumpWidget(_wrap(const DashboardAppHeader(
        userName: 'Alice',
        role: 'CAREGIVER',
      )));
      expect(find.text('CARECONNECT'), findsOneWidget);
    });

    testWidgets('TC-HDR-003: shows welcome message with userName', (tester) async {
      await tester.pumpWidget(_wrap(const DashboardAppHeader(
        userName: 'John',
        role: 'CAREGIVER',
      )));
      expect(find.textContaining('Welcome back John'), findsOneWidget);
    });

    testWidgets('TC-HDR-004: shows caregiver summary text for CAREGIVER role', (tester) async {
      await tester.pumpWidget(_wrap(const DashboardAppHeader(
        userName: 'Alice',
        role: 'CAREGIVER',
      )));
      expect(find.textContaining("patients' health summary"), findsOneWidget);
    });

    testWidgets('TC-HDR-005: shows patient greeting for PATIENT role', (tester) async {
      await tester.pumpWidget(_wrap(const DashboardAppHeader(
        userName: 'Bob',
        role: 'PATIENT',
      )));
      expect(find.textContaining('How are you feeling today?'), findsOneWidget);
    });

    testWidgets('TC-HDR-006: shows settings icon', (tester) async {
      await tester.pumpWidget(_wrap(const DashboardAppHeader(
        userName: 'Alice',
        role: 'CAREGIVER',
      )));
      expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
    });

    testWidgets('TC-HDR-007: shows local_hospital icon (emergency QR)', (tester) async {
      await tester.pumpWidget(_wrap(const DashboardAppHeader(
        userName: 'Alice',
        role: 'CAREGIVER',
      )));
      expect(find.byIcon(Icons.local_hospital), findsAtLeastNWidgets(1));
    });

    testWidgets("TC-HDR-008: CC-12: the emergency icon opens the patient's passport", (tester) async {
      await tester.pumpWidget(_routed(const DashboardAppHeader(userName: 'Bob', role: 'PATIENT')));
      await tester.tap(find.widgetWithIcon(IconButton, Icons.local_hospital));
      await tester.pumpAndSettle();
      expect(find.text('passport page'), findsOneWidget);
    });

    testWidgets('TC-HDR-009: CC-12: the emergency icon stays put for a non-patient and says why', (tester) async {
      await tester.pumpWidget(_routed(const DashboardAppHeader(userName: 'Alice', role: 'CAREGIVER')));
      await tester.tap(find.widgetWithIcon(IconButton, Icons.local_hospital));
      await tester.pumpAndSettle();
      expect(find.text('passport page'), findsNothing);
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('TC-HDR-010: shows person icon when profileImageUrl is empty', (tester) async {
      await tester.pumpWidget(_wrap(const DashboardAppHeader(
        userName: 'Alice',
        role: 'CAREGIVER',
        profileImageUrl: '',
      )));
      expect(find.byIcon(Icons.person), findsOneWidget);
    });

    testWidgets('TC-HDR-011: preferredSize height is 210', (tester) async {
      const header = DashboardAppHeader(userName: 'Alice', role: 'CAREGIVER');
      expect(header.preferredSize.height, 210);
    });

    testWidgets('TC-HDR-012: renders AppBar widget', (tester) async {
      await tester.pumpWidget(_wrap(const DashboardAppHeader(
        userName: 'Alice',
        role: 'CAREGIVER',
      )));
      expect(find.byType(AppBar), findsOneWidget);
    });
    // ---------- Testing Lead (PR #344 review, 1fc33583) ----------

    testWidgets(
        'TC-HDR-013: for an account that is not a patient (FAMILY_LINK, ADMIN, '
        'no role) the emergency icon goes nowhere and says passports need '
        'patient data', (tester) async {
      for (final role in ['FAMILY_LINK', 'ADMIN', '']) {
        final (app, router) = _routedWith(DashboardAppHeader(userName: 'Alice', role: role));
        await tester.pumpWidget(app);
        await tester.tap(find.widgetWithIcon(IconButton, Icons.local_hospital));
        await tester.pumpAndSettle();
        expect(router.routerDelegate.currentConfiguration.uri.path, '/', reason: role);
        expect(find.text('Patient data not available for emergency QR'), findsOneWidget, reason: role);
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets(
        'TC-HDR-014: the passport is pushed over the dashboard, so Back returns '
        'to the dashboard', (tester) async {
      final (app, router) = _routedWith(const DashboardAppHeader(userName: 'Bob', role: 'PATIENT'));
      await tester.pumpWidget(app);
      await tester.tap(find.widgetWithIcon(IconButton, Icons.local_hospital));
      await tester.pumpAndSettle();
      expect(find.text('passport page'), findsOneWidget);
      expect(router.canPop(), isTrue, reason: 'pushed, not replaced');
      await tester.tap(find.text('passport page'));
      await tester.pumpAndSettle();
      expect(find.text('passport page'), findsNothing);
      expect(find.widgetWithIcon(IconButton, Icons.local_hospital), findsOneWidget);
    });

    testWidgets(
        'TC-HDR-015: a screen reader meets the emergency icon, now the only way '
        'to the passport, as a button named "Medical passport" (SC 4.1.2) '
        '(DEF-EMG-24)', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_routed(const DashboardAppHeader(userName: 'Bob', role: 'PATIENT')));
      expect(
          tester.getSemantics(find.widgetWithIcon(IconButton, Icons.local_hospital)),
          isSemantics(tooltip: 'Medical passport', isButton: true, hasTapAction: true));
      handle.dispose();
      // DEF-EMG-24: fixed by PR344_DEF-EMG-24-suggested.patch, not applied yet.
    }, skip: true);
  });
}
