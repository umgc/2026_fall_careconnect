// Tests for EvvDashboard
// (lib/features/evv/presentation/pages/evv_dashboard.dart).
//
// initState calls _loadDashboardData() which uses EvvService (API, try/catch).
// _isLoading starts true, so a spinner is shown immediately.
// After the API call fails (no server in tests), the catch block sets
// _isLoading = false and the full dashboard body is rendered.
//
// Tests wrap with MockUserProvider to satisfy Provider.of<UserProvider>.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:care_connect_app/features/evv/presentation/pages/evv_dashboard.dart';
import 'package:care_connect_app/providers/user_provider.dart';

import '../../mock_user_provider.dart';

Widget _wrap({String role = 'CAREGIVER'}) {
  final provider = MockUserProvider(mockUser: MockUser(id: 1, role: role));
  return MaterialApp(
    home: ChangeNotifierProvider<UserProvider>.value(
      value: provider,
      child: const EvvDashboard(),
    ),
  );
}

/// Pumps enough frames for the async _loadDashboardData to fail and setState
/// to fire, transitioning from loading to the dashboard body.
/// Also sets a large surface size to avoid overflow errors in test layout.
Future<void> _pumpUntilLoaded(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1600, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() => tester.view.resetPhysicalSize());
  addTearDown(() => tester.view.resetDevicePixelRatio());
  // The HTTP call inside EvvService will throw (no server).
  // Give enough time for the Future to fail and setState to fire.
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        if (call.method == 'readAll') return <String, String>{};
        if (call.method == 'containsKey') return false;
        return null;
      },
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async {
        if (call.method == 'check') return ['wifi'];
        return null;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      null,
    );
  });

  group('EvvDashboard – initial loading state', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(EvvDashboard), findsOneWidget);
    });

    testWidgets('shows "EVV Dashboard" in the AppBar', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('EVV Dashboard'), findsOneWidget);
    });

    testWidgets('shows CircularProgressIndicator while loading', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows Scaffold', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows AppBar', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('shows Center while loading', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(Center), findsWidgets);
    });

    testWidgets('does NOT show ListView while loading', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(ListView), findsNothing);
    });
  });

  group('EvvDashboard – CAREGIVER role after loading', () {
    testWidgets('shows Quick Stats section after loading', (tester) async {
      await tester.pumpWidget(_wrap(role: 'CAREGIVER'));
      await _pumpUntilLoaded(tester);
      expect(find.text('Quick Stats'), findsOneWidget);
    });

    testWidgets('shows Main Actions section after loading', (tester) async {
      await tester.pumpWidget(_wrap(role: 'CAREGIVER'));
      await _pumpUntilLoaded(tester);
      expect(find.text('Main Actions'), findsOneWidget);
    });

    testWidgets('shows Recent Activities section', (tester) async {
      await tester.pumpWidget(_wrap(role: 'CAREGIVER'));
      await _pumpUntilLoaded(tester);
      expect(find.text('Recent Activities'), findsOneWidget);
    });

    testWidgets('shows "No recent activity" text', (tester) async {
      await tester.pumpWidget(_wrap(role: 'CAREGIVER'));
      await _pumpUntilLoaded(tester);
      expect(find.text('No recent activity'), findsOneWidget);
    });

    testWidgets('shows Offline Records stat card', (tester) async {
      await tester.pumpWidget(_wrap(role: 'CAREGIVER'));
      await _pumpUntilLoaded(tester);
      expect(find.text('Offline Records'), findsOneWidget);
    });

    testWidgets('shows offline count as 0', (tester) async {
      await tester.pumpWidget(_wrap(role: 'CAREGIVER'));
      await _pumpUntilLoaded(tester);
      // Offline count should be 0 since API failed and offlineQueue stays empty
      expect(find.text('0'), findsOneWidget);
    });

    testWidgets('shows Start Visit action card for caregiver', (tester) async {
      await tester.pumpWidget(_wrap(role: 'CAREGIVER'));
      await _pumpUntilLoaded(tester);
      // Start Visit appears in both MainActions card and the FAB
      expect(find.text('Start Visit'), findsWidgets);
    });

    testWidgets('shows Review Records action card for caregiver', (tester) async {
      await tester.pumpWidget(_wrap(role: 'CAREGIVER'));
      await _pumpUntilLoaded(tester);
      expect(find.text('Review Records'), findsOneWidget);
    });

    testWidgets('shows Visit Schedules action card for caregiver', (tester) async {
      await tester.pumpWidget(_wrap(role: 'CAREGIVER'));
      await _pumpUntilLoaded(tester);
      expect(find.text('Visit Schedules'), findsOneWidget);
    });

    testWidgets('shows Offline Sync action card', (tester) async {
      await tester.pumpWidget(_wrap(role: 'CAREGIVER'));
      await _pumpUntilLoaded(tester);
      expect(find.text('Offline Sync'), findsOneWidget);
    });

    testWidgets('shows Start Visit FAB for caregiver', (tester) async {
      await tester.pumpWidget(_wrap(role: 'CAREGIVER'));
      await _pumpUntilLoaded(tester);
      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.byIcon(Icons.play_circle), findsWidgets);
    });

    testWidgets('does NOT show Pending Items section for caregiver',
        (tester) async {
      await tester.pumpWidget(_wrap(role: 'CAREGIVER'));
      await _pumpUntilLoaded(tester);
      expect(find.text('Pending Items'), findsNothing);
    });

    testWidgets('does NOT show Visit History for caregiver', (tester) async {
      await tester.pumpWidget(_wrap(role: 'CAREGIVER'));
      await _pumpUntilLoaded(tester);
      expect(find.text('Visit History'), findsNothing);
    });

    testWidgets('does NOT show Manage Corrections for caregiver',
        (tester) async {
      await tester.pumpWidget(_wrap(role: 'CAREGIVER'));
      await _pumpUntilLoaded(tester);
      expect(find.text('Manage Corrections'), findsNothing);
    });

    testWidgets('does NOT show Pending Approvals stat for caregiver',
        (tester) async {
      await tester.pumpWidget(_wrap(role: 'CAREGIVER'));
      await _pumpUntilLoaded(tester);
      expect(find.text('Pending Approvals'), findsNothing);
    });

    testWidgets('does NOT show Pending Corrections stat for caregiver',
        (tester) async {
      await tester.pumpWidget(_wrap(role: 'CAREGIVER'));
      await _pumpUntilLoaded(tester);
      expect(find.text('Pending Corrections'), findsNothing);
    });

    testWidgets('shows RefreshIndicator', (tester) async {
      await tester.pumpWidget(_wrap(role: 'CAREGIVER'));
      await _pumpUntilLoaded(tester);
      expect(find.byType(RefreshIndicator), findsOneWidget);
    });

    testWidgets('shows SingleChildScrollView after loading', (tester) async {
      await tester.pumpWidget(_wrap(role: 'CAREGIVER'));
      await _pumpUntilLoaded(tester);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });

    testWidgets('no CircularProgressIndicator after loading', (tester) async {
      await tester.pumpWidget(_wrap(role: 'CAREGIVER'));
      await _pumpUntilLoaded(tester);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('cloud_off icon shown in quick stats', (tester) async {
      await tester.pumpWidget(_wrap(role: 'CAREGIVER'));
      await _pumpUntilLoaded(tester);
      expect(find.byIcon(Icons.cloud_off), findsOneWidget);
    });

    testWidgets('dashboard_outlined icon shown in section header',
        (tester) async {
      await tester.pumpWidget(_wrap(role: 'CAREGIVER'));
      await _pumpUntilLoaded(tester);
      expect(find.byIcon(Icons.dashboard_outlined), findsOneWidget);
    });

    testWidgets('grid_view_rounded icon shown in main actions header',
        (tester) async {
      await tester.pumpWidget(_wrap(role: 'CAREGIVER'));
      await _pumpUntilLoaded(tester);
      expect(find.byIcon(Icons.grid_view_rounded), findsOneWidget);
    });

    testWidgets(
        'auto_awesome_motion_outlined icon shown in recent activities',
        (tester) async {
      await tester.pumpWidget(_wrap(role: 'CAREGIVER'));
      await _pumpUntilLoaded(tester);
      expect(
          find.byIcon(Icons.auto_awesome_motion_outlined), findsOneWidget);
    });
  });

  group('EvvDashboard – ADMIN role after loading', () {
    testWidgets('shows Pending Approvals stat for admin', (tester) async {
      await tester.pumpWidget(_wrap(role: 'ADMIN'));
      await _pumpUntilLoaded(tester);
      expect(find.text('Pending Approvals'), findsOneWidget);
    });

    testWidgets('shows Pending Corrections stat for admin', (tester) async {
      await tester.pumpWidget(_wrap(role: 'ADMIN'));
      await _pumpUntilLoaded(tester);
      expect(find.text('Pending Corrections'), findsOneWidget);
    });

    testWidgets('shows Pending Items section for admin', (tester) async {
      await tester.pumpWidget(_wrap(role: 'ADMIN'));
      await _pumpUntilLoaded(tester);
      expect(find.text('Pending Items'), findsOneWidget);
    });

    testWidgets('shows "No pending items" when counts are 0', (tester) async {
      await tester.pumpWidget(_wrap(role: 'ADMIN'));
      await _pumpUntilLoaded(tester);
      // After error, pending counts are 0, so "No pending items" shows
      expect(find.text('No pending items'), findsOneWidget);
    });

    testWidgets('shows Visit History action for admin', (tester) async {
      await tester.pumpWidget(_wrap(role: 'ADMIN'));
      await _pumpUntilLoaded(tester);
      expect(find.text('Visit History'), findsOneWidget);
    });

    testWidgets('shows Manage Corrections action for admin', (tester) async {
      await tester.pumpWidget(_wrap(role: 'ADMIN'));
      await _pumpUntilLoaded(tester);
      expect(find.text('Manage Corrections'), findsOneWidget);
    });

    testWidgets('shows Visit Schedules action for admin', (tester) async {
      await tester.pumpWidget(_wrap(role: 'ADMIN'));
      await _pumpUntilLoaded(tester);
      expect(find.text('Visit Schedules'), findsOneWidget);
    });

    testWidgets('shows Offline Sync action for admin', (tester) async {
      await tester.pumpWidget(_wrap(role: 'ADMIN'));
      await _pumpUntilLoaded(tester);
      expect(find.text('Offline Sync'), findsOneWidget);
    });

    testWidgets('does NOT show Start Visit action for admin', (tester) async {
      await tester.pumpWidget(_wrap(role: 'ADMIN'));
      await _pumpUntilLoaded(tester);
      // Admin should not have "Start Visit" in the main actions
      // (only caregivers have it)
      expect(find.text('Start Visit'), findsNothing);
    });

    testWidgets('does NOT show Review Records action for admin',
        (tester) async {
      await tester.pumpWidget(_wrap(role: 'ADMIN'));
      await _pumpUntilLoaded(tester);
      expect(find.text('Review Records'), findsNothing);
    });

    testWidgets('does NOT show FAB for admin', (tester) async {
      await tester.pumpWidget(_wrap(role: 'ADMIN'));
      await _pumpUntilLoaded(tester);
      expect(find.byType(FloatingActionButton), findsNothing);
    });

    testWidgets('shows approval icon in stat card for admin', (tester) async {
      await tester.pumpWidget(_wrap(role: 'ADMIN'));
      await _pumpUntilLoaded(tester);
      expect(find.byIcon(Icons.approval), findsOneWidget);
    });

    testWidgets('shows edit icon in stat card for admin', (tester) async {
      await tester.pumpWidget(_wrap(role: 'ADMIN'));
      await _pumpUntilLoaded(tester);
      expect(find.byIcon(Icons.edit), findsOneWidget);
    });

    testWidgets('shows pending_actions_outlined icon in pending items header',
        (tester) async {
      await tester.pumpWidget(_wrap(role: 'ADMIN'));
      await _pumpUntilLoaded(tester);
      expect(find.byIcon(Icons.pending_actions_outlined), findsOneWidget);
    });

    testWidgets('shows history icon for Visit History action', (tester) async {
      await tester.pumpWidget(_wrap(role: 'ADMIN'));
      await _pumpUntilLoaded(tester);
      expect(find.byIcon(Icons.history), findsOneWidget);
    });

    testWidgets('shows edit_note icon for Manage Corrections action',
        (tester) async {
      await tester.pumpWidget(_wrap(role: 'ADMIN'));
      await _pumpUntilLoaded(tester);
      expect(find.byIcon(Icons.edit_note), findsOneWidget);
    });
  });

  group('EvvDashboard – SUPERVISOR role after loading', () {
    testWidgets('shows Pending Approvals stat for supervisor', (tester) async {
      await tester.pumpWidget(_wrap(role: 'SUPERVISOR'));
      await _pumpUntilLoaded(tester);
      expect(find.text('Pending Approvals'), findsOneWidget);
    });

    testWidgets('shows Pending Corrections stat for supervisor',
        (tester) async {
      await tester.pumpWidget(_wrap(role: 'SUPERVISOR'));
      await _pumpUntilLoaded(tester);
      expect(find.text('Pending Corrections'), findsOneWidget);
    });

    testWidgets('shows Pending Items section for supervisor', (tester) async {
      await tester.pumpWidget(_wrap(role: 'SUPERVISOR'));
      await _pumpUntilLoaded(tester);
      expect(find.text('Pending Items'), findsOneWidget);
    });

    testWidgets('shows Visit History action for supervisor', (tester) async {
      await tester.pumpWidget(_wrap(role: 'SUPERVISOR'));
      await _pumpUntilLoaded(tester);
      expect(find.text('Visit History'), findsOneWidget);
    });

    testWidgets('shows Manage Corrections action for supervisor',
        (tester) async {
      await tester.pumpWidget(_wrap(role: 'SUPERVISOR'));
      await _pumpUntilLoaded(tester);
      expect(find.text('Manage Corrections'), findsOneWidget);
    });

    testWidgets('does NOT show FAB for supervisor', (tester) async {
      await tester.pumpWidget(_wrap(role: 'SUPERVISOR'));
      await _pumpUntilLoaded(tester);
      expect(find.byType(FloatingActionButton), findsNothing);
    });

    testWidgets('does NOT show Start Visit action for supervisor',
        (tester) async {
      await tester.pumpWidget(_wrap(role: 'SUPERVISOR'));
      await _pumpUntilLoaded(tester);
      expect(find.text('Start Visit'), findsNothing);
    });
  });

  group('EvvDashboard – PATIENT role after loading', () {
    testWidgets('shows Quick Stats for patient', (tester) async {
      await tester.pumpWidget(_wrap(role: 'PATIENT'));
      await _pumpUntilLoaded(tester);
      expect(find.text('Quick Stats'), findsOneWidget);
    });

    testWidgets('shows Main Actions for patient', (tester) async {
      await tester.pumpWidget(_wrap(role: 'PATIENT'));
      await _pumpUntilLoaded(tester);
      expect(find.text('Main Actions'), findsOneWidget);
    });

    testWidgets('shows Offline Sync action for patient', (tester) async {
      await tester.pumpWidget(_wrap(role: 'PATIENT'));
      await _pumpUntilLoaded(tester);
      expect(find.text('Offline Sync'), findsOneWidget);
    });

    testWidgets('does NOT show Start Visit for patient', (tester) async {
      await tester.pumpWidget(_wrap(role: 'PATIENT'));
      await _pumpUntilLoaded(tester);
      expect(find.text('Start Visit'), findsNothing);
    });

    testWidgets('does NOT show FAB for patient', (tester) async {
      await tester.pumpWidget(_wrap(role: 'PATIENT'));
      await _pumpUntilLoaded(tester);
      expect(find.byType(FloatingActionButton), findsNothing);
    });

    testWidgets('does NOT show Pending Items for patient', (tester) async {
      await tester.pumpWidget(_wrap(role: 'PATIENT'));
      await _pumpUntilLoaded(tester);
      expect(find.text('Pending Items'), findsNothing);
    });

    testWidgets('shows Visit History for patient', (tester) async {
      await tester.pumpWidget(_wrap(role: 'PATIENT'));
      await _pumpUntilLoaded(tester);
      expect(find.text('Visit History'), findsOneWidget);
    });

    testWidgets('does NOT show Manage Corrections for patient',
        (tester) async {
      await tester.pumpWidget(_wrap(role: 'PATIENT'));
      await _pumpUntilLoaded(tester);
      expect(find.text('Manage Corrections'), findsNothing);
    });

    testWidgets('does NOT show Review Records for patient', (tester) async {
      await tester.pumpWidget(_wrap(role: 'PATIENT'));
      await _pumpUntilLoaded(tester);
      expect(find.text('Review Records'), findsNothing);
    });

    testWidgets('shows Visit Schedules for patient', (tester) async {
      await tester.pumpWidget(_wrap(role: 'PATIENT'));
      await _pumpUntilLoaded(tester);
      expect(find.text('Visit Schedules'), findsOneWidget);
    });

    testWidgets('shows Recent Activities for patient', (tester) async {
      await tester.pumpWidget(_wrap(role: 'PATIENT'));
      await _pumpUntilLoaded(tester);
      expect(find.text('Recent Activities'), findsOneWidget);
    });
  });

  group('EvvDashboard – widget structure', () {
    testWidgets('has Card widgets after loading', (tester) async {
      await tester.pumpWidget(_wrap(role: 'CAREGIVER'));
      await _pumpUntilLoaded(tester);
      // Quick Stats, Main Actions, Recent Activities = 3 Cards minimum
      expect(find.byType(Card), findsWidgets);
    });

    testWidgets('has InkWell widgets for action cards', (tester) async {
      await tester.pumpWidget(_wrap(role: 'CAREGIVER'));
      await _pumpUntilLoaded(tester);
      // At least Start Visit, Review Records, Visit Schedules, Offline Sync
      expect(find.byType(InkWell), findsWidgets);
    });

    testWidgets('has schedule icon for Visit Schedules', (tester) async {
      await tester.pumpWidget(_wrap(role: 'CAREGIVER'));
      await _pumpUntilLoaded(tester);
      expect(find.byIcon(Icons.schedule), findsOneWidget);
    });

    testWidgets('has sync icon for Offline Sync action', (tester) async {
      await tester.pumpWidget(_wrap(role: 'CAREGIVER'));
      await _pumpUntilLoaded(tester);
      expect(find.byIcon(Icons.sync), findsOneWidget);
    });

    testWidgets('has rate_review icon for Review Records', (tester) async {
      await tester.pumpWidget(_wrap(role: 'CAREGIVER'));
      await _pumpUntilLoaded(tester);
      expect(find.byIcon(Icons.rate_review), findsOneWidget);
    });

    testWidgets('shows error snackbar when API fails', (tester) async {
      await tester.pumpWidget(_wrap(role: 'CAREGIVER'));
      await _pumpUntilLoaded(tester);
      // After API error, a SnackBar should have been shown
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('no offline queue section when queue is empty', (tester) async {
      await tester.pumpWidget(_wrap(role: 'CAREGIVER'));
      await _pumpUntilLoaded(tester);
      // _offlineQueue is empty after error, so the offline queue status
      // section should not appear
      expect(find.text('Offline Queue'), findsNothing);
      expect(find.text('Sync Now'), findsNothing);
    });

    testWidgets('admin shows 3 stat cards (offline, approvals, corrections)',
        (tester) async {
      await tester.pumpWidget(_wrap(role: 'ADMIN'));
      await _pumpUntilLoaded(tester);
      // Offline Records, Pending Approvals, Pending Corrections
      expect(find.text('Offline Records'), findsOneWidget);
      expect(find.text('Pending Approvals'), findsOneWidget);
      expect(find.text('Pending Corrections'), findsOneWidget);
    });

    testWidgets('caregiver shows 1 stat card (offline only)', (tester) async {
      await tester.pumpWidget(_wrap(role: 'CAREGIVER'));
      await _pumpUntilLoaded(tester);
      expect(find.text('Offline Records'), findsOneWidget);
      expect(find.text('Pending Approvals'), findsNothing);
      expect(find.text('Pending Corrections'), findsNothing);
    });

    testWidgets('GridView in main actions section', (tester) async {
      await tester.pumpWidget(_wrap(role: 'CAREGIVER'));
      await _pumpUntilLoaded(tester);
      expect(find.byType(GridView), findsOneWidget);
    });

    testWidgets('LayoutBuilder used for responsive layout', (tester) async {
      await tester.pumpWidget(_wrap(role: 'CAREGIVER'));
      await _pumpUntilLoaded(tester);
      // Quick Stats and Main Actions both use LayoutBuilder
      expect(find.byType(LayoutBuilder), findsWidgets);
    });
  });
}
