// More happy-path tests for PatientDetailsPage
// (lib/features/health/caregiver-patient-list/page/patient_details_page.dart):
// the caregiver's Configure Patient Check-in sheet and its save outcomes,
// and a medications payload that cannot be read.
import 'dart:convert';

import 'package:care_connect_app/features/health/caregiver-patient-list/page/patient_details_page.dart';
import 'package:care_connect_app/features/health/virtual_check_in/models/virtual_check_in_question.dart';
import 'package:care_connect_app/features/health/virtual_check_in/presentation/widgets/virtual_check_in_config_sheet.dart';
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

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status);

late http.Response Function(http.Request) _extra;
final _posts = <http.Request>[];

http.Response _handle(http.Request r) {
  if (r.method == 'POST') _posts.add(r);
  final override = _extra(r);
  if (override.statusCode != 599) return override;
  final path = r.url.path;
  if (path.contains('/profile')) {
    return _json({
      'id': 42,
      'firstName': 'Sarah',
      'lastName': 'Johnson',
      'mrn': 'MRN-1',
    });
  }
  if (path.contains('/search')) {
    return _json({
      'items': [
        {
          'checkInId': 7,
          'patientId': 42,
          'createdAt': '2026-10-01T09:00:00',
          'questionCount': 2,
        },
        {
          'checkInId': 8,
          'patientId': 42,
          'createdAt': '2026-10-05T09:00:00',
          'questionCount': 1,
        },
      ],
      'page': 0,
      'size': 5,
      'totalElements': 2,
      'totalPages': 1,
    });
  }
  if (path.contains('/medications') ||
      path.contains('/risk') ||
      path.contains('/mood') ||
      path.contains('/symptom') ||
      path.contains('/telemetry') ||
      path.contains('/family-members') ||
      path.contains('/questions')) {
    return _json([]);
  }
  if (RegExp(r'/patients/\d+').hasMatch(path)) {
    return _json({'id': 42, 'firstName': 'Sarah', 'lastName': 'Johnson'});
  }
  return _json({});
}

final _client = MockClient((r) async => _handle(r));

void main() {
  late HttpClientAdapter originalDio;

  setUp(() {
    _posts.clear();
    _extra = (_) => http.Response('', 599);
    SharedPreferences.setMockInitialValues({});
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => call.method == 'read' ? 'mock-token' : null,
    );
    m.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => call.method == 'check' ? ['wifi'] : null,
    );
    m.setMockStreamHandler(
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
  });

  Future<void> frames(WidgetTester t, [int n = 20]) async {
    for (var i = 0; i < n; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpPage(WidgetTester t) async {
    t.view.physicalSize = const Size(1200, 2400);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final original = FlutterError.onError;
    FlutterError.onError = (d) {
      final text = d.toString();
      if (text.contains('A RenderFlex overflowed')) return;
      original?.call(d);
    };
    addTearDown(() => FlutterError.onError = original);
    await http.runWithClient(() async {
      await t.pumpWidget(ChangeNotifierProvider<UserProvider>.value(
        value: MockUserProvider(
            mockUser: MockUser(role: 'CAREGIVER', caregiverId: 10)),
        child: const MaterialApp(
          home: PatientDetailsPage(patientId: '42', isCaregiver: true),
        ),
      ));
      await frames(t, 30);
    }, () => _client);
  }

  Future<void> act(WidgetTester t, Future<void> Function() body) =>
      http.runWithClient(() async {
        await body();
        await frames(t);
      }, () => _client);

  String? snack(WidgetTester t) {
    final s = find.byType(SnackBar);
    if (s.evaluate().isEmpty) return null;
    return (t.widget<SnackBar>(s.last).content as Text).data;
  }

  /// Opens the Configure sheet and closes it with [result].
  Future<void> configure(
      WidgetTester t, List<VirtualCheckInQuestion>? result) async {
    await act(t, () => t.tap(find.text('Virtual Check-In')));
    await act(t, () async {
      await t.ensureVisible(find.text('Configure Patient Check-in'));
      await t.tap(find.text('Configure Patient Check-in'));
    });
    expect(find.byType(VirtualCheckInConfigSheet), findsOneWidget);
    ScaffoldMessenger.of(t.element(find.byType(PatientDetailsPage)))
        .clearSnackBars();
    await act(t, () async {
      Navigator.of(t.element(find.byType(VirtualCheckInConfigSheet)))
          .pop(result);
    });
  }

  VirtualCheckInQuestion q(String id) => VirtualCheckInQuestion(
      id: id, type: CheckInQuestionType.yesNo, required: true, text: 'Q$id');

  testWidgets('a custom question is refused', (t) async {
    await pumpPage(t);
    await configure(t, [q('abc')]);
    expect(snack(t), startsWith('Custom questions are not supported yet.'));
  });

  testWidgets('saving no questions asks for one', (t) async {
    await pumpPage(t);
    await configure(t, const []);
    expect(snack(t), 'Select at least one question to save.');
  });

  testWidgets('a failed create says so', (t) async {
    await pumpPage(t);
    await configure(t, [q('5'), q(' 6 ')]);
    expect(snack(t), 'Failed to save virtual check-in configuration.');
    final body = jsonDecode(_posts.last.body) as Map<String, dynamic>;
    expect(body.toString(), contains('5'));
  });

  testWidgets('a created check-in reloads the page and says saved',
      (t) async {
    _extra = (r) => r.method == 'POST' && r.url.path.endsWith('/api/checkins')
        ? _json({'id': 99}, 201)
        : http.Response('', 599);
    await pumpPage(t);
    await configure(t, [q('5')]);
    expect(snack(t), 'Virtual check-in configuration saved');
  });

  testWidgets('closing the sheet without a result changes nothing',
      (t) async {
    await pumpPage(t);
    await configure(t, null);
    expect(_posts, isEmpty);
  });

  testWidgets('an unreadable medications payload is reported', (t) async {
    _extra = (r) => r.url.path.endsWith('/medications')
        ? http.Response('{not json', 200)
        : http.Response('', 599);
    await pumpPage(t);
    await act(t, () => t.tap(find.text('Health')));
    expect(find.textContaining('Error loading medications'), findsOneWidget);
  });
}
