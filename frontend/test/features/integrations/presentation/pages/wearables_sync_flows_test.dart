// Flow tests for WearablesScreen and AddDeviceScreen
// (lib/features/integrations/presentation/pages/) with the health plugin,
// device-info and secure-storage channels faked and the backend served by a
// MockClient: sync of plugin readings into ingest, persisted vitals cards,
// sync error / empty states, caregiver patient auto-resolution, device
// removal, and the add-device connect wizard.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:care_connect_app/features/integrations/presentation/pages/add_devices_screen.dart';
import 'package:care_connect_app/features/integrations/presentation/pages/wearables_screen.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:care_connect_app/services/user_role_storage_service.dart';

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

/// Shared, mutable fake state.
class _Fake {
  bool healthAuthorized = true;
  bool healthHasPermissions = true;
  bool healthReturnsData = true;
  int ingestStatus = 201;
  Map<String, dynamic> ingestBody = {
    'data': {
      'acceptedCount': 0,
      'rejectedCount': 1,
      'acceptedReadings': [
        {
          'metric': 'STEPS',
          'metricValue': 4321,
          'recordedAt': '2026-10-01T10:00:00Z',
          'source': 'google_fit',
        },
        {
          'metric': 'HEART_RATE',
          'metricValue': 70,
          'recordedAt': '2026-10-01T10:00:00Z',
          'source': 'google_fit',
        },
        {'metric': 'UNKNOWN', 'metricValue': 1, 'recordedAt': 'x'},
      ],
    },
  };
  int vitalsStatus = 200;
  List<Map<String, dynamic>> vitals = [];
  String? sessionJson;
  final List<String> calls = <String>[];

