// Breadth coverage for AIChatService edge paths: model parsing validation,
// askRecords network / cancel errors, confirmation submit, share listing,
// HITL polling and file analysis. HTTP is intercepted via runWithClient.

import 'dart:convert';
import 'dart:io';

import 'package:care_connect_app/services/ai_chat_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _uuid = '22222222-2222-2222-2222-222222222222';

const _delivered = <String, dynamic>{
  'disclaimer': {
    'text': 'AI generated',
    'aiNoticeRequired': true,
    'recordsBasedFraming': true,
    'locale': 'en-US',
  },
  'confirmation': {'promptConfirmWithProvider': false},
};

Future<T> _with<T>(
  Future<T> Function() body,
  Future<http.Response> Function(http.Request) handler,
) =>
    http.runWithClient(body, () => MockClient(handler));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    final expiry = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
    FlutterSecureStorage.setMockInitialValues({
      'jwt_token': 'ai-jwt',
      'token_expiry': '$expiry',
    });
  });

  group('model parsing', () {
    test('disclaimer rejects non-bool and empty strings', () {
      expect(
        () => AiAskDisclaimer.fromJson({
          'text': 'ok',
          'aiNoticeRequired': 'yes',
          'recordsBasedFraming': true,
          'locale': 'en',
        }),
        throwsFormatException,
      );
      expect(
        () => AiAskDisclaimer.fromJson({
          'text': '  ',
          'aiNoticeRequired': true,
          'recordsBasedFraming': true,
          'locale': 'en',
        }),
        throwsFormatException,
      );
    });

    test('escalation tier accepts whole doubles and rejects fractions', () {
      final e = AiAskEscalation.fromJson({
        'tier': 2.0,
        'reason': 'r',
        'requiresClinicianReview': true,
      });
      expect(e.tier, 2);
      expect(
        () => AiAskEscalation.fromJson({
          'tier': 2.5,
          'reason': 'r',
          'requiresClinicianReview': true,
        }),
        throwsFormatException,
      );
    });

    test('confirmation copyWith overrides and keeps fields', () {
      const c = AiAskConfirmation(false, 'a');
      expect(c.copyWith(required: true).required, isTrue);
      expect(c.copyWith(required: true).text, 'a');
      expect(c.copyWith(text: 'b').text, 'b');
    });

    test('error rejects non-list details', () {
      expect(
        () => AiAskError.fromJson({'code': 'X', 'message': 'm', 'details': 1}),
        throwsFormatException,
      );
    });

    test('medication timeline rejects non-string optional fields', () {
      expect(
        () => MedicationTimelineEvent.fromJson(
            {'medicationName': 'x', 'eventType': 5}),
        throwsFormatException,
      );
    });

    test('HitlPollHttpException toString and permanence', () {
      const e = HitlPollHttpException(404, 'gone');
      expect(e.toString(), 'gone');
      expect(e.isPermanent, isTrue);
    });

    test('HitlPollResult reads answer text from an object', () {
      final r = HitlPollResult.fromJson({
        'status': 'RELEASED',
        'deliveryStatus': 'DELIVERED',
        ..._delivered,
        'answer': {'text': '  Take with food. '},
      });
      expect(r.answer, 'Take with food.');
      final empty = HitlPollResult.fromJson({
        'status': 'RELEASED',
        'deliveryStatus': 'DELIVERED',
        ..._delivered,
        'answer': {'text': '  '},
      });
      expect(empty.answer, isNull);
      expect(
        () => HitlPollResult.fromJson({
          'status': 'RELEASED',
          'deliveryStatus': 'DELIVERED',
          'answer': {'text': 3},
        }),
        throwsFormatException,
      );
    });
  });

  group('askRecords failures', () {
    test('network errors are retryable NETWORK_ERROR results', () async {
      final r = await _with(
        () => AIChatService.askRecords(query: 'meds', patientId: 1),
        (_) async => throw http.ClientException('down'),
      );
      expect(r.success, isFalse);
      expect(r.error?.code, 'NETWORK_ERROR');
      expect(r.retryable, isTrue);
      expect(r.retryInput, 'meds');
    });

    test('an already-fired abort trigger yields CANCELLED', () async {
      final r = await _with(
        () => AIChatService.askRecords(
          query: 'meds',
          patientId: 1,
          abortTrigger: Future<void>.value(),
        ),
        (_) async => http.Response('{}', 200),
      );
      expect(r.error?.code, 'CANCELLED');
      expect(r.cancelled, isTrue);
    });
  });

  group('submitConfirmation', () {
    test('includes requestId and auditId and returns true on 2xx', () async {
      late http.Request seen;
      final ok = await _with(
        () => AIChatService.submitConfirmation(
          sessionId: 's',
          patientId: 3,
          requestId: 'r1',
          auditId: 'a1',
          decision: 'CONFIRM',
        ),
        (req) async {
          seen = req;
          return http.Response('{}', 204);
        },
      );
      expect(ok, isTrue);
      final body = jsonDecode(seen.body) as Map<String, dynamic>;
      expect(body['auditId'], 'a1');
      expect(body['requestId'], 'r1');
    });

    test('returns false when the request throws', () async {
      final ok = await _with(
        () => AIChatService.submitConfirmation(
            sessionId: 's', patientId: 3, decision: 'DECLINE'),
        (_) async => throw http.ClientException('x'),
      );
      expect(ok, isFalse);
    });
  });

  test('listShares converts numeric recipient ids', () async {
    final items = await _with(
      () => AIChatService.listShares(patientId: 9),
      (_) async => http.Response(
        jsonEncode([
          {
            'shareId': 'sh1',
            'patientId': 9,
            'recipientUserIds': [1, 2.0, 'x'],
          },
        ]),
        200,
      ),
    );
    expect(items.single.shareId, 'sh1');
    expect(items.single.recipientUserIds, [1, 2]);
  });

  test('pollHitlStatus rethrows client exceptions', () async {
    await expectLater(
      _with(
        () => AIChatService.pollHitlStatus(_uuid),
        (_) async => throw http.ClientException('down'),
      ),
      throwsA(isA<http.ClientException>()),
    );
  });

  group('analyzeFile', () {
    late Directory dir;
    late String path;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('ai_chat_cov');
      path = '${dir.path}${Platform.pathSeparator}note.txt';
      File(path).writeAsStringSync('hello');
    });

    tearDown(() => dir.deleteSync(recursive: true));

    test('returns the analysis text on 200', () async {
      late http.Request seen;
      final r = await _with(
        () => AIChatService.analyzeFile(
          filePath: path,
          userId: 'u1',
          question: 'q?',
          conversationId: 'c1',
        ),
        (req) async {
          seen = req;
          return http.Response(jsonEncode({'response': 'Looks fine'}), 200);
        },
      );
      expect(r, 'Looks fine');
      final body = latin1.decode(seen.bodyBytes);
      expect(body, contains('note.txt'));
      expect(body, contains('c1'));
    });

    test('uses default text when response field is missing', () async {
      final r = await _with(
        () => AIChatService.analyzeFile(filePath: path, userId: 'u1'),
        (_) async => http.Response('{}', 200),
      );
      expect(r, 'File analyzed successfully');
    });

    test('returns an apology on server error', () async {
      final r = await _with(
        () => AIChatService.analyzeFile(filePath: path, userId: 'u1'),
        (_) async => http.Response('', 500),
      );
      expect(r, startsWith('Sorry'));
    });
  });
}
