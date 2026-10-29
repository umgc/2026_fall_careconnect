// Page-title tests for EvvDashboard (lib/features/evv/presentation/pages/evv_dashboard.dart).
// Setup copied from evv_dashboard_test.dart; adds the page-title
// checks (WCAG 2.4.2) for this PR's TitledMaterialPageRoute changes.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:care_connect_app/features/evv/presentation/pages/evv_dashboard.dart';
import 'package:care_connect_app/providers/user_provider.dart';

import '../../../../mock_user_provider.dart';
import '../../../../helpers/titled_route_probe.dart';

Widget _wrap({String role = 'CAREGIVER'}) {
  final provider = MockUserProvider(mockUser: MockUser(id: 1, role: role));
  return MaterialApp(
    navigatorObservers: [probe],
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

TitledRouteProbe probe = TitledRouteProbe();

void main() {
  setUp(() {
    probe = TitledRouteProbe();
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

  const cards = {
    'Start Visit': 'Select Patient for Visit',
    'Review Records': 'Review Visit Records',
    'Submit to HHAExchange': 'Submit Visits to HHAExchange',
    'Visit History': 'Visit History',
    'Manage Corrections': 'Visit Corrections',
    'Visit Schedules': 'Schedule',
    'Offline Sync': 'Offline Visit Sync',
  };

  for (final entry in cards.entries) {
    testWidgets('"${entry.key}" opens a page titled "${entry.value}"',
        (tester) async {
      // Visit History and Corrections are shown to admins and supervisors.
      const adminOnly = {'Visit History', 'Manage Corrections'};
      await tester.pumpWidget(
          _wrap(role: adminOnly.contains(entry.key) ? 'ADMIN' : 'CAREGIVER'));
      await _pumpUntilLoaded(tester);
      final card = find.text(entry.key, skipOffstage: false).last;
      // Lower cards are built lazily; scroll until this one exists.
      if (card.evaluate().isEmpty) {
        await tester.scrollUntilVisible(
            find.text(entry.key, skipOffstage: false), 200,
            scrollable: find.byType(Scrollable).first);
      }
      await tester.ensureVisible(card);
      await tester.pump();
      expect(await probe.tapAndReadTitle(tester, card), entry.value);
    });
  }
}
