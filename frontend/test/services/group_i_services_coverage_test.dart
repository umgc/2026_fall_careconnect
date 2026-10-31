// Coverage-focused tests for small service/model gaps (group I).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/features/ai_hitl/models/hitl_models.dart';
import 'package:care_connect_app/features/health/virtual_check_in/models/answer_dto.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:care_connect_app/services/auth_token_manager.dart';
import 'package:care_connect_app/services/checkin_service.dart';
import 'package:care_connect_app/services/medical_notes_service.dart';
import 'package:care_connect_app/services/notetaker_config_service.dart';
import 'package:care_connect_app/services/subscription_service.dart';

const MethodChannel _secure =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

final Map<String, String?> _store = {};
bool _throwOnStorage = false;

void _installSecure() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_secure, (call) async {
    if (_throwOnStorage) {
      throw PlatformException(code: 'boom', message: 'storage failure');
    }
    final args = (call.arguments as Map?) ?? {};
    switch (call.method) {
      case 'write':
        _store[args['key'] as String] = args['value'] as String?;
        return null;
      case 'read':
        return _store[args['key'] as String];
      case 'delete':
        _store.remove(args['key'] as String);
        return null;
      case 'readAll':
        return Map<String, String>.from(
            _store.map((k, v) => MapEntry(k, v ?? '')));
      default:
        return null;
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _store.clear();
    _throwOnStorage = false;
    _installSecure();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secure, null);
  });

  group('HITL models', () {
    test('HitlQueueItem accepts numeric (double) patientId', () {
      final item = HitlQueueItem.fromJson({
        'heldItemId': 'h1',
        'patientId': 7.0,
        'triggerCodes': ['A', ' ', 3],
      });
      expect(item.patientId, 7);
      expect(item.triggerCodes, ['A']);
    });

    test('HitlDetail accepts numeric patientId and int-like fields', () {
      final d = HitlDetail.fromJson({
        'heldItemId': 'h2',
        'patientId': 9.0,
        'status': 'PENDING_REVIEW',
        'deliveryStatus': 'HELD',
        'requesterUserId': 4,
        'reviewerUserId': 5.0,
      });
      expect(d.patientId, 9);
      expect(d.requesterUserId, 4);
      expect(d.reviewerUserId, 5);
      expect(d.isPending, isTrue);
    });

    test('HitlDetail rejects invalid optional field types', () {
      Map<String, dynamic> base() => {
            'heldItemId': 'h3',
            'patientId': 1,
            'status': 'S',
            'deliveryStatus': 'D',
          };
      expect(() => HitlDetail.fromJson(base()..['queryText'] = 5),
          throwsFormatException);
      expect(() => HitlDetail.fromJson(base()..['reviewerUserId'] = 'x'),
          throwsFormatException);
      expect(() => HitlDetail.fromJson(base()..['createdAt'] = 12),
          throwsFormatException);
    });

    test('HitlApiException.toString returns message', () {
      const e = HitlApiException(500, 'Server broke', errorCode: 'X');
      expect(e.toString(), 'Server broke');
    });
  });

  group('CheckinService string-typed parsing', () {
    test('fetchCheckInsForPatient parses string ids', () async {
      final list = await http.runWithClient(
        () => CheckinService.fetchCheckInsForPatient('5'),
        () => MockClient((req) async => http.Response(
            jsonEncode([
              {
                'checkInId': '11',
                'patientId': '5',
                'questionCount': '3',
                'createdAt': '2024-01-01T00:00:00Z',
              }
            ]),
            200)),
      );
      expect(list.single.checkInId, 11);
    });

    test('fetchCheckInsForPatientFiltered parses string paging values',
        () async {
      final page = await http.runWithClient(
        () => CheckinService.fetchCheckInsForPatientFiltered(patientId: '5'),
        () => MockClient((req) async => http.Response(
            jsonEncode({
              'items': [
                {'checkInId': '1', 'patientId': '5'}
              ],
              'page': '2',
              'size': '10',
              'totalElements': '30',
              'totalPages': '3',
            }),
            200)),
      );
      expect(page!.page, 2);
      expect(page.size, 10);
      expect(page.totalElements, 30);
      expect(page.totalPages, 3);
    });

    test('fetchCheckInDetail parses string ids and ordinals', () async {
      final detail = await http.runWithClient(
        () => CheckinService.fetchCheckInDetail(1),
        () => MockClient((req) async => http.Response(
            jsonEncode({
              'checkInId': '1',
              'patientId': '2',
              'status': 'submitted',
              'answers': [
                {'questionId': '4', 'ordinal': '2', 'valueNumber': '3.5'},
                {'questionId': 'bad'},
              ],
            }),
            200)),
      );
      expect(detail!.checkInId, 1);
      expect(detail.answers.single.questionId, 4);
      expect(detail.answers.single.ordinal, 2);
    });

    test('submitAnswers surfaces backend error message', () async {
      await expectLater(
        http.runWithClient(
          () => CheckinService.submitAnswers(
            checkInId: 1,
            request: const SubmitAnswersRequestDTO(answers: []),
          ),
          () => MockClient((req) async =>
              http.Response(jsonEncode({'error': 'Already submitted'}), 409)),
        ),
        throwsA(predicate((e) => e.toString().contains('Already submitted'))),
      );
    });

    test('addCheckin handles numeric (double) question ids', () async {
      final ok = await http.runWithClient(
        () => CheckinService.addCheckin('3', 'cg'),
        () => MockClient((req) async {
          if (req.method == 'GET') {
            return http.Response(
                jsonEncode([
                  {'id': 2.0}
                ]),
                200);
          }
          return http.Response('', 201);
        }),
      );
      expect(ok, isTrue);
    });
  });

  group('NotetakerConfigService.getPatientNote', () {
    test('returns note on 200', () async {
      final note = await http.runWithClient(
        () => NotetakerConfigService.getPatientNote(1, 'n1'),
        () => MockClient((req) async =>
            http.Response(jsonEncode({'id': 'n1', 'note': 'Hello'}), 200)),
      );
      expect(note!.note, 'Hello');
    });

    test('returns null on non-200 and non-map', () async {
      expect(
          await http.runWithClient(
            () => NotetakerConfigService.getPatientNote(1, 'n1'),
            () => MockClient((req) async => http.Response('nope', 404)),
          ),
          isNull);
      expect(
          await http.runWithClient(
            () => NotetakerConfigService.getPatientNote(1, 'n1'),
            () => MockClient((req) async => http.Response('[1]', 200)),
          ),
          isNull);
    });
  });

  group('AuthTokenManager error paths', () {
    test('saveAuthData wraps storage errors', () async {
      _throwOnStorage = true;
      await expectLater(
        AuthTokenManager.saveAuthData(jwtToken: 't', userSession: {}),
        throwsA(isA<Exception>()),
      );
    });

    test('validateCurrentSession returns false on storage error', () async {
      _throwOnStorage = true;
      expect(await AuthTokenManager.validateCurrentSession(), isFalse);
    });

    test('isSessionStale returns false for corrupt activity value', () async {
      _store['last_activity'] = 'not-a-number';
      expect(await AuthTokenManager.isSessionStale(), isFalse);
    });
  });

  group('PatientNotesService upload', () {
    test('uploadPatientNote returns a PatientNote on success', () async {
      final dir = Directory.systemTemp.createTempSync('grpI');
      final f = File('${dir.path}${Platform.pathSeparator}note.txt')
        ..writeAsStringSync('hello');
      try {
        final note = await http.runWithClient(
          () => PatientNotesService.uploadPatientNote(
            patientId: 3,
            file: f,
            title: 'Title',
            content: 'Body',
            category: 'labResult',
          ),
          () => MockClient((req) async => http.Response(
              jsonEncode({
                'data': {
                  'fileId': 42,
                  'originalFilename': 'note.txt',
                  'fileUrl': '/f/42',
                }
              }),
              200)),
        );
        expect(note, isNotNull);
        expect(note!.id, 42);
        expect(note.fileName, 'note.txt');
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });

  group('SubscriptionService.hasPremiumSubscription', () {
    Future<bool> run(WidgetTester tester, String body) async {
      _store['user_session'] = jsonEncode({'id': 10});
      ApiService.debugSetHttpClient(
          MockClient((req) async => http.Response(body, 200)));
      final provider = UserProvider();
      provider.setUser(UserSession(
        id: 10,
        email: 'cg@example.com',
        role: 'CAREGIVER',
        token: 'tok',
        name: 'CG',
      ));
      late BuildContext ctx;
      await tester.pumpWidget(ChangeNotifierProvider<UserProvider>.value(
        value: provider,
        child: MaterialApp(home: Builder(builder: (c) {
          ctx = c;
          return const SizedBox();
        })),
      ));
      final result = await tester.runAsync(
          () => SubscriptionService.hasPremiumSubscription(ctx));
      ApiService.debugResetHttpClient();
      return result!;
    }

    testWidgets('list with active premium plan → true', (tester) async {
      expect(
          await run(
              tester,
              jsonEncode([
                {'status': 'canceled', 'planName': 'basic'},
                {'status': 'ACTIVE', 'planName': 'premium monthly'},
              ])),
          isTrue);
    });

    testWidgets('map with active basic plan → false', (tester) async {
      expect(
          await run(tester,
              jsonEncode({'status': 'active', 'planName': 'basic'})),
          isFalse);
    });
  });
}
