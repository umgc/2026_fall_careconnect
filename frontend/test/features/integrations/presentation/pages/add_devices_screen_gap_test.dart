// Gap test for AddDeviceScreen
// (lib/features/integrations/presentation/pages/add_devices_screen.dart): the
// in-progress "Connecting to ..." state while the health authorization prompt
// is still open, followed by the successful completion and the saved device.
//
// The health plugin, device info and secure storage channels are faked, so no
// platform services or network are used.

import 'dart:async';
import 'dart:convert';

import 'package:care_connect_app/features/integrations/presentation/pages/add_devices_screen.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _secureStorage =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
const _connectivity = MethodChannel('dev.fluttercommunity.plus/connectivity');
const _connectivityStatus =
    MethodChannel('dev.fluttercommunity.plus/connectivity_status');
const _health = MethodChannel('flutter_health');
const _deviceInfo = MethodChannel('dev.fluttercommunity.plus/device_info');

const _iosInfo = <String, dynamic>{
  'name': 'Test Phone',
  'systemName': 'iOS',
  'systemVersion': '17.0',
  'model': 'iPhone',
  'modelName': 'iPhone 15',
  'localizedModel': 'iPhone',
  'identifierForVendor': 'vendor-1',
  'freeDiskSize': 1,
  'totalDiskSize': 2,
  'isPhysicalDevice': false,
  'physicalRamSize': 1,
  'availableRamSize': 1,
  'isiOSAppOnMac': false,
  'isiOSAppOnVision': false,
  'utsname': {
    'sysname': 'Darwin',
    'nodename': 'n',
    'release': 'r',
    'version': 'v',
    'machine': 'm',
  },
};

void _mock(MethodChannel c, Future<Object?> Function(MethodCall) h) =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(c, h);

void main() {
  late Completer<bool> authorization;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    authorization = Completer<bool>();
    _mock(_secureStorage, (call) async {
      if (call.method == 'readAll') return <String, String>{};
      if (call.method == 'containsKey') return false;
      return null;
    });
    _mock(_connectivity,
        (call) async => call.method == 'check' ? ['wifi'] : null);
    _mock(_connectivityStatus, (call) async => null);
    _mock(_deviceInfo, (call) async => _iosInfo);
    _mock(_health, (call) async {
      switch (call.method) {
        case 'requestAuthorization':
          return authorization.future;
        case 'hasPermissions':
          return true;
        case 'getData':
          return <Object>[];
      }
      return null;
    });
  });

  tearDown(() {
    for (final c in [
      _secureStorage,
      _connectivity,
      _connectivityStatus,
      _health,
      _deviceInfo
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(c, null);
    }
  });

  testWidgets('shows progress while authorizing, then saves the device',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<UserProvider>.value(
        value: UserProvider()
          ..setUser(UserSession(
            id: 2,
            email: 'cg@example.com',
            role: 'CAREGIVER',
            token: 'tok',
          )),
        child: const MaterialApp(home: AddDeviceScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('Fitbit'));
    await tester.pump(const Duration(milliseconds: 100));

    // The authorization prompt has not answered yet.
    expect(find.text('Connecting to Fitbit...'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Connection Failed'), findsNothing);

    authorization.complete(true);
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('Connecting to Fitbit...'), findsNothing);
    expect(find.text('Continue'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    final saved = jsonDecode(prefs.getString('connected_devices')!) as List;
    expect(saved.single['platform'], 'fitbit');

    ScaffoldMessenger.of(tester.element(find.byType(AddDeviceScreen)))
        .removeCurrentSnackBar();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Successfully Connected!'), findsOneWidget);
  });
}