  Future<http.Response> handle(http.Request r) async {
    final p = r.url.path;
    calls.add('${r.method} $p');
    if (p.endsWith('/analytics/vitals/ingest')) {
      return http.Response(jsonEncode(ingestBody), ingestStatus);
    }
    if (p.endsWith('/analytics/vitals')) {
      return http.Response(jsonEncode({'data': vitals}), vitalsStatus);
    }
    if (p.contains('/caregivers/') && p.endsWith('/patients')) {
      return http.Response(
        jsonEncode([
          {
            'patient': {'id': 42},
          },
          'skip',
        ]),
        200,
      );
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
  // The storage service caches its SharedPreferences instance, so the
  // patient id is written through it rather than via the mock values.
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

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1000, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await http.runWithClient(() async {
    await tester.pumpWidget(_app(child));
    await _settle(tester);
  }, () => MockClient(_f.handle));
}

Future<void> _withHttp(Future<void> Function() body) =>
    http.runWithClient(body, () => MockClient(_f.handle));

void main() {
  setUp(() {
    _f = _Fake();
    _mock(_secureStorage, (call) async {
      final key = (call.arguments as Map?)?['key'];
      if (call.method == 'read' && key == 'user_session') return _f.sessionJson;
      if (call.method == 'readAll') return <String, String>{};
      if (call.method == 'containsKey') return false;
      return null;
    });
    _mock(_connectivity,
        (call) async => call.method == 'check' ? ['wifi'] : null);
    _mock(_deviceInfo, (call) async => _iosInfo);
    _mock(_health, (call) async {
      switch (call.method) {
        case 'requestAuthorization':
          return _f.healthAuthorized;
        case 'hasPermissions':
          return _f.healthHasPermissions;
        case 'getData':
          if (!_f.healthReturnsData) return <Object>[];
          final now = DateTime.now().millisecondsSinceEpoch;
          return [
            {
              'uuid': 'u-${(call.arguments as Map)['dataTypeKey']}',
              'value': 75,
              'date_from': now - 60000,
              'date_to': now,
              'source_id': 'src',
              'source_name': 'Source',
            },
            {
              'uuid': 'zero-${(call.arguments as Map)['dataTypeKey']}',
              'value': 0,
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

  testWidgets('plugin readings are ingested and the accepted snapshot shown',
      (tester) async {
    await _setPrefs(devices: [_device('google_fit', name: 'Health Connect')]);
    await _pump(tester, const WearablesScreen());

    expect(_f.calls, contains('POST /v1/api/analytics/vitals/ingest'));
    expect(find.text('Health Metrics'), findsOneWidget);
    expect(find.text('4321'), findsOneWidget);
    expect(find.text('Steps'), findsWidgets);
    expect(find.text('Heart Rate'), findsWidgets);
  });

  testWidgets('persisted vitals render health metric cards', (tester) async {
    _f.vitals = [
      {'timestamp': 'not-a-date'},
      {
        'timestamp': '2026-10-01T09:00:00Z',
        'heartRate': 60,
      },
      {
        'timestamp': '2026-10-02T09:00:00Z',
        'heartRate': 72,
        'spo2': 97,
        'systolic': 120,
        'diastolic': 80,
        'weight': 70.5,
      },
    ];
    await _setPrefs(devices: [
      _device('apple_health', name: 'Apple Health'),
      _device('fitbit', name: 'My Fitbit'),
    ]);
    await _pump(tester, const WearablesScreen());

    expect(find.text('Health Metrics'), findsOneWidget);
    expect(find.text('72'), findsOneWidget);
    expect(find.text('120'), findsOneWidget);
    expect(find.text('80'), findsOneWidget);
    expect(find.text('2 devices connected'), findsOneWidget);

    // Pull the refresh action.
    await _withHttp(() async {
      await tester.tap(find.byIcon(Icons.refresh));
      await _settle(tester);
    });
    expect(find.text('Health Metrics'), findsOneWidget);
  });

  testWidgets('empty persisted data with no readings explains the state',
      (tester) async {
    _f.healthReturnsData = false;
    await _setPrefs(devices: [_device('google_fit')]);
    await _pump(tester, const WearablesScreen());
    expect(find.text('No synced data yet'), findsOneWidget);
  });

  testWidgets('denied health access shows the access message',
      (tester) async {
    _f.healthAuthorized = false;
    await _setPrefs(devices: [_device('apple_health')]);
    await _pump(tester, const WearablesScreen());
    expect(find.text('No synced data yet'), findsOneWidget);
  });

  testWidgets('ingest failure shows the synchronization failed card',
      (tester) async {
    _f.ingestStatus = 500;
    _f.ingestBody = {'error': 'x' * 300};
    await _setPrefs(devices: [_device('google_fit')]);
    await _pump(tester, const WearablesScreen());
    expect(find.text('Synchronization failed'), findsOneWidget);
  });

  testWidgets('fitbit-only device falls back to the health plugin',
      (tester) async {
    _f.vitalsStatus = 500;
    await _setPrefs(devices: [_device('fitbit', name: 'My Fitbit')]);
    await _pump(tester, const WearablesScreen());
    expect(_f.calls, contains('POST /v1/api/analytics/vitals/ingest'));
    expect(find.text('Synchronization failed'), findsOneWidget);
  });

  testWidgets('caregiver session resolves its single linked patient',
      (tester) async {
    _f.sessionJson = jsonEncode({
      'id': 2,
      'email': 'cg2@example.com',
      'role': 'CAREGIVER',
      'caregiverId': 7,
    });
    _f.healthReturnsData = false;
    await _setPrefs(devices: [_device('google_fit')], patientId: null);
    await _pump(tester, const WearablesScreen());
    expect(_f.calls, contains('GET /v1/api/caregivers/7/patients'));
    expect(await UserRoleStorageService.instance.getPatientId(), 42);
  });

  testWidgets('missing patient asks to select one first', (tester) async {
    await _setPrefs(devices: [_device('google_fit')], patientId: null);
    await _pump(tester, const WearablesScreen());
    expect(find.textContaining('Select a patient first'), findsOneWidget);
  });

  testWidgets('removing devices asks first, then clears the list',
      (tester) async {
    _f.healthReturnsData = false;
    await _setPrefs(devices: [
      _device('google_fit', id: 'g1', name: 'Health Connect'),
      _device('apple_health', id: 'a1', name: 'Apple Health'),
    ]);
    await _pump(tester, const WearablesScreen());

    await tester.tap(find.byIcon(Icons.delete_outline).first);
    await tester.pumpAndSettle();
    expect(find.text('Remove Device'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await _withHttp(() async {
      await tester.tap(find.byIcon(Icons.delete_outline).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await _settle(tester);
    });
    expect(find.text('Health Connect has been removed'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete_outline).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await _settle(tester);
    expect(find.text('No Wearables Connected'), findsOneWidget);
  });

  testWidgets('add device wizard connects Fitbit and returns to wearables',
      (tester) async {
    _f.healthReturnsData = false;
    await _setPrefs(devices: []);
    await _pump(tester, const WearablesScreen());
    expect(find.text('No Wearables Connected'), findsOneWidget);

    await _withHttp(() async {
      await tester.tap(find.text('Add Your First Device'));
      await tester.pumpAndSettle();
      expect(find.byType(AddDeviceScreen), findsOneWidget);

      await tester.tap(find.text('Fitbit'));
      await _settle(tester);
      expect(find.text('Connected to Fitbit!'), findsOneWidget);
      ScaffoldMessenger.of(tester.element(find.byType(AddDeviceScreen)))
          .removeCurrentSnackBar();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Successfully Connected!'), findsOneWidget);
      expect(find.textContaining('Now tracking:'), findsOneWidget);

      // Reset to the selection step: Fitbit is now marked Connected.
      await tester.tap(find.text('Add Another Platform'));
      await tester.pumpAndSettle();
      expect(find.text('Connected'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
    });
  });

  testWidgets('add device completes back to the dashboard', (tester) async {
    _f.healthReturnsData = false;
    await _setPrefs(devices: []);
    await _pump(tester, const WearablesScreen());

    await _withHttp(() async {
      await tester.tap(find.text('Add Your First Device'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fitbit'));
      await _settle(tester);
      ScaffoldMessenger.of(tester.element(find.byType(AddDeviceScreen)))
          .removeCurrentSnackBar();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Back to Dashboard'));
      await tester.pumpAndSettle();
      await _settle(tester);
    });
    expect(find.byType(AddDeviceScreen), findsNothing);
    expect(find.text('Fitbit'), findsWidgets);
  });

  testWidgets('add device shows connection failure and retries',
      (tester) async {
    _f.healthAuthorized = false;
    await _setPrefs(devices: []);
    await _pump(tester, const AddDeviceScreen());

    await tester.tap(find.text('Fitbit'));
    await _settle(tester);
    expect(find.text('Connection Failed'), findsOneWidget);

    // Bottom "Try Again" retries the connection.
    _f.healthAuthorized = true;
    _f.healthHasPermissions = false;
    await tester.tap(find.text('Try Again').last);
    await _settle(tester);
    expect(find.text('Connection Failed'), findsOneWidget);
    expect(find.textContaining('permissions were not granted'), findsOneWidget);

    // Inline "Try Again" clears the error.
    await tester.tap(find.text('Try Again').first);
    await tester.pump();
    expect(find.text('Connection Failed'), findsNothing);
  });
}
