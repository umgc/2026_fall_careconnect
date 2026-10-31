// Additional coverage for WearablesScreen
// (lib/features/integrations/presentation/pages/wearables_screen.dart):
// plugin failures, unmapped Apple Health data, short ingest error bodies,
// persisted vitals edge cases, accepted-snapshot metric mapping, loading
// state, compact header layout, device-removal failure and patient-id
// resolution branches. Health plugin, device-info and secure-storage channels
// are faked and the backend is served by a MockClient.

import 'dart:async';
import 'dart:convert';

import 'package:care_connect_app/features/integrations/presentation/pages/add_devices_screen.dart';
import 'package:care_connect_app/features/integrations/presentation/pages/wearables_screen.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:care_connect_app/services/user_role_storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _secureStorage =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
const _connectivity = MethodChannel('dev.fluttercommunity.plus/connectivity');
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

Map<String, dynamic> _device(String platform, {String? id, String? name}) => {
      'id': id ?? '$platform-1',
      'platform': platform,
      'name': name ?? platform,
      'connectedAt': DateTime.now()
          .subtract(const Duration(days: 2))
          .toIso8601String(),
      'permissions': ['steps'],
      'isActive': true,
    };

class _Fake {
  bool deviceInfoFails = false;
  bool deleteFails = false;

  /// Value reported for each plugin data point (0 => unmappable).
  num pointValue = 75;
  bool healthReturnsData = true;
  int ingestStatus = 201;
  String? ingestRawBody;
  Map<String, dynamic> ingestBody = {
    'data': {'acceptedCount': 1, 'rejectedCount': 0, 'acceptedReadings': []},
  };
  int vitalsStatus = 200;
  List<Map<String, dynamic>> vitals = [];
  Completer<void>? vitalsGate;
  int caregiverPatientsStatus = 200;
  Object caregiverPatientsBody = [
    {
      'patient': {'id': '55'},
    },
  ];
  String? sessionJson;
  final List<String> calls = <String>[];

  Future<http.Response> handle(http.Request r) async {
    final p = r.url.path;
    calls.add('${r.method} $p');
    if (p.endsWith('/analytics/vitals/ingest')) {
      return http.Response(
          ingestRawBody ?? jsonEncode(ingestBody), ingestStatus);
    }
    if (p.endsWith('/analytics/vitals')) {
      if (vitalsGate != null) await vitalsGate!.future;
      return http.Response(jsonEncode({'data': vitals}), vitalsStatus);
    }
    if (p.contains('/caregivers/') && p.endsWith('/patients')) {
      return http.Response(
          jsonEncode(caregiverPatientsBody), caregiverPatientsStatus);
    }
    return http.Response('{}', 404);
  }
}

late _Fake _f;

void _mock(MethodChannel c, Future<Object?> Function(MethodCall) h) =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(c, h);

Future<void> _setPrefs({
  required List<Map<String, dynamic>> devices,
  int? patientId = 42,
}) async {
  SharedPreferences.setMockInitialValues({
    'connected_devices': jsonEncode(devices),
  });
  await UserRoleStorageService.instance.updatePatientId(patientId);
}

Widget _app(Widget child) => ChangeNotifierProvider<UserProvider>.value(
      value: UserProvider()
        ..setUser(UserSession(
          id: 2,
          email: 'cg2@example.com',
          role: 'CAREGIVER',
          token: 'tok2',
        )),
      child: MaterialApp(home: child),
    );

