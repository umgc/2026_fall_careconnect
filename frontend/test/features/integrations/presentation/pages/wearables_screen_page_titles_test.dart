// Page-title test for WearablesScreen (lib/features/integrations/presentation/pages/wearables_screen.dart).
// Setup copied from wearables_screen_test.dart; adds the page-title
// checks (WCAG 2.4.2) for this PR's TitledMaterialPageRoute changes.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/features/integrations/presentation/pages/wearables_screen.dart';
import '../../../../helpers/titled_route_probe.dart';

/// Wraps [child] with a UserProvider (needed by CommonDrawer) and a
/// MaterialApp.
Widget _wrap(Widget child) {
  final provider = UserProvider();
  provider.setUser(UserSession(
    id: 2,
    email: 'cg2@example.com',
    role: 'CAREGIVER',
    token: 'tok2',
  ));
  return ChangeNotifierProvider<UserProvider>.value(
    value: provider,
    child: MaterialApp(navigatorObservers: [probe], home: child),
  );
}

/// Creates a JSON-encoded list of connected devices for SharedPreferences.
String _makeDevicesJson(List<Map<String, dynamic>> devices) {
  return jsonEncode(devices);
}

/// A single Fitbit device JSON map.
Map<String, dynamic> _fitbitDevice({
  String id = 'fitbit-1',
  String name = 'My Fitbit',
  bool isActive = true,
  DateTime? connectedAt,
}) => {
  'id': id,
  'platform': 'fitbit',
  'name': name,
  'connectedAt': (connectedAt ?? DateTime.now().subtract(const Duration(hours: 2))).toIso8601String(),
  'permissions': ['steps', 'calories'],
  'isActive': isActive,
};

/// A Google Fit device JSON map.
Map<String, dynamic> _googleFitDevice({
  String id = 'gfit-1',
  String name = 'Google Fit',
  bool isActive = true,
}) => {
  'id': id,
  'platform': 'google_fit',
  'name': name,
  'connectedAt': DateTime.now().subtract(const Duration(days: 3)).toIso8601String(),
  'permissions': ['steps', 'heart_rate', 'calories'],
  'isActive': isActive,
};

/// An Apple Health device JSON map.
Map<String, dynamic> _appleHealthDevice({
  String id = 'ahealth-1',
  String name = 'Apple Health',
  bool isActive = true,
}) => {
  'id': id,
  'platform': 'apple_health',
  'name': name,
  'connectedAt': DateTime.now().subtract(const Duration(minutes: 10)).toIso8601String(),
  'permissions': ['steps'],
  'isActive': isActive,
};

/// An unknown-platform device JSON map.
Map<String, dynamic> _unknownDevice({
  String id = 'unknown-1',
  String name = 'Unknown Band',
  bool isActive = true,
}) => {
  'id': id,
  'platform': 'some_other',
  'name': name,
  'connectedAt': DateTime.now().subtract(const Duration(minutes: 30)).toIso8601String(),
  'permissions': [],
  'isActive': isActive,
};

/// Sets a tall test viewport and registers the teardown to reset it.
Future<void> _setTallViewport(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(800, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

/// Standard setUp for all tests - mocks secure storage and connectivity channels.
void _setUpChannels() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    (call) async {
      if (call.method == 'readAll') return <String, String>{};
      if (call.method == 'read') return null;
      if (call.method == 'containsKey') return false;
      if (call.method == 'write') return null;
      if (call.method == 'delete') return null;
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
}

TitledRouteProbe probe = TitledRouteProbe();

void main() {
  setUp(() {
    _setUpChannels();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('the add button opens a page titled "Add Device"',
      (tester) async {
    await _setTallViewport(tester);
    probe = TitledRouteProbe();
    await tester.pumpWidget(_wrap(const WearablesScreen()));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
        await probe.tapAndReadTitle(tester, find.byIcon(Icons.add).first),
        'Add Device');
  });
}
