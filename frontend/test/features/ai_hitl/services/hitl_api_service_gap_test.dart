// Gap coverage for HitlApiService: fetchDetail, reject, error mapping, bad
// payload shapes, UUID validation and timeouts. All HTTP goes through
// http.testing MockClient; secure storage is stubbed so no platform channel
// or network is touched.
import 'dart:async';
import 'dart:convert';

import 'package:care_connect_app/features/ai_hitl/models/hitl_models.dart';
import 'package:care_connect_app/features/ai_hitl/services/hitl_api_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const heldId = '22222222-2222-2222-2222-222222222222';
  final svc = HitlApiService.instance;

  Map<String, dynamic> detailJson({String status = 'RELEASED'}) => {
        'heldItemId': heldId,
        'patientId': 7,
        'status': status,
        'deliveryStatus': 'DELIVERED',
        'triggerCodes': ['LOW_CONFIDENCE'],
        'queryText': 'Q',
        'finalAnswer': 'Final',
      };

  Future<http.Response> slow(Object body) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    return http.Response(jsonEncode(body), 200);
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('fetchDetail', () {
    test('GETs the item with Accept header and parses the detail', () async {
      late http.Request seen;
      final client = MockClient((request) async {
        seen = request;
        return http.Response(
          jsonEncode(detailJson(status: 'PENDING_REVIEW')),
          200,
        );
      });
      final detail = await svc.fetchDetail(heldId, client: client);
      expect(seen.method, 'GET');
      expect(seen.url.path, endsWith('/v1/api/ai/hitl/$heldId'));
      expect(seen.headers['Accept'], 'application/json');
      expect(detail.isPending, isTrue);
      expect(detail.requiresEditedAnswer, isFalse);
      expect(detail.finalAnswer, 'Final');
    });

    test('rejects a non-UUID id before any request is made', () async {
      var called = false;
      final client = MockClient((request) async {
        called = true;
        return http.Response('{}', 200);
      });
      await expectLater(
        svc.fetchDetail('not-a-uuid', client: client),
        throwsA(isA<FormatException>()),
      );
      expect(called, isFalse);
    });

    test('throws FormatException when the body is not an object', () async {
      final client = MockClient((_) async => http.Response('[]', 200));
      await expectLater(
        svc.fetchDetail(heldId, client: client),
        throwsA(isA<FormatException>()),
      );
    });

    test('maps an error body to HitlApiException with code and message',
        () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({'message': '  Not yours  ', 'error': 'FORBIDDEN'}),
          403,
        ),
      );
      await expectLater(
        svc.fetchDetail(heldId, client: client),
        throwsA(
          isA<HitlApiException>()
              .having((e) => e.statusCode, 'status', 403)
              .having((e) => e.message, 'message', 'Not yours')
              .having((e) => e.errorCode, 'code', 'FORBIDDEN'),
        ),
      );
    });

    test('uses a default message when the error body is not JSON', () async {
      final client = MockClient((_) async => http.Response('boom', 500));
      await expectLater(
        svc.fetchDetail(heldId, client: client),
        throwsA(
          isA<HitlApiException>()
              .having(
                (e) => e.message,
                'message',
                'HITL detail failed with HTTP 500',
              )
              .having((e) => e.errorCode, 'code', isNull),
        ),
      );
    });

    test('propagates a TimeoutException when the server is too slow', () async {
      final client = MockClient((_) => slow(detailJson()));
      await expectLater(
        svc.fetchDetail(
          heldId,
          client: client,
          timeout: const Duration(milliseconds: 10),
        ),
        throwsA(isA<TimeoutException>()),
      );
    });
  });

  group('fetchQueue', () {
    test('throws FormatException when the body is not a list', () async {
      final client = MockClient((_) async => http.Response('{}', 200));
      await expectLater(
        svc.fetchQueue(client: client),
        throwsA(isA<FormatException>()),
      );
    });

    test('skips non-object entries and surfaces HTTP failures', () async {
      final ok = MockClient(
        (_) async => http.Response(
          jsonEncode([
            'junk',
            {'heldItemId': heldId, 'patientId': 3.0},
          ]),
          200,
        ),
      );
      final items = await svc.fetchQueue(client: ok);
      expect(items, hasLength(1));
      expect(items.single.patientId, 3);

      final bad = MockClient((_) async => http.Response('{}', 401));
      await expectLater(
        svc.fetchQueue(client: bad),
        throwsA(
          isA<HitlApiException>().having((e) => e.statusCode, 'status', 401),
        ),
      );
    });

    test('times out when the server is slow', () async {
      final client = MockClient((_) => slow(<String>[]));
      await expectLater(
        svc.fetchQueue(
          client: client,
          timeout: const Duration(milliseconds: 10),
        ),
        throwsA(isA<TimeoutException>()),
      );
    });
  });

  group('release', () {
    test('sends only the fields provided and parses the response', () async {
      late http.Request seen;
      final client = MockClient((request) async {
        seen = request;
        return http.Response(jsonEncode(detailJson()), 200);
      });
      final detail = await svc.release(heldId, notes: 'ok', client: client);
      expect(seen.method, 'POST');
      expect(seen.url.path, endsWith('/$heldId/release'));
      expect(seen.headers['Content-Type'], contains('application/json'));
      expect(jsonDecode(seen.body), {'notes': 'ok'});
      expect(detail.status, 'RELEASED');
    });

    test('rejects bad ids, bad shapes and server errors', () async {
      final shape = MockClient((_) async => http.Response('"x"', 200));
      await expectLater(
        svc.release(heldId, client: shape),
        throwsA(isA<FormatException>()),
      );
      await expectLater(
        svc.release('nope', client: shape),
        throwsA(isA<FormatException>()),
      );
      final conflict = MockClient(
        (_) async =>
            http.Response(jsonEncode({'message': 'Already released'}), 409),
      );
      await expectLater(
        svc.release(heldId, client: conflict),
        throwsA(
          isA<HitlApiException>().having(
            (e) => e.message,
            'message',
            'Already released',
          ),
        ),
      );
    });

    test('times out when the server is slow', () async {
      final client = MockClient((_) => slow(detailJson()));
      await expectLater(
        svc.release(
          heldId,
          client: client,
          timeout: const Duration(milliseconds: 10),
        ),
        throwsA(isA<TimeoutException>()),
      );
    });
  });

  group('reject', () {
    test('posts the reason and parses the rejected item', () async {
      late http.Request seen;
      final client = MockClient((request) async {
        seen = request;
        return http.Response(jsonEncode(detailJson(status: 'REJECTED')), 200);
      });
      final detail = await svc.reject(
        heldId,
        reason: 'Unsafe advice',
        client: client,
      );
      expect(seen.url.path, endsWith('/$heldId/reject'));
      expect(jsonDecode(seen.body), {'reason': 'Unsafe advice'});
      expect(detail.status, 'REJECTED');
    });

    test('sends an empty object when no reason is given', () async {
      late http.Request seen;
      final client = MockClient((request) async {
        seen = request;
        return http.Response(jsonEncode(detailJson(status: 'REJECTED')), 200);
      });
      await svc.reject(heldId, client: client);
      expect(jsonDecode(seen.body), isEmpty);
    });

    test('rejects bad ids, bad shapes, server errors and slow servers',
        () async {
      final shape = MockClient((_) async => http.Response('[]', 200));
      await expectLater(
        svc.reject(heldId, client: shape),
        throwsA(isA<FormatException>()),
      );
      await expectLater(
        svc.reject('x', client: shape),
        throwsA(isA<FormatException>()),
      );
      final err = MockClient((_) async => http.Response('', 500));
      await expectLater(
        svc.reject(heldId, client: err),
        throwsA(
          isA<HitlApiException>().having(
            (e) => e.toString(),
            'toString',
            'HITL reject failed with HTTP 500',
          ),
        ),
      );
      final slowClient = MockClient((_) => slow(detailJson()));
      await expectLater(
        svc.reject(
          heldId,
          client: slowClient,
          timeout: const Duration(milliseconds: 10),
        ),
        throwsA(isA<TimeoutException>()),
      );
    });
  });
}
