// Additional coverage for PatientDetailsPage: video-call / dev delete guards,
// response shape fallbacks, mood/symptom/DOB edge cases, risk-type failures,
// loading spinners on the Health tab and a thrown known-risk save.

import 'dart:async';
import 'dart:convert';

import 'package:care_connect_app/features/health/caregiver-patient-list/page/patient_details_page.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_client.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:dio/dio.dart' show HttpClientAdapter;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../mock_user_provider.dart';
import '../../health_data/health_data_test_support.dart';

/// 'METHOD path-regex' -> response; checked before the defaults.
final Map<String, FutureOr<http.Response> Function(http.Request)> _routes = {};
final List<http.Request> _requests = [];

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status);

Map<String, dynamic> _profile() => {
      'id': 42,
      'firstName': 'Sarah',
      'lastName': 'Johnson',
      'email': 'sarah@example.com',
      'dob': '1980-05-15',
      'gender': 'Female',
    };

Future<http.Response> _handle(http.Request req) async {
  _requests.add(req);
  for (final e in _routes.entries) {
    final i = e.key.indexOf(' ');
    if (req.method == e.key.substring(0, i) &&
        RegExp(e.key.substring(i + 1)).hasMatch(req.url.path)) {
      return await e.value(req);
    }
  }
  final path = req.url.path;
  if (path.contains('/profile')) return _json(_profile());
  if (path.contains('/symptoms')) return _json({'data': []});
  if (path.contains('/search') ||
      path.contains('/check-in') ||
      path.contains('/checkin')) {
    return _json({
      'items': [],
      'page': 0,
      'size': 5,
      'totalElements': 0,
      'totalPages': 0,
    });
  }
  if (RegExp(r'/patients/\d+$').hasMatch(path)) return _json(_profile());
  if (path.contains('/family-members') ||
      path.contains('/medications') ||
      path.contains('/risk') ||
      path.contains('/mood') ||
      path.contains('/telemetry')) {
    return _json([]);
  }
  return _json({});
}

final MockClient _client = MockClient(_handle);

