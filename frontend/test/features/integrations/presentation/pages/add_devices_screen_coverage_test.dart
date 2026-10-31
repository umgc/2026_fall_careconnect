// Additional coverage for AddDeviceScreen: drives the Fitbit -> Google Health
// (Health Connect) connection flow by mocking the `flutter_health`,
// device_info_plus and flutter_secure_storage method channels.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/features/integrations/presentation/pages/add_devices_screen.dart';
import 'package:care_connect_app/providers/user_provider.dart';

const _healthChannel = MethodChannel('flutter_health');
const _deviceInfoChannel =
    MethodChannel('dev.fluttercommunity.plus/device_info');
const _secureStorageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

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

Map<String, dynamic> _fakeDeviceInfo() => {
      'name': 'Test Device',
      'systemName': 'iOS',
      'systemVersion': '17.0',
      'model': 'iPhone',
      'modelName': 'iPhone 15',
      'localizedModel': 'iPhone',
      'identifierForVendor': 'vendor-id',
      'freeDiskSize': 1,
      'totalDiskSize': 2,
      'isPhysicalDevice': false,
      'physicalRamSize': 1,
      'availableRamSize': 1,
      'isiOSAppOnMac': false,
      'isiOSAppOnVision': false,
      'utsname': {
        'sysname': 's',
        'nodename': 'n',
        'release': 'r',
        'version': 'v',
        'machine': 'm',
      },
    };

/// Installs channel mocks. [configureOk] controls whether device info
/// resolves; [authorized] / [hasPerms] control flutter_health replies.
List<String> _installMocks({
  bool configureOk = true,
  bool authorized = true,
  bool hasPerms = true,
  Future<bool>? authGate,
  bool getDataThrows = false,
  bool secureStorageThrows = false,
}) {
  final calls = <String>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(_deviceInfoChannel, (call) async {
    if (!configureOk) {
      throw PlatformException(code: 'unavailable', message: 'no device');
    }
    return _fakeDeviceInfo();
  });
  messenger.setMockMethodCallHandler(_healthChannel, (call) async {
    calls.add(call.method);
    switch (call.method) {
      case 'requestAuthorization':
        if (authGate != null) return await authGate;
        return authorized;
      case 'hasPermissions':
        return hasPerms;
      case 'getData':
        if (getDataThrows) {
          throw PlatformException(code: 'boom', message: 'read failed');
        }
        final now = DateTime(2025, 1, 1).millisecondsSinceEpoch;
        return <dynamic>[
          {
            'value': 42,
            'date_from': now,
            'date_to': now,
            'source_id': 'src',
            'source_name': 'Source',
          },
        ];
      default:
        return null;
    }
  });
  messenger.setMockMethodCallHandler(_secureStorageChannel, (call) async {
    calls.add('secure:${call.method}');
    if (secureStorageThrows && call.method == 'write') {
      throw PlatformException(code: 'denied', message: 'no keychain');
    }
    return null;
  });
  return calls;
}

void _clearMocks() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(_deviceInfoChannel, null);
  messenger.setMockMethodCallHandler(_healthChannel, null);
  messenger.setMockMethodCallHandler(_secureStorageChannel, null);
}

void _tallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(_clearMocks);

  testWidgets('Fitbit connects via Health Connect and reaches Complete step',
      (tester) async {
    final calls = _installMocks();
    _tallView(tester);
    await tester.pumpWidget(_wrap(const AddDeviceScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Fitbit'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(calls, contains('requestAuthorization'));
    expect(calls, contains('hasPermissions'));
    expect(calls, contains('secure:write'));
    expect(find.text('Connected to Fitbit!'), findsOneWidget);
    expect(find.textContaining('successfully connected with 4 permissions'),
        findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('connected_devices'), contains('"fitbit"'));

    // The success SnackBar overlaps the bottom button, so invoke it directly.
    tester
        .widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Continue'))
        .onPressed!();
    await tester.pumpAndSettle();
    expect(find.text('Successfully Connected!'), findsOneWidget);
  });

  testWidgets('shows connecting indicator while authorization is pending',
      (tester) async {
    final gate = Completer<bool>();
    _installMocks(authGate: gate.future);
    _tallView(tester);
    await tester.pumpWidget(_wrap(const AddDeviceScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Fitbit'));
    await tester.pump();

    expect(find.text('Connecting to Fitbit...'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    gate.complete(true);
    await tester.pumpAndSettle();
    expect(find.text('Connected to Fitbit!'), findsOneWidget);
  });

  testWidgets('authorization denied shows failure and Try Again retries',
      (tester) async {
    final calls = _installMocks(authorized: false);
    _tallView(tester);
    await tester.pumpWidget(_wrap(const AddDeviceScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Fitbit'));
    await tester.pumpAndSettle();

    expect(find.text('Connection Failed'), findsOneWidget);
    expect(find.textContaining('Health authorization was denied'),
        findsOneWidget);

    final before = calls.where((c) => c == 'requestAuthorization').length;
    await tester.tap(find.widgetWithText(ElevatedButton, 'Try Again').last);
    await tester.pumpAndSettle();
    expect(calls.where((c) => c == 'requestAuthorization').length,
        greaterThan(before));
    expect(find.text('Connection Failed'), findsOneWidget);
  });

  testWidgets('missing permissions surfaces not-granted error',
      (tester) async {
    _installMocks(hasPerms: false);
    _tallView(tester);
    await tester.pumpWidget(_wrap(const AddDeviceScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Fitbit'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Health permissions were not granted'),
        findsOneWidget);
  });

  testWidgets('configure failure surfaces Fitbit error', (tester) async {
    _installMocks(configureOk: false);
    _tallView(tester);
    await tester.pumpWidget(_wrap(const AddDeviceScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Fitbit'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Failed to connect to Fitbit'), findsOneWidget);
  });

  testWidgets('invalid stored devices JSON is tolerated', (tester) async {
    SharedPreferences.setMockInitialValues({'connected_devices': 'not json'});
    _tallView(tester);
    await tester.pumpWidget(_wrap(const AddDeviceScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Choose Health Platform'), findsOneWidget);
  });

  testWidgets('already-connected Fitbit tap is a no-op', (tester) async {
    SharedPreferences.setMockInitialValues({
      'connected_devices':
          '[{"id":"fitbit_1","platform":"fitbit","name":"Fitbit","connectedAt":"2025-01-01T00:00:00.000","permissions":["steps"],"isActive":true}]',
    });
    final calls = _installMocks();
    _tallView(tester);
    await tester.pumpWidget(_wrap(const AddDeviceScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Fitbit'));
    await tester.pumpAndSettle();
    expect(calls.where((c) => !c.startsWith('secure:')), isEmpty);
    expect(find.text('Choose Health Platform'), findsOneWidget);
  });

  testWidgets(
      'connection still succeeds when token storage and data fetch fail',
      (tester) async {
    _installMocks(getDataThrows: true, secureStorageThrows: true);
    _tallView(tester);
    await tester.pumpWidget(_wrap(const AddDeviceScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Fitbit'));
    await tester.pumpAndSettle();

    expect(find.text('Connected to Fitbit!'), findsOneWidget);
    expect(find.text('Connection Failed'), findsNothing);
  });
}
