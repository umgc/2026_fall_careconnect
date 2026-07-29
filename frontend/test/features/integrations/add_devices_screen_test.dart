// Tests for AddDeviceScreen widget
// (lib/features/integrations/presentation/pages/add_devices_screen.dart).
//
// Coverage strategy:
//   AddDeviceScreen is a multi-step wizard for connecting health platforms.
//   Fitbit connects through Google Health OAuth (Authorization Code + PKCE).
//   Legacy Fitbit Web API credentials are no longer used for this flow.
//
//   The widget also calls _loadConnectedDevices() in initState which reads
//   SharedPreferences ('connected_devices' key).  We seed mock prefs to
//   control that.
//
//   Branches tested:
//     Step 0 (Select)    — title text, platform cards, Fitbit card content
//     Step indicators    — three step labels rendered
//     Initial state      — no connecting/connected indicators
//
//   Branches NOT tested (require real platform APIs):
//     _connectToFitbitReal     — FitbitConnector.authorize (native plugin)
//     _connectToAppleHealthReal — Health().requestAuthorization (iOS only)
//     _connectToGoogleFitReal  — Health().configure/requestAuthorization (Android only)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';

import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/features/integrations/presentation/pages/add_devices_screen.dart';

/// Wraps [child] with UserProvider + MaterialApp so the widget tree is valid.
Widget _wrap(Widget child) {
  final provider = UserProvider();
  provider.setUser(UserSession(
    id: 1,
    email: 'patient@test.com',
    role: 'PATIENT',
    token: 'tok',
    name: 'Test Patient',
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

  // ─── Step 0 — Select Platform ──────────────────────────────────────────────

  group('AddDeviceScreen — step 0 (select platform)', () {
    testWidgets('renders Scaffold without crashing', (tester) async {
      await tester.pumpWidget(_wrap(const AddDeviceScreen()));
      await tester.pump();

      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows app bar title "Add Health Platform"', (tester) async {
      await tester.pumpWidget(_wrap(const AddDeviceScreen()));
      await tester.pump();

      expect(find.text('Add Health Platform'), findsOneWidget);
    });

    testWidgets('shows "Choose Health Platform" heading', (tester) async {
      await tester.pumpWidget(_wrap(const AddDeviceScreen()));
      await tester.pump();

      expect(find.text('Choose Health Platform'), findsOneWidget);
    });

    testWidgets('shows instruction text about selecting a platform',
        (tester) async {
      await tester.pumpWidget(_wrap(const AddDeviceScreen()));
      await tester.pump();

      expect(
        find.textContaining('Select which health platform'),
        findsOneWidget,
      );
    });

    testWidgets('shows Fitbit platform card', (tester) async {
      await tester.pumpWidget(_wrap(const AddDeviceScreen()));
      await tester.pump();

      expect(find.text('Fitbit'), findsOneWidget);
    });

    testWidgets('shows Fitbit description', (tester) async {
      await tester.pumpWidget(_wrap(const AddDeviceScreen()));
      await tester.pump();

      expect(
        find.textContaining('Connect Fitbit through Google Health'),
        findsOneWidget,
      );
    });

    testWidgets('shows "Health Metrics:" label', (tester) async {
      await tester.pumpWidget(_wrap(const AddDeviceScreen()));
      await tester.pump();

      expect(find.text('Health Metrics:'), findsWidgets);
    });

    testWidgets('shows Steps feature chip', (tester) async {
      await tester.pumpWidget(_wrap(const AddDeviceScreen()));
      await tester.pump();

      expect(find.text('Steps'), findsWidgets);
    });

    testWidgets('shows Heart Rate feature chip', (tester) async {
      await tester.pumpWidget(_wrap(const AddDeviceScreen()));
      await tester.pump();

      expect(find.text('Heart Rate'), findsWidgets);
    });

    testWidgets('shows arrow_forward_ios icon for unconnected platform',
        (tester) async {
      await tester.pumpWidget(_wrap(const AddDeviceScreen()));
      await tester.pump();

      expect(find.byIcon(Icons.arrow_forward_ios), findsWidgets);
    });

    testWidgets('shows fitness_center icon for Fitbit', (tester) async {
      await tester.pumpWidget(_wrap(const AddDeviceScreen()));
      await tester.pump();

      expect(find.byIcon(Icons.fitness_center), findsOneWidget);
    });
  });

  // ─── Step indicators ──────────────────────────────────────────────────────

  group('AddDeviceScreen — step indicators', () {
    testWidgets('shows Select step label', (tester) async {
      await tester.pumpWidget(_wrap(const AddDeviceScreen()));
      await tester.pump();

      expect(find.text('Select'), findsOneWidget);
    });

    testWidgets('shows Connect step label', (tester) async {
      await tester.pumpWidget(_wrap(const AddDeviceScreen()));
      await tester.pump();

      expect(find.text('Connect'), findsOneWidget);
    });

    testWidgets('shows Complete step label', (tester) async {
      await tester.pumpWidget(_wrap(const AddDeviceScreen()));
      await tester.pump();

      expect(find.text('Complete'), findsOneWidget);
    });

    testWidgets('shows step number 1', (tester) async {
      await tester.pumpWidget(_wrap(const AddDeviceScreen()));
      await tester.pump();

      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('shows step number 2', (tester) async {
      await tester.pumpWidget(_wrap(const AddDeviceScreen()));
      await tester.pump();

      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('shows step number 3', (tester) async {
      await tester.pumpWidget(_wrap(const AddDeviceScreen()));
      await tester.pump();

      expect(find.text('3'), findsOneWidget);
    });
  });

  // ─── Initial state checks ─────────────────────────────────────────────────

  group('AddDeviceScreen — initial state', () {
    testWidgets('does not show CircularProgressIndicator initially',
        (tester) async {
      await tester.pumpWidget(_wrap(const AddDeviceScreen()));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('does not show "Connected" badge initially', (tester) async {
      await tester.pumpWidget(_wrap(const AddDeviceScreen()));
      await tester.pump();

      expect(find.text('Connected'), findsNothing);
    });

    testWidgets('does not show check_circle icon initially', (tester) async {
      await tester.pumpWidget(_wrap(const AddDeviceScreen()));
      await tester.pump();

      expect(find.byIcon(Icons.check_circle), findsNothing);
    });

    testWidgets('does not show error icon initially', (tester) async {
      await tester.pumpWidget(_wrap(const AddDeviceScreen()));
      await tester.pump();

      expect(find.byIcon(Icons.error), findsNothing);
    });

    testWidgets('does not show "Connection Failed" text initially',
        (tester) async {
      await tester.pumpWidget(_wrap(const AddDeviceScreen()));
      await tester.pump();

      expect(find.text('Connection Failed'), findsNothing);
    });

    testWidgets('does not show "Successfully Connected!" text initially',
        (tester) async {
      await tester.pumpWidget(_wrap(const AddDeviceScreen()));
      await tester.pump();

      expect(find.text('Successfully Connected!'), findsNothing);
    });

    testWidgets('does not show "Back to Dashboard" button initially',
        (tester) async {
      await tester.pumpWidget(_wrap(const AddDeviceScreen()));
      await tester.pump();

      expect(find.text('Back to Dashboard'), findsNothing);
    });

    testWidgets('does not show "Add Another Platform" button initially',
        (tester) async {
      await tester.pumpWidget(_wrap(const AddDeviceScreen()));
      await tester.pump();

      expect(find.text('Add Another Platform'), findsNothing);
    });

    testWidgets('shows back arrow button in app bar', (tester) async {
      await tester.pumpWidget(_wrap(const AddDeviceScreen()));
      await tester.pump();

      expect(find.byIcon(Icons.arrow_back), findsWidgets);
    });

    testWidgets('has at least one Card widget for platforms', (tester) async {
      await tester.pumpWidget(_wrap(const AddDeviceScreen()));
      await tester.pump();

      expect(find.byType(Card), findsWidgets);
    });

    testWidgets('has at least one InkWell for tappable platform cards',
        (tester) async {
      await tester.pumpWidget(_wrap(const AddDeviceScreen()));
      await tester.pump();

      expect(find.byType(InkWell), findsWidgets);
    });
  });

  // ─── Pre-connected devices from SharedPreferences ─────────────────────────

  group('AddDeviceScreen — with pre-connected device in prefs', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({
        'connected_devices':
            '[{"id":"fitbit_123","platform":"fitbit","name":"Fitbit","connectedAt":"2025-01-01T00:00:00.000","permissions":["steps","calories"],"isActive":true}]',
      });
    });

    testWidgets('loads connected devices from SharedPreferences without crash',
        (tester) async {
      // _loadConnectedDevices reads from SharedPreferences but does not call
      // setState, so the UI won't visually reflect the loaded data.
      // This test verifies the load path does not throw.
      await tester.pumpWidget(_wrap(const AddDeviceScreen()));
      await tester.pumpAndSettle();

      // Widget should still render the step-0 UI
      expect(find.text('Choose Health Platform'), findsOneWidget);
      expect(find.text('Fitbit'), findsOneWidget);
    });

    testWidgets('still shows step indicators after loading prefs',
        (tester) async {
      await tester.pumpWidget(_wrap(const AddDeviceScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Select'), findsOneWidget);
      expect(find.text('Connect'), findsOneWidget);
      expect(find.text('Complete'), findsOneWidget);
    });
  });
}