Future<void> _settle(WidgetTester t, [int frames = 30]) async {
  for (var i = 0; i < frames; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _act(WidgetTester t, Future<void> Function() body,
    {int frames = 20}) async {
  await http.runWithClient(() async {
    await body();
    await _settle(t, frames);
  }, () => _client);
}

Future<void> _pumpPage(
  WidgetTester t, {
  bool isCaregiver = true,
  UserProvider? provider,
  int frames = 30,
}) async {
  t.view.physicalSize = const Size(1200, 2400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await http.runWithClient(() async {
    await t.pumpWidget(ChangeNotifierProvider<UserProvider>.value(
      value: provider ??
          MockUserProvider(
              mockUser: MockUser(role: 'CAREGIVER', caregiverId: 10)),
      child: MaterialApp(
        home: PatientDetailsPage(patientId: '42', isCaregiver: isCaregiver),
      ),
    ));
    await _settle(t, frames);
  }, () => _client);
}

String? _snack(WidgetTester t) {
  final s = find.byType(SnackBar);
  if (s.evaluate().isEmpty) return null;
  return (t.widget<SnackBar>(s.last).content as Text).data;
}

Future<void> _openTab(WidgetTester t, String label) =>
    _act(t, () => t.tap(find.text(label)), frames: 10);

void main() {
  late HttpClientAdapter originalDio;

  setUp(() {
    _routes.clear();
    _requests.clear();
    SharedPreferences.setMockInitialValues({});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        if (call.method == 'read') {
          final key = (call.arguments as Map?)?['key'] as String?;
          if (key == 'jwt_token') return 'mock-token';
          return null;
        }
        if (call.method == 'readAll') return <String, String>{};
        if (call.method == 'containsKey') return false;
        return null;
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => call.method == 'check' ? ['wifi'] : null,
    );
    messenger.setMockStreamHandler(
      const EventChannel('dev.fluttercommunity.plus/connectivity_status'),
      MockStreamHandler.inline(onListen: (_, __) {}),
    );
    ApiService.debugSetHttpClient(_client);
    originalDio = ApiClient.instance.debugHttpClientAdapter;
    ApiClient.instance.debugSetHttpClientAdapter(RouteAdapter({
      '/v1/api/medicare/visits': envelope(const []),
      '/v1/api/medicare/coverage': envelope(const []),
    }));
  });

  tearDown(() {
    ApiService.debugResetHttpClient();
    ApiClient.instance.debugSetHttpClientAdapter(originalDio);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        null);
    messenger.setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/connectivity'), null);
    messenger.setMockStreamHandler(
        const EventChannel('dev.fluttercommunity.plus/connectivity_status'),
        null);
  });

  testWidgets('video call without a signed-in user explains the problem',
      (t) async {
    await _pumpPage(t, isCaregiver: false, provider: UserProvider());
    expect(find.byType(PatientDetailsPage), findsOneWidget);
    await _act(t, () => t.tap(find.text('Start Video Call').first));
    expect(_snack(t), 'Unable to determine your account.');
  });

  testWidgets(
      'caregiver without a resolvable patient user cannot call or delete '
      'call history', (t) async {
    await _pumpPage(t);
    await _act(t, () => t.tap(find.text('Start Video Call').first));
    expect(_snack(t), 'Invalid patient ID for video call.');

    ScaffoldMessenger.of(t.element(find.byType(PatientDetailsPage)))
        .clearSnackBars();
    await t.pumpAndSettle();
    await _act(t, () => t.tap(find.text('Delete Call History (Dev)')));
    expect(_snack(t), 'No patient call history is available to delete.');
  });

  testWidgets(
      'non-2xx details and list-shaped profile fall back to the caregiver '
      'view; string messaging flag, undated mood and old symptom are read',
      (t) async {
    final threeDaysAgo =
        DateTime.now().subtract(const Duration(days: 3)).toIso8601String();
    _routes.addAll({
      r'GET /api/patients/42$': (_) => _json({'error': 'nope'}, 500),
      r'GET /patients/42/profile$': (_) => _json(['not', 'a', 'map']),
      r'GET /caregivers/10/patients/42$': (_) => _json({
            'patient': {'firstName': 'Casey', 'lastName': 'Viewer'},
            'link': {
              'linkId': '77',
              'patientUserId': 500,
              'patientVideoCallsEnabled': true,
              'patientMessagingEnabled': 'FALSE',
            },
          }),
      r'GET .*/500/mood$': (_) => _json([
            {'score': 7, 'note': 'no date'},
          ]),
      r'GET /symptoms/patient/42$': (_) => _json({
            'data': [
              {
                'id': 1,
                'symptomKey': 'Headache',
                'severity': 'MILD',
                'takenAt': threeDaysAgo,
              },
            ],
          }),
    });
    await _pumpPage(t);

    expect(find.text('Patient messaging is currently blocked.'),
        findsOneWidget);
    expect(find.textContaining('Casey'), findsWidgets);
    expect(_requests.where((r) => r.url.path.endsWith('/500/mood')),
        isNotEmpty);
  });

  testWidgets('list-shaped details and failed profile still render the page',
      (t) async {
    final now = DateTime.now();
    // Birthday is tomorrow, so this year's birthday has not happened yet.
    final dob = DateTime(now.year - 30, now.month, now.day + 1);
    _routes.addAll({
      r'GET /api/patients/42$': (_) => _json([1, 2, 3]),
      r'GET /patients/42/profile$': (_) => _json({}, 404),
      r'GET /caregivers/10/patients/42$': (_) => _json({
            'patient': {
              'firstName': 'Dana',
              'lastName': 'Birthday',
              'dob': '${dob.year.toString().padLeft(4, '0')}-'
                  '${dob.month.toString().padLeft(2, '0')}-'
                  '${dob.day.toString().padLeft(2, '0')}',
            },
          }),
    });
    await _pumpPage(t);
    expect(find.byType(PatientDetailsPage), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
    expect(find.textContaining('Dana'), findsWidgets);
  });

  testWidgets('risk types that fail to parse leave "No risk types available."',
      (t) async {
    _routes[r'GET /risk-types$'] = (_) => _json({'unexpected': 'shape'});
    await _pumpPage(t);
    await _openTab(t, 'Health');
    await _act(t, () => t.tap(find.text('Edit')), frames: 2);
    expect(find.text('No risk types available.'), findsOneWidget);
  });

  testWidgets('Health tab shows spinners while risk types and medications load',
      (t) async {
    final riskGate = Completer<http.Response>();
    var medsCalls = 0;
    final medsGate = Completer<http.Response>();
    _routes[r'GET /risk-types$'] = (_) => riskGate.future;
    _routes[r'GET /patients/42/medications$'] = (_) {
      medsCalls++;
      return medsCalls == 1 ? _json([], 500) : medsGate.future;
    };

    await _pumpPage(t);
    await _openTab(t, 'Health');
    // Known Risks card is still loading its risk types.
    expect(find.byType(CircularProgressIndicator), findsWidgets);
    expect(find.text('Failed to load medications: 500'), findsOneWidget);

    // Retry medications while the response is pending -> loading spinner.
    await _act(t, () => t.tap(find.text('Retry')), frames: 2);
    expect(find.text('Failed to load medications: 500'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsWidgets);

    riskGate.complete(_json([
      {'id': 1, 'name': 'Fall risk'},
    ]));
    medsGate.complete(_json([]));
    await _act(t, () async {});
    expect(find.text('No current medications'), findsOneWidget);
    expect(medsCalls, 2);
  });

  testWidgets('a thrown known-risk save reports Save failed', (t) async {
    _routes.addAll({
      r'GET /risk-types$': (_) => _json([
            {'id': 1, 'name': 'Fall risk'},
          ]),
      r'GET /patients/42/risks$': (_) => _json([]),
      r'POST /patients/42/risks$': (_) => throw Exception('network down'),
    });
    await _pumpPage(t);
    await _openTab(t, 'Health');
    await _act(t, () => t.tap(find.text('Edit')), frames: 2);
    await _act(
        t, () => t.tap(find.widgetWithText(CheckboxListTile, 'Fall risk')),
        frames: 1);
    await _act(t, () => t.tap(find.text('Save')));
    expect(_snack(t), contains('Save failed:'));
    expect(_snack(t), contains('network down'));
  });

  testWidgets('a thrown personalization save reports Save failed',
      (t) async {
    _routes[r'PUT /patients/42/profile$'] =
        (_) => throw Exception('profile offline');
    await _pumpPage(t);
    await _act(t, () => t.tap(find.text('Edit').first), frames: 2);
    expect(find.widgetWithText(TextField, 'Likes'), findsOneWidget);
    await _act(t, () => t.tap(find.text('Save').first));
    expect(_snack(t), contains('Save failed:'));
    expect(_snack(t), contains('profile offline'));
    expect(find.widgetWithText(TextField, 'Likes'), findsNothing);
  });
}
