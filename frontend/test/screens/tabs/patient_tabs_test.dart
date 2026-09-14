// Tests for PatientHealthTab, PatientMessagesTab, PatientReportsTab
// (lib/screens/tabs/patient_tabs.dart).
//
// Coverage strategy:
//   PatientHomeTab and PatientProfileTab depend on deeply-nested widgets
//   (PatientDashboard, ProfileSettingsPage) that require live API calls and
//   are excluded.  The remaining tabs can be exercised via Provider stubs.
//
//   Branches tested (PatientHealthTab):
//     build — renders Scaffold + AppBar 'Health' + static icon and text.
//
//   Branches tested (PatientMessagesTab):
//     user == null — shows 'Please log in to view messages'.
//     user != null — renders the logged-in scaffold (ChatInboxScreen).
//
//   Branches tested (PatientReportsTab):
//     build — renders without crashing (delegates to PatientReportsScreen).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/screens/tabs/patient_tabs.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';

MaterialApp _app(Widget child) => MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );

/// Wraps [child] in a minimal MaterialApp with a [UserProvider] whose
/// initial session is null (logged-out state).
Widget _withNullUser(Widget child) {
  return ChangeNotifierProvider<UserProvider>(
    create: (_) => UserProvider(),
    child: _app(child),
  );
}

/// Wraps [child] with a [UserProvider] that has a PATIENT session.
Widget _withPatientUser(Widget child) {
  final provider = UserProvider();
  provider.setUser(UserSession(
    id: 5,
    email: 'patient@example.com',
    role: 'PATIENT',
    token: 'token',
    name: 'Test Patient',
  ));
  return ChangeNotifierProvider<UserProvider>.value(
    value: provider,
    child: _app(child),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Provide a clean SharedPreferences store so UserProvider initialises
    // without hitting real persistent storage.
    SharedPreferences.setMockInitialValues({});
  });

  // ─── PatientHealthTab ─────────────────────────────────────────────────────

  group('PatientHealthTab', () {
    testWidgets('renders Health app bar and static content', (tester) async {
      // Verifies the purely static UI renders without errors and displays
      // the expected title and text strings.
      await tester.pumpWidget(
        const MaterialApp(home: PatientHealthTab()),
      );
      await tester.pump();

      expect(find.text('Health'), findsOneWidget);
      expect(find.text('Health Tracking'), findsOneWidget);
      expect(find.text('Monitor your health metrics, medications, and wellness goals.'),
          findsOneWidget);
      expect(find.byIcon(Icons.health_and_safety), findsOneWidget);
    });
  });

  // ─── PatientMessagesTab ───────────────────────────────────────────────────

  group('PatientMessagesTab', () {
    testWidgets('shows login prompt when user is null', (tester) async {
      // Verifies the null-user branch renders the login message.
      await tester.pumpWidget(_withNullUser(const PatientMessagesTab()));
      await tester.pump();

      expect(find.text('Please log in to view messages'), findsOneWidget);
      expect(find.text('Messages'), findsOneWidget);
    });

    testWidgets('renders logged-in scaffold when user is set', (tester) async {
      // Verifies the non-null user branch builds the logged-in view.
      // ChatInboxScreen makes network calls that fail silently.
      await tester.pumpWidget(_withPatientUser(const PatientMessagesTab()));
      await tester.pump();

      // The Messages text should be present in the logged-in branch.
      expect(find.text('Messages'), findsAtLeastNWidgets(1));
      // The login-required message should NOT appear.
      expect(find.text('Please log in to view messages'), findsNothing);
    });
  });

  // ─── PatientReportsTab ────────────────────────────────────────────────────

  group('PatientReportsTab', () {
    testWidgets('renders without crashing', (tester) async {
      // Verifies the tab that delegates to PatientReportsScreen builds.
      await tester.pumpWidget(
        _withPatientUser(const PatientReportsTab()),
      );
      await tester.pump();

      expect(find.byType(Scaffold), findsAtLeastNWidgets(1));
    });
  });

  // ─── PatientHomeTab ───────────────────────────────────────────────────────

  group('PatientHomeTab', () {
    testWidgets('renders without crashing with patient user', (tester) async {
      // Use a larger surface to avoid RenderFlex overflow errors.
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // Verifies the tab reads userId from UserProvider and delegates to
      // PatientDashboard.  Sub-widget API calls fail silently (no live server).
      await tester.pumpWidget(
        _withPatientUser(const PatientHomeTab()),
      );
      await tester.pump(const Duration(seconds: 2));

      expect(find.byType(Scaffold), findsAtLeastNWidgets(1));
    });
  });

  // ─── PatientProfileTab ───────────────────────────────────────────────────

  group('PatientProfileTab', () {
    testWidgets('renders without crashing', (tester) async {
      // Verifies the tab that delegates to ProfileSettingsPage builds.
      await tester.pumpWidget(
        _withPatientUser(const PatientProfileTab()),
      );
      await tester.pump(const Duration(seconds: 2));

      expect(find.byType(Scaffold), findsAtLeastNWidgets(1));
    });
  });
}
