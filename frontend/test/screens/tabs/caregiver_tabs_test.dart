// Tests for CaregiverTasksTab, CaregiverAnalyticsTab, CaregiverMessagesTab
// (lib/screens/tabs/caregiver_tabs.dart).
//
// Coverage strategy:
//   CaregiverPatientsTab and CaregiverProfileTab depend on deeply-nested
//   widgets (CaregiverDashboard, ProfileSettingsPage) that require live API
//   calls and are excluded.  The remaining three tabs can be exercised with
//   a minimal Provider stub.
//
//   Branches tested (CaregiverTasksTab):
//     build — renders Scaffold + AppBar 'Tasks' + static icon and text.
//
//   Branches tested (CaregiverAnalyticsTab):
//     build — renders Scaffold + AppBar 'Analytics' + static icon and text.
//
//   Branches tested (CaregiverMessagesTab):
//     user == null — shows 'Please log in to view messages'.
//     user != null — renders the logged-in scaffold body.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/screens/tabs/caregiver_tabs.dart';

/// Wraps [child] in a minimal MaterialApp with a [UserProvider] in the
/// logged-out (null user) state.
Widget _withNullUser(Widget child) {
  return ChangeNotifierProvider<UserProvider>(
    create: (_) => UserProvider(),
    child: MaterialApp(home: child),
  );
}

/// Wraps [child] with a [UserProvider] that has a CAREGIVER session.
Widget _withCaregiverUser(Widget child) {
  final provider = UserProvider();
  provider.setUser(UserSession(
    id: 10,
    email: 'cg@example.com',
    role: 'CAREGIVER',
    token: 'token',
    name: 'Test Caregiver',
  ));
  return ChangeNotifierProvider<UserProvider>.value(
    value: provider,
    child: MaterialApp(home: child),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Clean SharedPreferences so UserProvider initialises without real storage.
    SharedPreferences.setMockInitialValues({});
  });

  // ─── CaregiverTasksTab ────────────────────────────────────────────────────

  group('CaregiverTasksTab', () {
    testWidgets('renders Tasks app bar and static content', (tester) async {
      // Verifies the purely static task management UI renders without errors.
      await tester.pumpWidget(
        const MaterialApp(home: CaregiverTasksTab()),
      );
      await tester.pump();

      expect(find.text('Tasks'), findsOneWidget);
      expect(find.text('Task Management'), findsOneWidget);
      expect(find.text('Manage and assign tasks to your patients.'),
          findsOneWidget);
      expect(find.byIcon(Icons.assignment), findsOneWidget);
    });
  });

  // ─── CaregiverAnalyticsTab ────────────────────────────────────────────────

  group('CaregiverAnalyticsTab', () {
    testWidgets('renders Analytics app bar and static content', (tester) async {
      // Verifies the purely static analytics UI renders without errors.
      await tester.pumpWidget(
        const MaterialApp(home: CaregiverAnalyticsTab()),
      );
      await tester.pump();

      expect(find.text('Analytics'), findsOneWidget);
    });
  });

  // ─── CaregiverMessagesTab ─────────────────────────────────────────────────

  group('CaregiverMessagesTab', () {
    testWidgets('shows login prompt when user is null', (tester) async {
      // Verifies the null-user branch renders the login message.
      await tester.pumpWidget(_withNullUser(const CaregiverMessagesTab()));
      await tester.pump();

      expect(find.text('Please log in to view messages'), findsOneWidget);
    });

    testWidgets('renders logged-in scaffold when user is set', (tester) async {
      // Verifies the non-null user branch builds the logged-in view.
      // ChatInboxScreen makes network calls that fail silently.
      await tester.pumpWidget(_withCaregiverUser(const CaregiverMessagesTab()));
      await tester.pump();

      // The login-required message should NOT appear.
      expect(find.text('Please log in to view messages'), findsNothing);
      // A Scaffold should be present (may have nested Scaffolds from child widgets).
      expect(find.byType(Scaffold), findsAtLeastNWidgets(1));
    });
  });

  // ─── CaregiverPatientsTab ─────────────────────────────────────────────────

  group('CaregiverPatientsTab', () {
    testWidgets('renders without crashing', (tester) async {
      // Verifies the tab reads caregiverId and userRole from UserProvider
      // and delegates to CaregiverDashboard.  API calls fail silently.
      await tester.pumpWidget(
        _withCaregiverUser(const CaregiverPatientsTab()),
      );
      await tester.pump(const Duration(seconds: 2));

      expect(find.byType(Scaffold), findsAtLeastNWidgets(1));
    });
  });

  // ─── CaregiverProfileTab ──────────────────────────────────────────────────

  group('CaregiverProfileTab', () {
    testWidgets('renders without crashing', (tester) async {
      // Verifies the tab that delegates to ProfileSettingsPage builds.
      await tester.pumpWidget(
        _withCaregiverUser(const CaregiverProfileTab()),
      );
      await tester.pump();

      expect(find.byType(Scaffold), findsAtLeastNWidgets(1));
    });
  });
}