Future<void> _settle(WidgetTester tester, [int rounds = 8]) async {
  for (var i = 0; i < rounds; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _pump(WidgetTester tester,
    {Size size = const Size(1000, 3000)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await http.runWithClient(() async {
    await tester.pumpWidget(_app(const WearablesScreen()));
    await _settle(tester);
  }, () => MockClient(_f.handle));
}

Map<String, dynamic> _accepted(String metric, num value, String at) => {
      'metric': metric,
      'metricValue': value,
      'recordedAt': at,
      'source': 'google_fit',
    };

void main() {
  setUp(() {
    _f = _Fake();
    _mock(_secureStorage, (call) async {
      final key = (call.arguments as Map?)?['key'];
      if (call.method == 'read' && key == 'user_session') return _f.sessionJson;
      if (call.method == 'readAll') return <String, String>{};
      if (call.method == 'containsKey') return false;
      if (call.method == 'delete' &&
          _f.deleteFails &&
          key.toString().endsWith('_access_token')) {
        throw PlatformException(code: 'denied', message: 'delete failed');
      }
      return null;
    });
    _mock(_connectivity,
        (call) async => call.method == 'check' ? ['wifi'] : null);
    _mock(_deviceInfo, (call) async {
      if (_f.deviceInfoFails) {
        throw PlatformException(code: 'nope', message: 'no device info');
      }
      return _iosInfo;
    });
    _mock(_health, (call) async {
      switch (call.method) {
        case 'requestAuthorization':
          return true;
        case 'hasPermissions':
          return true;
        case 'getData':
          if (!_f.healthReturnsData) return <Object>[];
          final now = DateTime.now().millisecondsSinceEpoch;
          return [
            {
              'uuid': 'u-${(call.arguments as Map)['dataTypeKey']}',
              'value': _f.pointValue,
              'date_from': now - 60000,
              'date_to': now,
              'source_id': 'src',
              'source_name': 'Source',
            },
          ];
      }
      return null;
    });
    ApiService.debugSetHttpClient(MockClient(_f.handle));
  });

  tearDown(() {
    for (final c in [_secureStorage, _connectivity, _health, _deviceInfo]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(c, null);
    }
    ApiService.debugResetHttpClient();
  });

  testWidgets('fitbit plugin fallback failure is tolerated', (tester) async {
    _f.deviceInfoFails = true;
    await _setPrefs(devices: [_device('fitbit', name: 'My Fitbit')]);
    await _pump(tester);

    // No readings collected -> nothing ingested, empty-state message shown.
    expect(_f.calls, isNot(contains('POST /v1/api/analytics/vitals/ingest')));
    expect(find.text('No synced data yet'), findsOneWidget);
    expect(find.textContaining('No Apple Health samples were collected'),
        findsOneWidget);
  });

  testWidgets('health connect collection failure is tolerated',
      (tester) async {
    _f.deviceInfoFails = true;
    await _setPrefs(devices: [_device('google_fit')]);
    await _pump(tester);
    expect(_f.calls, contains('GET /v1/api/analytics/vitals'));
    expect(find.text('No synced data yet'), findsOneWidget);
  });

  testWidgets('apple health data that cannot be mapped explains the state',
      (tester) async {
    _f.pointValue = 0;
    // Persisted vitals exist so the status message is not overwritten.
    _f.vitals = [
      {'timestamp': '2026-10-02T09:00:00Z', 'heartRate': 61},
    ];
    await _setPrefs(devices: [_device('apple_health', name: 'Apple Health')]);
    await _pump(tester);
    expect(find.text('61'), findsOneWidget);
  });

  testWidgets('clean sync with persisted vitals shows metric cards',
      (tester) async {
    _f.vitals = [
      {'timestamp': '2026-10-02T09:00:00Z', 'heartRate': 66, 'spo2': 98},
    ];
    await _setPrefs(devices: [_device('google_fit')]);
    await _pump(tester);
    expect(_f.calls, contains('POST /v1/api/analytics/vitals/ingest'));
    expect(find.text('Health Metrics'), findsOneWidget);
    expect(find.text('66'), findsOneWidget);
    expect(find.text('Synchronization failed'), findsNothing);
  });

  testWidgets('short ingest error body surfaces sync failure',
      (tester) async {
    _f.ingestStatus = 400;
    _f.ingestRawBody = 'bad request';
    await _setPrefs(devices: [_device('google_fit')]);
    await _pump(tester);
    expect(find.text('Synchronization failed'), findsOneWidget);
    expect(find.textContaining('body=bad request'), findsOneWidget);
  });

  testWidgets('persisted vitals with only zero values show empty message',
      (tester) async {
    _f.healthReturnsData = false;
    _f.vitals = [
      {'timestamp': '2026-10-02T09:00:00Z', 'heartRate': 0},
      {'timestamp': 'bad'},
      {'timestamp': '2026-10-01T09:00:00Z'},
      {'note': 'no timestamp'},
    ];
    await _setPrefs(devices: [_device('google_fit')]);
    await _pump(tester);
    expect(find.text('No synced data yet'), findsOneWidget);
    expect(find.textContaining('No Apple Health samples were collected'),
        findsOneWidget);
  });

  testWidgets('accepted ingestion snapshot maps every backend metric',
      (tester) async {
    _f.ingestBody = {
      'data': {
        'acceptedCount': 6,
        'rejectedCount': 0,
        'acceptedReadings': [
          _accepted('STEPS', 5000, '2026-10-02T10:00:00Z'),
          _accepted('STEPS', 1234, '2026-10-01T10:00:00Z'),
          _accepted('SPO2', 98, '2026-10-02T10:00:00Z'),
          _accepted('BLOOD_PRESSURE_SYS', 121, '2026-10-02T10:00:00Z'),
          _accepted('BLOOD_PRESSURE_DIA', 79, '2026-10-02T10:00:00Z'),
          _accepted('WEIGHT', 70, '2026-10-02T10:00:00Z'),
        ],
      },
    };
    await _setPrefs(devices: [_device('google_fit')]);
    await _pump(tester);

    expect(find.text('Health Metrics'), findsOneWidget);
    // The newer STEPS reading wins over the older one.
    expect(find.text('5000'), findsOneWidget);
    expect(find.text('1234'), findsNothing);
    expect(find.text('121'), findsOneWidget);
    expect(find.text('79'), findsOneWidget);
  });

  testWidgets('shows a progress indicator while vitals are loading',
      (tester) async {
    _f.healthReturnsData = false;
    _f.vitalsGate = Completer<void>();
    await _setPrefs(devices: [_device('google_fit')]);
    await _pump(tester);

    expect(find.byType(CircularProgressIndicator), findsWidgets);

    await http.runWithClient(() async {
      _f.vitalsGate!.complete();
      await _settle(tester);
    }, () => MockClient(_f.handle));
    expect(find.text('No synced data yet'), findsOneWidget);
  });

  testWidgets('compact header layout on narrow screens opens add device',
      (tester) async {
    _f.healthReturnsData = false;
    await _setPrefs(devices: [_device('google_fit', name: 'Health Connect')]);
    await _pump(tester, size: const Size(400, 3000));

    expect(find.text('Connected Devices'), findsOneWidget);
    expect(find.text('1 device connected'), findsOneWidget);

    await tester.tap(find.text('Add Device'));
    await tester.pumpAndSettle();
    expect(find.byType(AddDeviceScreen), findsOneWidget);
  });

  testWidgets('device removal failure shows error snackbar', (tester) async {
    _f.healthReturnsData = false;
    _f.deleteFails = true;
    await _setPrefs(devices: [_device('google_fit', name: 'Health Connect')]);
    await _pump(tester);

    await tester.tap(find.byIcon(Icons.delete_outline).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await _settle(tester);

    expect(find.text('Failed to remove device'), findsOneWidget);
  });

  testWidgets('session patient id is used when no patient is selected',
      (tester) async {
    _f.healthReturnsData = false;
    _f.sessionJson = jsonEncode({
      'id': 3,
      'email': 'p@example.com',
      'role': 'PATIENT',
      'patientId': 77,
    });
    await _setPrefs(devices: [_device('google_fit')], patientId: null);
    await _pump(tester);
    expect(find.textContaining('Select a patient first'), findsNothing);
    expect(_f.calls, contains('GET /v1/api/analytics/vitals'));
  });

  testWidgets('caregiver linked patient id given as a string is parsed',
      (tester) async {
    _f.healthReturnsData = false;
    _f.sessionJson = jsonEncode({
      'id': 2,
      'email': 'cg2@example.com',
      'role': 'CAREGIVER',
      'caregiverId': 7,
    });
    await _setPrefs(devices: [_device('google_fit')], patientId: null);
    await _pump(tester);
    expect(_f.calls, contains('GET /v1/api/caregivers/7/patients'));
    expect(await UserRoleStorageService.instance.getPatientId(), 55);
  });

  testWidgets('caregiver patients lookup failure asks to select a patient',
      (tester) async {
    _f.caregiverPatientsStatus = 500;
    _f.sessionJson = jsonEncode({
      'id': 2,
      'email': 'cg2@example.com',
      'role': 'CAREGIVER',
      'caregiverId': 7,
    });
    await _setPrefs(devices: [_device('google_fit')], patientId: null);
    await _pump(tester);
    expect(find.textContaining('Select a patient first'), findsOneWidget);
  });

  testWidgets('caregiver patients non-list response asks to select a patient',
      (tester) async {
    _f.caregiverPatientsBody = {'unexpected': true};
    _f.sessionJson = jsonEncode({
      'id': 2,
      'email': 'cg2@example.com',
      'role': 'CAREGIVER',
      'caregiverId': 7,
    });
    await _setPrefs(devices: [_device('google_fit')], patientId: null);
    await _pump(tester);
    expect(find.textContaining('Select a patient first'), findsOneWidget);
  });
}
