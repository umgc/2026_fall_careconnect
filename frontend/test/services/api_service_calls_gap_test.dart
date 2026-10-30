// Gap-filling tests for lib/services/api_service.dart, part two: family and
// vitals access, tasks v2, medications, allergies, call telemetry/summary
// endpoints and the file helpers at the bottom of the file.
//
// Same harness as api_service_gap_test.dart: a MockClient installed through
// ApiService.debugSetHttpClient for calls on the shared client, and a fake
// HttpOverrides for the methods that use top-level http.* functions or build
// their own multipart request.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:care_connect_app/services/api_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_http_overrides.dart';

typedef _Route = http.Response Function(http.Request req);

void main() {
  final requests = <http.Request>[];
  _Route route = (r) => http.Response('{}', 200);
  FakeResponse Function(String, Uri) rawRoute =
      (m, u) => FakeResponse(200, '{}');
  final rawRequests = <String>[];

  void signIn({Map<String, dynamic>? session}) {
    final exp =
        DateTime.now().add(const Duration(hours: 2)).millisecondsSinceEpoch ~/
            1000;
    FlutterSecureStorage.setMockInitialValues({
      'jwt_token': 'tok-xyz',
      'token_expiry': '$exp',
      if (session != null) 'user_session': jsonEncode(session),
    });
  }

  setUpAll(() {
    HttpOverrides.global = FakeHttpOverrides((m, u) {
      rawRequests.add('$m ${u.path}');
      return rawRoute(m, u);
    });
  });

  tearDownAll(() {
    ApiService.debugResetHttpClient();
    HttpOverrides.global = null;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    signIn();
    requests.clear();
    rawRequests.clear();
    route = (r) => http.Response('{}', 200);
    rawRoute = (m, u) => FakeResponse(200, '{}');
    ApiService.debugSetHttpClient(MockClient((req) async {
      requests.add(req);
      return route(req);
    }));
  });

  http.Request last() => requests.last;

  group('getUserSubscriptions', () {
    test('uses the session user id', () async {
      signIn(session: {'id': 8});
      await ApiService.getUserSubscriptions();
      expect(last().url.path, endsWith('/subscriptions/user/8/active'));
    });

    test('throws when not logged in', () async {
      await expectLater(
        ApiService.getUserSubscriptions(),
        throwsA(predicate((e) => '$e'.contains('User ID not found'))),
      );
    });
  });

  group('family / caregiver patient access (top-level http)', () {
    test('getAccessiblePatients returns the decoded list on 200', () async {
      rawRoute = (m, u) => FakeResponse(
            200,
            jsonEncode([
              {'id': 1},
              {'id': 2},
            ]),
          );
      final list = await ApiService.getAccessiblePatients();
      expect(list.map((p) => p['id']), [1, 2]);
      expect(rawRequests.single, 'GET /v3/api/family-members/patients');
    });

    test('getAccessiblePatients reports access denied on 403', () async {
      rawRoute = (m, u) => FakeResponse(403, '{"error":"no"}');
      await expectLater(
        ApiService.getAccessiblePatients(),
        throwsA(predicate((e) => '$e'.contains('do not have access'))),
      );
    });

    test('getAccessiblePatients surfaces server error text otherwise',
        () async {
      rawRoute = (m, u) => FakeResponse(500, '{"error":"db down"}');
      await expectLater(
        ApiService.getAccessiblePatients(),
        throwsA(isA<Exception>()),
      );
    });

    test('getAccessiblePatients maps malformed JSON to a format error',
        () async {
      rawRoute = (m, u) => FakeResponse(200, 'not json');
      await expectLater(
        ApiService.getAccessiblePatients(),
        throwsA(predicate((e) => '$e'.contains('Invalid response format'))),
      );
    });

    test('getPatientData decodes 200 and maps 403 / other failures', () async {
      rawRoute = (m, u) => FakeResponse(200, '{"id":5}');
      expect(await ApiService.getPatientData(5), {'id': 5});
      expect(rawRequests.last, 'GET /v3/api/family-members/patients/5');

      rawRoute = (m, u) => FakeResponse(403, '{}');
      await expectLater(ApiService.getPatientData(5),
          throwsA(predicate((e) => '$e'.contains('Access denied'))));

      rawRoute = (m, u) => FakeResponse(500, '{}');
      await expectLater(ApiService.getPatientData(5),
          throwsA(predicate((e) => '$e'.contains('Failed to fetch'))));
    });

    test('getPatientForCaregiver maps 200, 403, 404 and other failures',
        () async {
      rawRoute = (m, u) => FakeResponse(200, '{"id":9}');
      expect(await ApiService.getPatientForCaregiver(2, 9), {'id': 9});
      expect(rawRequests.last, 'GET /v1/api/caregivers/2/patients/9');

      rawRoute = (m, u) => FakeResponse(403, '{}');
      await expectLater(ApiService.getPatientForCaregiver(2, 9),
          throwsA(predicate((e) => '$e'.contains('Access denied'))));

      rawRoute = (m, u) => FakeResponse(404, '{}');
      await expectLater(ApiService.getPatientForCaregiver(2, 9),
          throwsA(predicate((e) => '$e'.contains('Patient not found'))));

      rawRoute = (m, u) => FakeResponse(500, '{}');
      await expectLater(ApiService.getPatientForCaregiver(2, 9),
          throwsA(predicate((e) => '$e'.contains('Failed to fetch'))));
    });

    test('getPatientStatus decodes 200 and maps failures', () async {
      rawRoute = (m, u) => FakeResponse(200, '{"status":"OK"}');
      expect(await ApiService.getPatientStatus(4), {'status': 'OK'});
      expect(rawRequests.last, 'GET /v3/api/family-members/patients/4/status');

      rawRoute = (m, u) => FakeResponse(403, '{}');
      await expectLater(ApiService.getPatientStatus(4),
          throwsA(predicate((e) => '$e'.contains('Access denied'))));
    });
  });

  group('vitals and family members', () {
    test('getRecentVitalAlerts returns the data list as maps', () async {
      route = (r) => http.Response(
            jsonEncode({
              'data': [
                {'id': 1},
                'skip',
                {'id': 2},
              ],
            }),
            200,
          );
      final alerts = await ApiService.getRecentVitalAlerts(7, limit: 3);
      expect(alerts, [
        {'id': 1},
        {'id': 2},
      ]);
      expect(last().url.queryParameters, {'patientId': '7', 'limit': '3'});
    });

    test('getRecentVitalAlerts is empty on non-200, bad shape and errors',
        () async {
      route = (r) => http.Response('{}', 500);
      expect(await ApiService.getRecentVitalAlerts(7), isEmpty);
      route = (r) => http.Response('{"data":"x"}', 200);
      expect(await ApiService.getRecentVitalAlerts(7), isEmpty);
      route = (r) => http.Response('[1]', 200);
      expect(await ApiService.getRecentVitalAlerts(7), isEmpty);
      route = (r) => throw Exception('x');
      expect(await ApiService.getRecentVitalAlerts(7), isEmpty);
    });

    test('getPatientVitals wraps client exceptions in a 500 response',
        () async {
      route = (r) => throw Exception('socket');
      final r = await ApiService.getPatientVitals(3);
      expect(r.statusCode, 500);
      expect(jsonDecode(r.body)['error'], contains('socket'));
    });

    test('getPatientFamilyMembers keeps map entries and tolerates failures',
        () async {
      route = (r) => http.Response(
            jsonEncode([
              {'name': 'A'},
              7,
            ]),
            200,
          );
      expect(await ApiService.getPatientFamilyMembers(4), [
        {'name': 'A'},
      ]);
      expect(last().url.path, endsWith('/patients/4/family-members'));

      route = (r) => http.Response('{}', 200);
      expect(await ApiService.getPatientFamilyMembers(4), isEmpty);
      route = (r) => http.Response('[]', 500);
      expect(await ApiService.getPatientFamilyMembers(4), isEmpty);
    });

    test('getPatientCompleteProfile GETs the profile endpoint', () async {
      await ApiService.getPatientCompleteProfile(4);
      expect(last().url.path, endsWith('/patients/4/profile'));
    });
  });

  group('tasks v2', () {
    test('updateTaskCompletionV2 PUTs the flag and throws on failure',
        () async {
      await ApiService.updateTaskCompletionV2(12, true);
      expect(last().method, 'PUT');
      expect(last().url.path, endsWith('/v2/api/tasks/12/complete'));
      expect(jsonDecode(last().body), {'isComplete': true});

      route = (r) => http.Response('nope', 500);
      await expectLater(
        ApiService.updateTaskCompletionV2(12, false),
        throwsA(predicate((e) => '$e'.contains('500'))),
      );
    });

    test('createTaskV2 / previewTaskNotification / getTaskByIdV2 build URLs',
        () async {
      await ApiService.createTaskV2(3, '{"t":1}');
      expect(last().method, 'POST');
      expect(last().url.path, endsWith('/v2/api/tasks/patient/3'));
      expect(last().body, '{"t":1}');

      await ApiService.previewTaskNotification(3, '{"t":2}');
      expect(last().url.path,
          endsWith('/v3/api/tasks/patient/3/preview-notification'));
      expect(last().body, '{"t":2}');

      await ApiService.getTaskByIdV2(55);
      expect(last().method, 'GET');
      expect(last().url.path, endsWith('/v2/api/tasks/55'));
    });
  });

  group('getEnhancedPatientProfile', () {
    test('unwraps a data envelope', () async {
      route = (r) => http.Response('{"data":{"name":"A"}}', 200);
      expect(await ApiService.getEnhancedPatientProfile(1), {'name': 'A'});
      expect(last().url.path, endsWith('/patients/1/profile/enhanced'));
    });

    test('returns a bare object as is', () async {
      route = (r) => http.Response('{"name":"B"}', 200);
      expect(await ApiService.getEnhancedPatientProfile(1), {'name': 'B'});
    });

    test('returns null on non-200 and on errors', () async {
      route = (r) => http.Response('{}', 404);
      expect(await ApiService.getEnhancedPatientProfile(1), isNull);
      route = (r) => throw Exception('x');
      expect(await ApiService.getEnhancedPatientProfile(1), isNull);
    });
  });

  group('medications', () {
    test('getPatientMedicationsForPatient GETs v3 medications', () async {
      await ApiService.getPatientMedicationsForPatient(6);
      expect(last().url.path, endsWith('/v3/api/patients/6/medications'));
    });

    test('add / remove / approve / delete-by-caregiver use expected verbs',
        () async {
      await ApiService.addPatientMedication(6, {'name': 'Aspirin'});
      expect(last().method, 'POST');
      expect(jsonDecode(last().body), {'name': 'Aspirin'});

      await ApiService.removePatientMedication(6, 2);
      expect(last().method, 'DELETE');
      expect(last().url.path, endsWith('/patients/6/medications/2'));

      await ApiService.approveMedication(6, 2);
      expect(last().method, 'PUT');
      expect(last().url.path, endsWith('/medications/2/approve'));

      await ApiService.deleteMedicationByCaregiver(6, 2, 9);
      expect(last().method, 'DELETE');
      expect(last().url.path, endsWith('/medications/2/caregiver/9'));
    });

    test('markMedicationTaken sends the UTC taken time', () async {
      final at = DateTime.utc(2026, 5, 6, 7, 8, 9);
      await ApiService.markMedicationTaken(6, 2, takenAt: at);
      expect(last().method, 'PUT');
      expect(last().url.path, endsWith('/patients/6/medications/2/last-taken'));
      expect(jsonDecode(last().body), {'lastTaken': at.toIso8601String()});

      await ApiService.markMedicationTaken(6, 2);
      expect(DateTime.tryParse(jsonDecode(last().body)['lastTaken'] as String),
          isNotNull);
    });

    test('clearMedicationTakenStatus DELETEs last-taken', () async {
      await ApiService.clearMedicationTakenStatus(6, 2);
      expect(last().method, 'DELETE');
      expect(last().url.path, endsWith('/medications/2/last-taken'));
    });

    test('medication calls convert client exceptions into a 500 response',
        () async {
      route = (r) => throw Exception('offline');
      final calls = <Future<http.Response>>[
        ApiService.getPatientMedicationsForPatient(1),
        ApiService.addPatientMedication(1, {'a': 1}),
        ApiService.removePatientMedication(1, 1),
        ApiService.deleteMedicationByCaregiver(1, 1, 1),
        ApiService.approveMedication(1, 1),
        ApiService.markMedicationTaken(1, 1),
        ApiService.clearMedicationTakenStatus(1, 1),
      ];
      for (final r in await Future.wait(calls)) {
        expect(r.statusCode, 500);
        expect(jsonDecode(r.body)['error'], contains('offline'));
      }
    });
  });

  group('mood data (top-level http)', () {
    test('getMoodData decodes 200 and returns null otherwise', () async {
      rawRoute = (m, u) => FakeResponse(200, '{"score":4}');
      expect(await ApiService.getMoodData(1), {'score': 4});
      rawRoute = (m, u) => FakeResponse(404, '{}');
      expect(await ApiService.getMoodData(1), isNull);
    });

    test('getDailyMoodAverage decodes 200 and returns null otherwise',
        () async {
      rawRoute = (m, u) => FakeResponse(200, '{"avg":3.5}');
      expect(await ApiService.getDailyMoodAverage(1), {'avg': 3.5});
      rawRoute = (m, u) => FakeResponse(500, '{}');
      expect(await ApiService.getDailyMoodAverage(1), isNull);
    });
  });

  group('allergies', () {
    test('fetchAllergies returns the data list', () async {
      route = (r) => http.Response('{"data":[{"id":1}]}', 200);
      expect(await ApiService.fetchAllergies(3), [
        {'id': 1},
      ]);
      expect(last().url.path, endsWith('/allergies/patient/3'));
    });

    test('fetchAllergies defaults to an empty list without data', () async {
      route = (r) => http.Response('{}', 200);
      expect(await ApiService.fetchAllergies(3), isEmpty);
    });

    test('fetchAllergies throws HttpException on failure', () async {
      route = (r) => http.Response('bad', 500);
      await expectLater(
          ApiService.fetchAllergies(3), throwsA(isA<HttpException>()));
    });

    test('addAllergy maps form fields and unwraps the data envelope', () async {
      route = (r) => http.Response('{"data":{"id":9}}', 201);
      final out = await ApiService.addAllergy({
        'drug': 'Penicillin',
        'severity': 'HIGH',
        'reaction': 'rash',
        'note': 'since 2020',
      }, 3);
      expect(out, {'id': 9});
      expect(jsonDecode(last().body), {
        'patientId': 3,
        'allergen': 'Penicillin',
        'severity': 'HIGH',
        'reaction': 'rash',
        'notes': 'since 2020',
        'isActive': true,
      });
    });

    test('addAllergy returns the bare object when there is no envelope',
        () async {
      route = (r) => http.Response('{"id":4}', 200);
      expect(await ApiService.addAllergy({'drug': 'x'}, 3), {'id': 4});
    });

    test('addAllergy returns an empty map for non-object success bodies',
        () async {
      route = (r) => http.Response('[1]', 200);
      expect(await ApiService.addAllergy({'drug': 'x'}, 3), isEmpty);
    });

    test('addAllergy reports an offline-queued write', () async {
      route = (r) => http.Response(
            '{"requestId":"abc"}',
            202,
            headers: {'x-offline-queued': 'true'},
          );
      expect(await ApiService.addAllergy({'drug': 'x'}, 3),
          {'queued': true, 'requestId': 'abc'});
    });

    test('addAllergy throws HttpException on failure', () async {
      route = (r) => http.Response('no', 400);
      await expectLater(ApiService.addAllergy({'drug': 'x'}, 3),
          throwsA(isA<HttpException>()));
    });

    test('removeAllergy is true for 200 and 204 only', () async {
      route = (r) => http.Response('', 200);
      expect(await ApiService.removeAllergy(5), isTrue);
      expect(last().method, 'DELETE');
      route = (r) => http.Response('', 204);
      expect(await ApiService.removeAllergy(5), isTrue);
      route = (r) => http.Response('', 404);
      expect(await ApiService.removeAllergy(5), isFalse);
    });
  });

  group('call telemetry endpoints', () {
    const listCalls = <String>['telemetry', 'segments', 'mine', 'sentiment'];

    Future<List<Map<String, dynamic>>> invoke(String which) {
      switch (which) {
        case 'telemetry':
          return ApiService.getCallTelemetry('c1');
        case 'segments':
          return ApiService.getCallTranscriptSegments('c1');
        case 'mine':
          return ApiService.getMyCallTelemetry();
        default:
          return ApiService.getSentimentHistory(3);
      }
    }

    for (final which in listCalls) {
      test('$which: keeps map entries from a list body', () async {
        route = (r) => http.Response(
              jsonEncode([
                {'a': 1},
                'skip',
              ]),
              200,
            );
        expect(await invoke(which), [
          {'a': 1},
        ]);
      });

      test('$which: is empty on non-200, non-list body and errors', () async {
        route = (r) => http.Response('[]', 500);
        expect(await invoke(which), isEmpty);
        route = (r) => http.Response('{}', 200);
        expect(await invoke(which), isEmpty);
        route = (r) => throw Exception('x');
        expect(await invoke(which), isEmpty);
      });
    }

    test('endpoint paths', () async {
      await ApiService.getCallTelemetry('c1');
      expect(last().url.path, endsWith('/api/v3/calls/c1/telemetry'));
      await ApiService.getCallTranscriptSegments('c1');
      expect(last().url.path, endsWith('/calls/c1/transcript/segments'));
      await ApiService.getMyCallTelemetry();
      expect(last().url.path, endsWith('/calls/telemetry/my'));
      await ApiService.getSentimentHistory(3);
      expect(last().url.path, endsWith('/calls/sentiment-history'));
      expect(last().url.queryParameters, {'userId': '3'});
    });

    test('getCallSummary returns a map, else null', () async {
      route = (r) => http.Response('{"items":[]}', 200);
      expect(await ApiService.getCallSummary('c1'), {'items': []});
      expect(last().url.path, endsWith('/calls/c1/summary'));
      route = (r) => http.Response('{}', 404);
      expect(await ApiService.getCallSummary('c1'), isNull);
      route = (r) => http.Response('[]', 200);
      expect(await ApiService.getCallSummary('c1'), isNull);
      route = (r) => throw Exception('x');
      expect(await ApiService.getCallSummary('c1'), isNull);
    });

    test('confirmCallSummaryItem sends decision plus optional fields',
        () async {
      route = (r) => http.Response('{"ok":true}', 200);
      final out = await ApiService.confirmCallSummaryItem(
        'c1',
        'i7',
        decision: 'ACCEPT',
        destination: 'TASK',
        notes: 'n',
      );
      expect(out, {'ok': true});
      expect(last().url.path, endsWith('/calls/c1/summary/items/i7/confirm'));
      expect(jsonDecode(last().body),
          {'decision': 'ACCEPT', 'destination': 'TASK', 'notes': 'n'});

      await ApiService.confirmCallSummaryItem('c1', 'i7', decision: 'REJECT');
      expect(jsonDecode(last().body), {'decision': 'REJECT'});
    });

    test('confirmCallSummaryItem includes the server message in the error',
        () async {
      route = (r) => http.Response('{"message":"already done"}', 409);
      await expectLater(
        ApiService.confirmCallSummaryItem('c1', 'i7', decision: 'ACCEPT'),
        throwsA(predicate(
            (e) => '$e'.contains('HTTP 409') && '$e'.contains('already done'))),
      );
      route = (r) => http.Response('plain text', 500);
      await expectLater(
        ApiService.confirmCallSummaryItem('c1', 'i7', decision: 'ACCEPT'),
        throwsA(predicate(
            (e) => '$e'.contains('HTTP 500') && !'$e'.contains(' - '))),
      );
    });

    test('confirmCallSummaryItem rejects a non-object success body', () async {
      route = (r) => http.Response('[1]', 200);
      await expectLater(
        ApiService.confirmCallSummaryItem('c1', 'i7', decision: 'ACCEPT'),
        throwsA(isA<FormatException>()),
      );
    });

    test('getCallRecording returns the map unless there is no recording',
        () async {
      route = (r) => http.Response('{"status":"READY","url":"u"}', 200);
      expect(await ApiService.getCallRecording('c1'),
          {'status': 'READY', 'url': 'u'});
      route = (r) => http.Response('{"status":" no_recording "}', 200);
      expect(await ApiService.getCallRecording('c1'), isNull);
      route = (r) => http.Response('{"status":"NOT_FOUND"}', 200);
      expect(await ApiService.getCallRecording('c1'), isNull);
      route = (r) => http.Response('{}', 500);
      expect(await ApiService.getCallRecording('c1'), isNull);
      route = (r) => http.Response('[]', 200);
      expect(await ApiService.getCallRecording('c1'), isNull);
      route = (r) => throw Exception('x');
      expect(await ApiService.getCallRecording('c1'), isNull);
    });

    test('getConditionFlags returns a map, else null', () async {
      route = (r) => http.Response('{"flags":["a"]}', 200);
      expect(await ApiService.getConditionFlags('c1'), {
        'flags': ['a'],
      });
      expect(last().url.path, endsWith('/calls/c1/condition-flags'));
      route = (r) => http.Response('[]', 200);
      expect(await ApiService.getConditionFlags('c1'), isNull);
      route = (r) => http.Response('{}', 404);
      expect(await ApiService.getConditionFlags('c1'), isNull);
      route = (r) => throw Exception('x');
      expect(await ApiService.getConditionFlags('c1'), isNull);
    });

    test('recording playback data and url', () async {
      route = (r) => http.Response('{"playbackUrl":"https://p/x"}', 200);
      expect(await ApiService.getCallRecordingPlaybackData('c1'),
          {'playbackUrl': 'https://p/x'});
      expect(last().url.path, endsWith('/calls/c1/recording/playback-url'));
      expect(await ApiService.getCallRecordingPlaybackUrl('c1'), 'https://p/x');

      route = (r) => http.Response('{"playbackUrl":12}', 200);
      expect(await ApiService.getCallRecordingPlaybackUrl('c1'), '12');

      route = (r) => http.Response('{}', 200);
      expect(await ApiService.getCallRecordingPlaybackUrl('c1'), isNull);

      route = (r) => http.Response('{}', 500);
      expect(await ApiService.getCallRecordingPlaybackData('c1'), isNull);
      route = (r) => throw Exception('x');
      expect(await ApiService.getCallRecordingPlaybackData('c1'), isNull);
    });

    test('deletePatientCallHistoryDev returns the body map on 200', () async {
      route = (r) => http.Response('{"deleted":3}', 200);
      expect(await ApiService.deletePatientCallHistoryDev(8), {'deleted': 3});
      expect(last().method, 'DELETE');
      expect(last().url.path, endsWith('/calls/patients/8/telemetry'));

      route = (r) => http.Response('[1]', 200);
      expect(await ApiService.deletePatientCallHistoryDev(8), isEmpty);
    });

    test('deletePatientCallHistoryDev throws with status and message',
        () async {
      route = (r) => http.Response('{"error":"forbidden"}', 403);
      await expectLater(
        ApiService.deletePatientCallHistoryDev(8),
        throwsA(predicate((e) =>
            e is HttpException &&
            e.message.contains('(403)') &&
            e.message.contains('forbidden'))),
      );
      route = (r) => http.Response('oops', 500);
      await expectLater(
        ApiService.deletePatientCallHistoryDev(8),
        throwsA(predicate(
            (e) => e is HttpException && e.message.endsWith('(500)'))),
      );
    });
  });

  group('file helpers', () {
    test('uploadUserFileFromBytes posts a multipart upload', () async {
      rawRoute = (m, u) => FakeResponse(200, '{"fileUrl":"/x"}');
      final r = await uploadUserFileFromBytes(
        userId: 21,
        fileBytes: Uint8List.fromList([1, 2, 3]),
        fileName: 'a.png',
        category: 'profilePicture',
      );
      expect(r.statusCode, 200);
      expect(r.body, '{"fileUrl":"/x"}');
      expect(rawRequests.single, 'POST /v1/api/files/users/21/upload');
    });

    test('getUserFilesByCategory GETs the list endpoint', () async {
      await getUserFilesByCategory(21);
      expect(last().url.path, endsWith('/files/users/21/list'));
    });

    test('getUserFilesByCategory turns client errors into a 500 response',
        () async {
      route = (r) => throw Exception('net');
      final r = await getUserFilesByCategory(21);
      expect(r.statusCode, 500);
      expect(jsonDecode(r.body)['error'], contains('net'));
    });
  });

  group('http client lifecycle', () {
    test('dispose closes the active client', () {
      final probe = _CloseProbe();
      ApiService.debugSetHttpClient(probe);
      ApiService.dispose();
      expect(probe.closed, isTrue);
    });
  });
}

class _CloseProbe extends http.BaseClient {
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      throw UnimplementedError();

  @override
  void close() => closed = true;
}
