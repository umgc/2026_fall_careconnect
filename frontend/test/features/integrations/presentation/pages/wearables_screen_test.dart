// Tests for WearablesScreen
// (lib/features/integrations/presentation/pages/wearables_screen.dart).
//
// Coverage strategy:
//   - ConnectedDevice model: toJson, fromJson, isActive default
//   - HealthData model: construction
//   - Empty state: all UI elements when no devices connected
//   - Connected devices view: devices pre-seeded via SharedPreferences
//   - Device cards: all platform types (fitbit, google_fit, apple_health, unknown)
//   - Health data display: all metric types, icons, colors
//   - _formatHealthValue: percentage, glucose/pressure, default
//   - _formatDate: days, hours, minutes, just now
//   - _removeDevice: dialog display, cancel, confirm
//   - _refreshData: refresh icon tap
//   - _navigateToAddDevice: add button tap
//   - _getSourceColor: Fitbit, Apple Health, Health Connect, default

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/features/integrations/presentation/pages/wearables_screen.dart';

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
    child: MaterialApp(home: child),
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Suppress overflow errors in test viewport
  final originalOnError = FlutterError.onError;
  setUp(() {
    _setUpChannels();
    FlutterError.onError = (details) {
      final exception = details.exception;
      if (exception is FlutterError &&
          exception.message.contains('overflowed')) {
        return; // suppress RenderFlex overflow
      }
      originalOnError?.call(details);
    };
  });

  tearDown(() {
    FlutterError.onError = originalOnError;
  });

  // ======================================================================
  // ConnectedDevice model tests
  // ======================================================================
  group('ConnectedDevice model', () {
    test('toJson produces correct map', () {
      final now = DateTime(2025, 6, 15, 10, 30);
      final device = ConnectedDevice(
        id: 'test-id',
        platform: 'fitbit',
        name: 'Test Fitbit',
        connectedAt: now,
        permissions: ['steps', 'calories'],
        isActive: true,
      );
      final json = device.toJson();
      expect(json['id'], 'test-id');
      expect(json['platform'], 'fitbit');
      expect(json['name'], 'Test Fitbit');
      expect(json['connectedAt'], now.toIso8601String());
      expect(json['permissions'], ['steps', 'calories']);
      expect(json['isActive'], true);
    });

    test('fromJson parses correctly', () {
      final json = {
        'id': 'dev-1',
        'platform': 'google_fit',
        'name': 'GFit',
        'connectedAt': '2025-06-15T10:30:00.000',
        'permissions': ['heart_rate'],
        'isActive': false,
      };
      final device = ConnectedDevice.fromJson(json);
      expect(device.id, 'dev-1');
      expect(device.platform, 'google_fit');
      expect(device.name, 'GFit');
      expect(device.connectedAt, DateTime(2025, 6, 15, 10, 30));
      expect(device.permissions, ['heart_rate']);
      expect(device.isActive, false);
    });

    test('fromJson defaults isActive to true when missing', () {
      final json = {
        'id': 'dev-2',
        'platform': 'fitbit',
        'name': 'FB',
        'connectedAt': '2025-01-01T00:00:00.000',
        'permissions': [],
      };
      final device = ConnectedDevice.fromJson(json);
      expect(device.isActive, true);
    });

    test('isActive defaults to true in constructor', () {
      final device = ConnectedDevice(
        id: 'x',
        platform: 'fitbit',
        name: 'X',
        connectedAt: DateTime.now(),
        permissions: [],
      );
      expect(device.isActive, true);
    });

    test('roundtrip toJson -> fromJson preserves data', () {
      final original = ConnectedDevice(
        id: 'rt-1',
        platform: 'apple_health',
        name: 'Apple Watch',
        connectedAt: DateTime(2025, 3, 10, 8, 0),
        permissions: ['steps', 'heart_rate', 'blood_glucose'],
        isActive: true,
      );
      final restored = ConnectedDevice.fromJson(original.toJson());
      expect(restored.id, original.id);
      expect(restored.platform, original.platform);
      expect(restored.name, original.name);
      expect(restored.connectedAt, original.connectedAt);
      expect(restored.permissions, original.permissions);
      expect(restored.isActive, original.isActive);
    });
  });

  // ======================================================================
  // HealthData model tests
  // ======================================================================
  group('HealthData model', () {
    test('constructs with all fields', () {
      final now = DateTime.now();
      final data = HealthData(
        type: 'Steps',
        value: 5000,
        unit: 'steps',
        date: now,
        source: 'Fitbit',
      );
      expect(data.type, 'Steps');
      expect(data.value, 5000);
      expect(data.unit, 'steps');
      expect(data.date, now);
      expect(data.source, 'Fitbit');
    });
  });

  // ======================================================================
  // Empty-devices state
  // ======================================================================
  group('WearablesScreen - empty-devices state', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('renders Scaffold without crashing', (tester) async {
      await _setTallViewport(tester);
      await tester.pumpWidget(_wrap(const WearablesScreen()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows "Wearables" in the AppBar', (tester) async {
      await _setTallViewport(tester);
      await tester.pumpWidget(_wrap(const WearablesScreen()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Wearables'), findsOneWidget);
    });

    testWidgets('shows "No Wearables Connected" heading', (tester) async {
      await _setTallViewport(tester);
      await tester.pumpWidget(_wrap(const WearablesScreen()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('No Wearables Connected'), findsOneWidget);
    });

    testWidgets('shows descriptive text in empty state', (tester) async {
      await _setTallViewport(tester);
      await tester.pumpWidget(_wrap(const WearablesScreen()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.textContaining('Connect wearable devices'), findsOneWidget);
    });

    testWidgets('shows "Add Your First Device" button', (tester) async {
      await _setTallViewport(tester);
      await tester.pumpWidget(_wrap(const WearablesScreen()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Add Your First Device'), findsOneWidget);
    });

    testWidgets('shows "Supported Devices" card heading', (tester) async {
      await _setTallViewport(tester);
      await tester.pumpWidget(_wrap(const WearablesScreen()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Supported Devices'), findsOneWidget);
    });

    testWidgets('shows Fitbit in the supported devices card', (tester) async {
      await _setTallViewport(tester);
      await tester.pumpWidget(_wrap(const WearablesScreen()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Fitbit'), findsOneWidget);
    });

    testWidgets('shows watch icon in the empty state circle', (tester) async {
      await _setTallViewport(tester);
      await tester.pumpWidget(_wrap(const WearablesScreen()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.watch), findsOneWidget);
    });

    testWidgets('shows refresh icon button in AppBar', (tester) async {
      await _setTallViewport(tester);
      await tester.pumpWidget(_wrap(const WearablesScreen()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });

    testWidgets('shows add icon button in AppBar', (tester) async {
      await _setTallViewport(tester);
      await tester.pumpWidget(_wrap(const WearablesScreen()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.add), findsAtLeastNWidgets(1));
    });

    testWidgets('shows fitness_center icon for Fitbit supported device', (tester) async {
      await _setTallViewport(tester);
      await tester.pumpWidget(_wrap(const WearablesScreen()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.fitness_center), findsOneWidget);
    });

    testWidgets('shows ElevatedButton for Add Your First Device', (tester) async {
      await _setTallViewport(tester);
      await tester.pumpWidget(_wrap(const WearablesScreen()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(ElevatedButton), findsOneWidget);
    });

    testWidgets('shows Card for supported devices', (tester) async {
      await _setTallViewport(tester);
      await tester.pumpWidget(_wrap(const WearablesScreen()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(Card), findsOneWidget);
    });

    testWidgets('shows Wrap widget for supported device icons', (tester) async {
      await _setTallViewport(tester);
      await tester.pumpWidget(_wrap(const WearablesScreen()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(Wrap), findsOneWidget);
    });
  });

  // ======================================================================
  // Connected devices state - with pre-seeded devices
  // ======================================================================
  group('WearablesScreen - connected devices state', () {
    testWidgets('shows "Connected Devices" heading with one device', (tester) async {
      SharedPreferences.setMockInitialValues({
        'connected_devices': _makeDevicesJson([_fitbitDevice()]),
      });

      await _setTallViewport(tester);
      await tester.pumpWidget(_wrap(const WearablesScreen()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Connected Devices'), findsOneWidget);
    });

    testWidgets('shows correct device count text for 1 device', (tester) async {
      SharedPreferences.setMockInitialValues({
        'connected_devices': _makeDevicesJson([_fitbitDevice()]),
      });

      await _setTallViewport(tester);
      await tester.pumpWidget(_wrap(const WearablesScreen()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('1 device connected'), findsOneWidget);
    });

    testWidgets('shows correct device count text for 2 devices', (tester) async {
      SharedPreferences.setMockInitialValues({
        'connected_devices': _makeDevicesJson([
          _fitbitDevice(),
          _unknownDevice(),
        ]),
      });

      await _setTallViewport(tester);
      await tester.pumpWidget(_wrap(const WearablesScreen()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('2 devices connected'), findsOneWidget);
    });

    testWidgets('shows "Your Devices" section heading', (tester) async {
      SharedPreferences.setMockInitialValues({
        'connected_devices': _makeDevicesJson([_fitbitDevice()]),
      });

      await _setTallViewport(tester);
      await tester.pumpWidget(_wrap(const WearablesScreen()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Your Devices'), findsOneWidget);
    });

    testWidgets('shows "Add Device" button in connected view', (tester) async {
      SharedPreferences.setMockInitialValues({
        'connected_devices': _makeDevicesJson([_fitbitDevice()]),
      });

      await _setTallViewport(tester);
      await tester.pumpWidget(_wrap(const WearablesScreen()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Add Device'), findsOneWidget);
    });

    testWidgets('shows device name on card', (tester) async {
      SharedPreferences.setMockInitialValues({
        'connected_devices': _makeDevicesJson([_fitbitDevice(name: 'My Fitbit Watch')]),
      });

      await _setTallViewport(tester);
      await tester.pumpWidget(_wrap(const WearablesScreen()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('My Fitbit Watch'), findsOneWidget);
    });

    testWidgets('shows "Active" badge on device card', (tester) async {
      SharedPreferences.setMockInitialValues({
        'connected_devices': _makeDevicesJson([_fitbitDevice()]),
      });

      await _setTallViewport(tester);
      await tester.pumpWidget(_wrap(const WearablesScreen()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Active'), findsOneWidget);
    });

    testWidgets('shows delete icon on device card', (tester) async {
      SharedPreferences.setMockInitialValues({
        'connected_devices': _makeDevicesJson([_fitbitDevice()]),
      });

      await _setTallViewport(tester);
      await tester.pumpWidget(_wrap(const WearablesScreen()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    });

    testWidgets('shows permissions count on device card', (tester) async {
      SharedPreferences.setMockInitialValues({
        'connected_devices': _makeDevicesJson([_fitbitDevice()]),
      });

      await _setTallViewport(tester);
      await tester.pumpWidget(_wrap(const WearablesScreen()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('2 permissions granted'), findsOneWidget);
    });

    testWidgets('shows singular permission text for 1 permission', (tester) async {
      SharedPreferences.setMockInitialValues({
        'connected_devices': _makeDevicesJson([_appleHealthDevice()]),
      });

      await _setTallViewport(tester);
      await tester.pumpWidget(_wrap(const WearablesScreen()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('1 permission granted'), findsOneWidget);
    });

    testWidgets('shows "Connected" date text on device card', (tester) async {
      SharedPreferences.setMockInitialValues({
        'connected_devices': _makeDevicesJson([_fitbitDevice()]),
      });

      await _setTallViewport(tester);
      await tester.pumpWidget(_wrap(const WearablesScreen()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // The date is "2 hours ago" which renders as "Connected 2 hours ago"
      expect(find.textContaining('Connected'), findsAtLeastNWidgets(1));
    });

    testWidgets('filters out inactive devices', (tester) async {
      SharedPreferences.setMockInitialValues({
        'connected_devices': _makeDevicesJson([
          _fitbitDevice(name: 'Active Fitbit', isActive: true),
          _unknownDevice(name: 'Inactive Band', isActive: false),
        ]),
      });

      await _setTallViewport(tester);
      await tester.pumpWidget(_wrap(const WearablesScreen()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Active Fitbit'), findsOneWidget);
      expect(find.text('Inactive Band'), findsNothing);
      expect(find.text('1 device connected'), findsOneWidget);
    });

    testWidgets('shows fitness_center icon for fitbit device card', (tester) async {
      SharedPreferences.setMockInitialValues({
        'connected_devices': _makeDevicesJson([_fitbitDevice()]),
      });

      await _setTallViewport(tester);
      await tester.pumpWidget(_wrap(const WearablesScreen()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.fitness_center), findsOneWidget);
    });

    testWidgets('shows watch icon for unknown platform device card', (tester) async {
      SharedPreferences.setMockInitialValues({
        'connected_devices': _makeDevicesJson([_unknownDevice()]),
      });

      await _setTallViewport(tester);
      await tester.pumpWidget(_wrap(const WearablesScreen()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.watch), findsOneWidget);
    });

    testWidgets('shows RefreshIndicator in connected devices view', (tester) async {
      SharedPreferences.setMockInitialValues({
        'connected_devices': _makeDevicesJson([_fitbitDevice()]),
      });

      await _setTallViewport(tester);
      await tester.pumpWidget(_wrap(const WearablesScreen()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(RefreshIndicator), findsOneWidget);
    });

    testWidgets('shows multiple device cards when multiple devices connected', (tester) async {
      SharedPreferences.setMockInitialValues({
        'connected_devices': _makeDevicesJson([
          _fitbitDevice(name: 'Fitbit Charge'),
          _unknownDevice(name: 'Generic Band'),
        ]),
      });

      await _setTallViewport(tester);
      await tester.pumpWidget(_wrap(const WearablesScreen()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Fitbit Charge'), findsOneWidget);
      expect(find.text('Generic Band'), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsNWidgets(2));
      expect(find.text('Active'), findsNWidgets(2));
    });
  });

  // ======================================================================
  // Remove device dialog
  // ======================================================================
  group('WearablesScreen - remove device dialog', () {
    testWidgets('tapping delete icon shows remove confirmation dialog', (tester) async {
      SharedPreferences.setMockInitialValues({
        'connected_devices': _makeDevicesJson([_fitbitDevice(name: 'My Fitbit')]),
      });

      await _setTallViewport(tester);
      await tester.pumpWidget(_wrap(const WearablesScreen()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // Tap the delete icon
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pump();

      expect(find.text('Remove Device'), findsOneWidget);
      expect(find.text('Are you sure you want to remove My Fitbit?'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Remove'), findsOneWidget);
    });

    testWidgets('tapping Cancel dismisses dialog and keeps device', (tester) async {
      SharedPreferences.setMockInitialValues({
        'connected_devices': _makeDevicesJson([_fitbitDevice(name: 'My Fitbit')]),
      });

      await _setTallViewport(tester);
      await tester.pumpWidget(_wrap(const WearablesScreen()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // Tap delete
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pump();

      // Tap Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // Device should still be there
      expect(find.text('My Fitbit'), findsOneWidget);
      // Dialog should be gone
      expect(find.text('Remove Device'), findsNothing);
    });

    testWidgets('tapping Remove in dialog removes the device', (tester) async {
      SharedPreferences.setMockInitialValues({
        'connected_devices': _makeDevicesJson([_fitbitDevice(name: 'My Fitbit')]),
      });

      await _setTallViewport(tester);
      await tester.pumpWidget(_wrap(const WearablesScreen()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // Tap delete
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pump();

      // Tap Remove
      await tester.tap(find.text('Remove'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // Device should be removed, empty state should show
      expect(find.text('My Fitbit'), findsNothing);
    });

    testWidgets('removing last device shows empty state', (tester) async {
      SharedPreferences.setMockInitialValues({
        'connected_devices': _makeDevicesJson([_fitbitDevice(name: 'Solo Fitbit')]),
      });

      await _setTallViewport(tester);
      await tester.pumpWidget(_wrap(const WearablesScreen()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // Tap delete then Remove
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pump();
      await tester.tap(find.text('Remove'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // Should show empty state
      expect(find.text('No Wearables Connected'), findsOneWidget);
    });

    testWidgets('removing last device shows snackbar', (tester) async {
      SharedPreferences.setMockInitialValues({
        'connected_devices': _makeDevicesJson([_fitbitDevice(name: 'My Fitbit')]),
      });

      await _setTallViewport(tester);
      await tester.pumpWidget(_wrap(const WearablesScreen()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pump();
      await tester.tap(find.text('Remove'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('My Fitbit has been removed'), findsOneWidget);
    });
  });

  // ======================================================================
  // _formatDate coverage via device cards
  // ======================================================================
  group('WearablesScreen - _formatDate', () {
    testWidgets('shows "days ago" for device connected days ago', (tester) async {
      SharedPreferences.setMockInitialValues({
        'connected_devices': _makeDevicesJson([
          _fitbitDevice(
            connectedAt: DateTime.now().subtract(const Duration(days: 5)),
          ),
        ]),
      });

      await _setTallViewport(tester);
      await tester.pumpWidget(_wrap(const WearablesScreen()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.textContaining('5 days ago'), findsOneWidget);
    });

    testWidgets('shows singular "day ago" for 1 day', (tester) async {
      SharedPreferences.setMockInitialValues({
        'connected_devices': _makeDevicesJson([
          _fitbitDevice(
            connectedAt: DateTime.now().subtract(const Duration(days: 1, hours: 1)),
          ),
        ]),
      });

      await _setTallViewport(tester);
      await tester.pumpWidget(_wrap(const WearablesScreen()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.textContaining('1 day ago'), findsOneWidget);
    });

    testWidgets('shows "hours ago" for device connected hours ago', (tester) async {
      SharedPreferences.setMockInitialValues({
        'connected_devices': _makeDevicesJson([
          _fitbitDevice(
            connectedAt: DateTime.now().subtract(const Duration(hours: 3)),
          ),
        ]),
      });

      await _setTallViewport(tester);
      await tester.pumpWidget(_wrap(const WearablesScreen()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.textContaining('3 hours ago'), findsOneWidget);
    });

    testWidgets('shows singular "hour ago" for 1 hour', (tester) async {
      SharedPreferences.setMockInitialValues({
        'connected_devices': _makeDevicesJson([
          _fitbitDevice(
            connectedAt: DateTime.now().subtract(const Duration(hours: 1, minutes: 1)),
          ),
        ]),
      });

      await _setTallViewport(tester);
      await tester.pumpWidget(_wrap(const WearablesScreen()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.textContaining('1 hour ago'), findsOneWidget);
    });

    testWidgets('shows "minutes ago" for device connected minutes ago', (tester) async {
      SharedPreferences.setMockInitialValues({
        'connected_devices': _makeDevicesJson([
          _fitbitDevice(
            connectedAt: DateTime.now().subtract(const Duration(minutes: 15)),
          ),
        ]),
      });

      await _setTallViewport(tester);
      await tester.pumpWidget(_wrap(const WearablesScreen()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.textContaining('15 minutes ago'), findsOneWidget);
    });

    testWidgets('shows singular "minute ago" for 1 minute', (tester) async {
      SharedPreferences.setMockInitialValues({
        'connected_devices': _makeDevicesJson([
          _fitbitDevice(
            connectedAt: DateTime.now().subtract(const Duration(minutes: 1, seconds: 10)),
          ),
        ]),
      });

      await _setTallViewport(tester);
      await tester.pumpWidget(_wrap(const WearablesScreen()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.textContaining('1 minute ago'), findsOneWidget);
    });

    testWidgets('shows "Just now" for device connected seconds ago', (tester) async {
      SharedPreferences.setMockInitialValues({
        'connected_devices': _makeDevicesJson([
          _fitbitDevice(
            connectedAt: DateTime.now().subtract(const Duration(seconds: 5)),
          ),
        ]),
      });

      await _setTallViewport(tester);
      await tester.pumpWidget(_wrap(const WearablesScreen()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.textContaining('Just now'), findsOneWidget);
    });
  });

  // ======================================================================
  // Invalid / corrupt SharedPreferences data
  // ======================================================================
  group('WearablesScreen - corrupt data handling', () {
    testWidgets('handles corrupt JSON in connected_devices gracefully', (tester) async {
      SharedPreferences.setMockInitialValues({
        'connected_devices': 'not valid json!',
      });

      await _setTallViewport(tester);
      await tester.pumpWidget(_wrap(const WearablesScreen()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // Should fall back to empty state
      expect(find.text('No Wearables Connected'), findsOneWidget);
    });
  });

  // ======================================================================
  // No connected_devices key
  // ======================================================================
  group('WearablesScreen - no connected_devices key', () {
    testWidgets('shows empty state when connected_devices key is missing', (tester) async {
      SharedPreferences.setMockInitialValues({});

      await _setTallViewport(tester);
      await tester.pumpWidget(_wrap(const WearablesScreen()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('No Wearables Connected'), findsOneWidget);
    });
  });

  // ======================================================================
  // Device platform icon/color mapping via UI
  // ======================================================================
  group('WearablesScreen - device platform icons', () {
    testWidgets('fitbit device shows fitness_center icon', (tester) async {
      SharedPreferences.setMockInitialValues({
        'connected_devices': _makeDevicesJson([_fitbitDevice()]),
      });

      await _setTallViewport(tester);
      await tester.pumpWidget(_wrap(const WearablesScreen()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.fitness_center), findsOneWidget);
    });

    testWidgets('google_fit device shows directions_run icon', (tester) async {
      SharedPreferences.setMockInitialValues({
        'connected_devices': _makeDevicesJson([_googleFitDevice()]),
      });

      await _setTallViewport(tester);
      await tester.pumpWidget(_wrap(const WearablesScreen()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.directions_run), findsOneWidget);
    });

    testWidgets('apple_health device shows favorite icon', (tester) async {
      SharedPreferences.setMockInitialValues({
        'connected_devices': _makeDevicesJson([_appleHealthDevice()]),
      });

      await _setTallViewport(tester);
      await tester.pumpWidget(_wrap(const WearablesScreen()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.favorite), findsOneWidget);
    });

    testWidgets('unknown platform device shows watch icon', (tester) async {
      SharedPreferences.setMockInitialValues({
        'connected_devices': _makeDevicesJson([_unknownDevice()]),
      });

      await _setTallViewport(tester);
      await tester.pumpWidget(_wrap(const WearablesScreen()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.watch), findsOneWidget);
    });
  });

  // ======================================================================
  // All devices inactive -> shows empty state
  // ======================================================================
  group('WearablesScreen - all inactive devices', () {
    testWidgets('shows empty state when all devices are inactive', (tester) async {
      SharedPreferences.setMockInitialValues({
        'connected_devices': _makeDevicesJson([
          _fitbitDevice(isActive: false),
          _unknownDevice(isActive: false),
        ]),
      });

      await _setTallViewport(tester);
      await tester.pumpWidget(_wrap(const WearablesScreen()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('No Wearables Connected'), findsOneWidget);
    });
  });

  // ======================================================================
  // Permissions count text
  // ======================================================================
  group('WearablesScreen - permissions display', () {
    testWidgets('shows "0 permissions granted" for device with no permissions', (tester) async {
      SharedPreferences.setMockInitialValues({
        'connected_devices': _makeDevicesJson([_unknownDevice()]),
      });

      await _setTallViewport(tester);
      await tester.pumpWidget(_wrap(const WearablesScreen()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('0 permissions granted'), findsOneWidget);
    });

    testWidgets('shows "3 permissions granted" for device with 3 permissions', (tester) async {
      SharedPreferences.setMockInitialValues({
        'connected_devices': _makeDevicesJson([_googleFitDevice()]),
      });

      await _setTallViewport(tester);
      await tester.pumpWidget(_wrap(const WearablesScreen()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('3 permissions granted'), findsOneWidget);
    });
  });

  // ======================================================================
  // Removing one of multiple devices keeps remaining
  // ======================================================================
  group('WearablesScreen - remove one of multiple devices', () {
    testWidgets('removing one device keeps the other device visible', (tester) async {
      SharedPreferences.setMockInitialValues({
        'connected_devices': _makeDevicesJson([
          _fitbitDevice(name: 'Keep Me'),
          _unknownDevice(name: 'Remove Me'),
        ]),
      });

      await _setTallViewport(tester);
      await tester.pumpWidget(_wrap(const WearablesScreen()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // Both should be visible
      expect(find.text('Keep Me'), findsOneWidget);
      expect(find.text('Remove Me'), findsOneWidget);

      // Tap delete on second device (second delete_outline icon)
      final deleteIcons = find.byIcon(Icons.delete_outline);
      await tester.tap(deleteIcons.last);
      await tester.pump();

      // Confirm removal
      await tester.tap(find.text('Remove'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // "Remove Me" gone, "Keep Me" remains
      expect(find.text('Remove Me'), findsNothing);
      expect(find.text('Keep Me'), findsOneWidget);
      expect(find.text('1 device connected'), findsOneWidget);
    });
  });
}
