// Tests for HomeMonitoringScreen
// (lib/features/integrations/presentation/pages/home_monitoring_screen.dart).
//
// Coverage strategy:
//   HomeMonitoringScreen is a StatefulWidget with a list of connected cameras
//   that is always empty on initialisation.  The CommonDrawer requires a
//   UserProvider; tests supply one via ChangeNotifierProvider.
//
//   Branches tested (empty-cameras state):
//     Scaffold renders              — widget builds without crashing.
//     "No Cameras Connected" text   — empty-state title is shown.
//     Supported-cameras card        — "Supported Cameras" section is present.
//     Camera type names             — Nest Cam Indoor, Outdoor, Doorbell shown.
//     "Add Your First Camera" btn   — CTA button is present.
//
//   Branches tested (_navigateToAddCamera dialog):
//     "Add Camera" dialog opens     — tapping the AppBar IconButton shows dialog.
//     Dialog has "Cancel" button    — Cancel is present in the dialog.
//     Tapping Cancel closes dialog  — dialog dismissed without crash.
//     "Add Your First Camera" btn   — opens the same dialog.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/features/integrations/presentation/pages/home_monitoring_screen.dart';

/// Wraps [child] with the providers required by HomeMonitoringScreen
/// (UserProvider is needed by the embedded CommonDrawer).
Widget _wrap(Widget child) {
  final provider = UserProvider();
  provider.setUser(UserSession(
    id: 1,
    email: 'cg@example.com',
    role: 'CAREGIVER',
    token: 'tok',
  ));
  return ChangeNotifierProvider<UserProvider>.value(
    value: provider,
    child: MaterialApp(home: child),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // ── empty-cameras state ───────────────────────────────────────────────────

  group('HomeMonitoringScreen – empty state', () {
    testWidgets('renders Scaffold without crashing', (tester) async {
      // Verifies the widget builds successfully with a mocked UserProvider.
      await tester.pumpWidget(_wrap(const HomeMonitoringScreen()));
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows "No Cameras Connected" title', (tester) async {
      // Verifies the empty-state heading is rendered.
      await tester.pumpWidget(_wrap(const HomeMonitoringScreen()));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('No Cameras Connected'), findsOneWidget);
    });

    testWidgets('shows "Supported Cameras" card', (tester) async {
      // Verifies the informational card listing supported hardware is shown.
      await tester.pumpWidget(_wrap(const HomeMonitoringScreen()));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Supported Cameras'), findsOneWidget);
    });

    testWidgets('shows Nest camera type names', (tester) async {
      // Verifies all three supported camera types are listed.
      await tester.pumpWidget(_wrap(const HomeMonitoringScreen()));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Nest Cam Indoor'), findsOneWidget);
      expect(find.text('Nest Cam Outdoor'), findsOneWidget);
      expect(find.text('Nest Doorbell'), findsOneWidget);
    });

    testWidgets('shows "Add Your First Camera" button', (tester) async {
      // Verifies the primary CTA button is rendered in the empty state.
      await tester.pumpWidget(_wrap(const HomeMonitoringScreen()));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Add Your First Camera'), findsOneWidget);
    });
  });

  // ── _navigateToAddCamera dialog ───────────────────────────────────────────

  group('HomeMonitoringScreen – add-camera dialog', () {
    testWidgets('tapping AppBar add icon opens "Add Camera" dialog', (
      tester,
    ) async {
      // Verifies the IconButton in the AppBar triggers _navigateToAddCamera.
      await tester.pumpWidget(_wrap(const HomeMonitoringScreen()));
      await tester.pump(const Duration(seconds: 1));

      // The AppBar add-icon and the body ElevatedButton both contain Icons.add;
      // tap .first which is the AppBar icon button.
      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pumpAndSettle();

      expect(find.text('Add Camera'), findsOneWidget);
    });

    testWidgets('dialog contains Cancel button', (tester) async {
      // Verifies the dismiss action is available in the dialog.
      await tester.pumpWidget(_wrap(const HomeMonitoringScreen()));
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pumpAndSettle();

      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('tapping Cancel closes the dialog', (tester) async {
      // Verifies Navigator.pop inside the Cancel button dismisses the dialog.
      await tester.pumpWidget(_wrap(const HomeMonitoringScreen()));
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Add Camera'), findsNothing);
    });

    testWidgets('"Add Your First Camera" button also opens the dialog', (
      tester,
    ) async {
      // Verifies the body CTA calls the same _navigateToAddCamera method.
      await tester.pumpWidget(_wrap(const HomeMonitoringScreen()));
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.text('Add Your First Camera'));
      await tester.pumpAndSettle();

      expect(find.text('Add Camera'), findsOneWidget);

      // Dismiss it
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  });
}
