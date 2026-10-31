// Breadth coverage for ApiService error / edge paths and multipart uploads.
//
// The shared client is swapped with ApiService.debugSetHttpClient, and
// top-level http.* calls plus MultipartRequest.send() are intercepted with
// http.runWithClient using the same MockClient handler.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:care_connect_app/services/api_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

typedef _Handler = Future<http.Response> Function(http.Request req);

Future<T> _run<T>(_Handler handler, Future<T> Function() body) async {
  final client = MockClient(handler);
  ApiService.debugSetHttpClient(client);
  try {
    return await http.runWithClient(body, () => client);
  } finally {
    ApiService.debugResetHttpClient();
  }
}

_Handler _respond(Object? body, [int status = 200, Map<String, String>? h]) =>
    (_) async => http.Response(
          body is String ? body : jsonEncode(body),
          status,
          headers: h ?? const {},
        );

Future<http.Response> _throws(http.Request _) async =>
    throw http.ClientException('offline');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUpAll(() {
    tmp = Directory.systemTemp.createTempSync('api_service_cov');
  });

  tearDownAll(() {
    tmp.deleteSync(recursive: true);
  });

  setUp(() {
    final expiry = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
    FlutterSecureStorage.setMockInitialValues({
      'jwt_token': 'api-jwt',
      'token_expiry': '$expiry',
      'user_session': jsonEncode({'id': 77}),
    });
  });

  File tempFile(String name) =>
      File('${tmp.path}${Platform.pathSeparator}$name')
        ..writeAsBytesSync([1, 2, 3, 4]);

  group('auth / feed', () {
    test('registerPatient sends the bearer token', () async {
      late http.Request seen;
      final res = await _run((req) async {
        seen = req;
        return http.Response('{}', 201);
      },
          () => ApiService.registerPatient(
              'A', 'B', 'a@b.c', '1', '2000-01-01', 'addr', 'son', 3));
      expect(res.statusCode, 201);
      expect(seen.headers['Authorization'], 'Bearer api-jwt');
    });

    test('createPost uploads with and without an image', () async {
      final seen = <http.Request>[];
      Future<http.Response> h(http.Request r) async {
        seen.add(r);
        return http.Response('{"ok":true}', 200);
      }

      final a = await _run(h, () => ApiService.createPost(1, 'hello'));
      final b = await _run(
          h, () => ApiService.createPost(1, 'pic', tempFile('img.png')));
      expect(a.statusCode, 200);
      expect(b.statusCode, 200);
      expect(seen.first.url.path, endsWith('/create'));
      expect(latin1.decode(seen.last.bodyBytes), contains('img.png'));
    });

    test('getUserSubscriptions uses session user id', () async {
      late http.Request seen;
      await _run((req) async {
        seen = req;
        return http.Response('[]', 200);
      }, ApiService.getUserSubscriptions);
      expect(seen.url.path, endsWith('/user/77/active'));
    });
  });

  group('link lookups return [] on failures', () {
    test('getCaregiverLinkedPatientUserIds', () async {
      expect(await _run(_respond('', 500),
          () => ApiService.getCaregiverLinkedPatientUserIds(1)), isEmpty);
      expect(await _run(_respond({'a': 1}),
          () => ApiService.getCaregiverLinkedPatientUserIds(1)), isEmpty);
      expect(await _run(_throws,
          () => ApiService.getCaregiverLinkedPatientUserIds(1)), isEmpty);
    });

    test('getPatientLinkedCaregiverUserIds', () async {
      expect(await _run(_respond('', 404),
          () => ApiService.getPatientLinkedCaregiverUserIds(1)), isEmpty);
      expect(await _run(_respond({'a': 1}),
          () => ApiService.getPatientLinkedCaregiverUserIds(1)), isEmpty);
      expect(await _run(_throws,
          () => ApiService.getPatientLinkedCaregiverUserIds(1)), isEmpty);
    });

    test('getPatientLinkedCaregiverLinks', () async {
      expect(await _run(_respond('', 404),
          () => ApiService.getPatientLinkedCaregiverLinks(1)), isEmpty);
      expect(await _run(_respond({'a': 1}),
          () => ApiService.getPatientLinkedCaregiverLinks(1)), isEmpty);
      expect(await _run(_throws,
          () => ApiService.getPatientLinkedCaregiverLinks(1)), isEmpty);
    });
  });

  group('swallowed errors', () {
    test('checkEmailExists returns error map', () async {
      final r = await _run(_throws, () => ApiService.checkEmailExists('a@b'));
      expect(r['exists'], isFalse);
      expect(r['error'], contains('offline'));
    });

    test('mood / medication helpers return empty values', () async {
      expect(await _run(_throws, () => ApiService.getCaregiverMoodSummaries(1)),
          isEmpty);
      expect(
          await _run(_throws, () => ApiService.getActiveMedications(1)), isEmpty);
      expect(
          await _run(_throws, () => ApiService.getTodaysMedications(1)), isEmpty);
      expect(await _run(_throws, () => ApiService.getMoodHistory(1)), isEmpty);
      expect(await _run(_throws, () => ApiService.getPrimaryCareProvider(1)),
          isEmpty);
      expect(await _run(_throws, () => ApiService.getUserProfilePictureUrl(1)),
          isNull);
      expect(await _run(_throws, () => ApiService.getEnhancedPatientProfile(1)),
          isNull);
    });

    test('medication mutations convert errors to 500 responses', () async {
      final calls = <Future<http.Response> Function()>[
        () => ApiService.getPatientVitals(1),
        () => ApiService.getPatientMedicationsForPatient(1),
        () => ApiService.addPatientMedication(1, {'name': 'x'}),
        () => ApiService.removePatientMedication(1, 2),
        () => ApiService.deleteMedicationByCaregiver(1, 2, 3),
        () => ApiService.approveMedication(1, 2),
        () => ApiService.markMedicationTaken(1, 2),
        () => ApiService.clearMedicationTakenStatus(1, 2),
        () => getUserFilesByCategory(1),
      ];
      for (final call in calls) {
        final res = await _run(_throws, call);
        expect(res.statusCode, 500);
        expect(jsonDecode(res.body)['error'], contains('offline'));
      }
    });
  });

  group('family / caregiver patient access', () {
    test('getAccessiblePatients maps bad JSON to a format error', () async {
      await expectLater(
        _run(_respond('not json'), ApiService.getAccessiblePatients),
        throwsA(isA<Exception>().having((e) => e.toString(), 'msg',
            contains('Invalid response format'))),
      );
    });

    test('getPatientData handles 200 / 403 / other', () async {
      final ok =
          await _run(_respond({'id': 5}), () => ApiService.getPatientData(5));
      expect(ok['id'], 5);
      await expectLater(_run(_respond('', 403), () => ApiService.getPatientData(5)),
          throwsA(isA<Exception>()));
      await expectLater(_run(_respond('', 500), () => ApiService.getPatientData(5)),
          throwsA(isA<Exception>()));
    });

    test('getPatientForCaregiver handles 403 / 404 / other', () async {
      for (final code in [403, 404, 500]) {
        await expectLater(
          _run(_respond('', code), () => ApiService.getPatientForCaregiver(1, 2)),
          throwsA(isA<Exception>()),
        );
      }
    });
  });

  group('client activities', () {
    test('resolveImageUrl joins relative paths onto the backend url', () {
      expect(ApiService.resolveImageUrl('/img/a.png'), endsWith('/img/a.png'));
      expect(ApiService.resolveImageUrl('img/b.png'), endsWith('/img/b.png'));
      expect(ApiService.resolveImageUrl('img/b.png'), startsWith('http'));
    });

    test('activity endpoints hit the expected paths', () async {
      final paths = <String>[];
      Future<http.Response> h(http.Request r) async {
        paths.add('${r.method} ${r.url.path}');
        return http.Response('{}', 200);
      }

      await _run(h, () => ApiService.getActivities());
      await _run(h, () => ApiService.postClientEvent(clientId: 3, activityId: 4));
      await _run(h, () => ApiService.getIncidentReport(3, 9));
      await _run(h,
          () => ApiService.postClientActivityIcon(3, 4, tempFile('icon.png')));
      await _run(
          h,
          () => ApiService.uploadUserFile(
              userId: 3, file: tempFile('doc.pdf'), category: 'docs'));
      await _run(
          h,
          () => uploadUserFileFromBytes(
              userId: 3,
              fileBytes: Uint8List.fromList([1, 2]),
              fileName: 'b.txt',
              category: 'notes'));
      await _run(h, () => getUserFilesByCategory(3));

      expect(paths, contains(startsWith('POST')));
      expect(paths.any((p) => p.endsWith('/clients/3/events')), isTrue);
      expect(paths.any((p) => p.endsWith('/incident-reports/9')), isTrue);
      expect(paths.any((p) => p.endsWith('/activity-config/4/icon')), isTrue);
      expect(paths.where((p) => p.endsWith('/users/3/upload')).length, 2);
      expect(paths.any((p) => p.endsWith('/users/3/list')), isTrue);
    });
  });

  group('allergies', () {
    test('addAllergy returns queued marker for offline-queued responses',
        () async {
      final r = await _run(
        _respond({'requestId': 'r1'}, 202, {'x-offline-queued': 'true'}),
        () => ApiService.addAllergy({'drug': 'x'}, 1),
      );
      expect(r, {'queued': true, 'requestId': 'r1'});
    });

    test('addAllergy returns {} for non-map success body', () async {
      final r =
          await _run(_respond([1]), () => ApiService.addAllergy({'drug': 'x'}, 1));
      expect(r, isEmpty);
    });
  });

  group('calls', () {
    test('list endpoints return [] on non-list / failures', () async {
      final calls = <Future<List<Map<String, dynamic>>> Function()>[
        () => ApiService.getCallTelemetry('c'),
        () => ApiService.getCallTranscriptSegments('c'),
        ApiService.getMyCallTelemetry,
        () => ApiService.getSentimentHistory(1),
      ];
      for (final call in calls) {
        expect(await _run(_respond({'x': 1}), call), isEmpty);
        expect(await _run(_throws, call), isEmpty);
        expect(await _run(_respond('', 500), call), isEmpty);
      }
    });

    test('confirmCallSummaryItem sends destination and notes', () async {
      late http.Request seen;
      final r = await _run((req) async {
        seen = req;
        return http.Response('{"status":"CONFIRMED"}', 200);
      },
          () => ApiService.confirmCallSummaryItem('c', 'i',
              decision: 'CONFIRM', destination: 'TASKS', notes: 'n'));
      expect(r['status'], 'CONFIRMED');
      expect(jsonDecode(seen.body),
          {'decision': 'CONFIRM', 'destination': 'TASKS', 'notes': 'n'});
    });

    test('getCallRecording returns null for odd bodies and errors', () async {
      expect(await _run(_respond([1]), () => ApiService.getCallRecording('c')),
          isNull);
      expect(await _run(_throws, () => ApiService.getCallRecording('c')),
          isNull);
    });

    test('getCallRecordingPlaybackUrl stringifies non-string urls', () async {
      final url = await _run(_respond({'playbackUrl': 123}),
          () => ApiService.getCallRecordingPlaybackUrl('c'));
      expect(url, '123');
    });

    test('deletePatientCallHistoryDev surfaces server message', () async {
      await expectLater(
        _run(_respond({'message': 'not allowed'}, 403),
            () => ApiService.deletePatientCallHistoryDev(1)),
        throwsA(isA<HttpException>().having(
            (e) => e.message, 'message', contains('(403) - not allowed'))),
      );
    });

    test('deletePatientCallHistoryDev returns {} for non-map body', () async {
      final r = await _run(
          _respond([1]), () => ApiService.deletePatientCallHistoryDev(1));
      expect(r, isEmpty);
    });
  });
}
