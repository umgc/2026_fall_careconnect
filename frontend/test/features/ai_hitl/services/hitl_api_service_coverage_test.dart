// Additional coverage for HitlApiService: fetchDetail, owned-client paths
// (no client injected -> http.Client() via runWithClient), error rethrows and
// the _throwIfFailed message/error-code parsing.

import 'dart:async';
import 'dart:convert';

import 'package:care_connect_app/features/ai_hitl/models/hitl_models.dart';
import 'package:care_connect_app/features/ai_hitl/services/hitl_api_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _id = '11111111-1111-1111-1111-111111111111';

Map<String, dynamic> _detail({String status = 'PENDING_REVIEW'}) => {
      'heldItemId': _id,
      'patientId': 42,
      'status': status,
      'deliveryStatus': 'HELD',
      'triggerCodes': ['EMERGENCY'],
      'queryText': 'Q',
      'draftAnswer': 'Draft',
    };

MockClient _json(Object body, [int status = 200]) =>
    MockClient((_) async => http.Response(jsonEncode(body), status));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final svc = HitlApiService.instance;

  setUp(() {
    final expiry = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
    FlutterSecureStorage.setMockInitialValues({
      'jwt_token': 'hitl-jwt',
      'token_expiry': '$expiry',
    });
  });

  group('fetchQueue', () {
    test('uses an owned client when none is injected', () async {
      late http.Request seen;
      final items = await http.runWithClient(
        () => svc.fetchQueue(),
        () => MockClient((req) async {
          seen = req;
          return http.Response(
            jsonEncode([
              {
                'heldItemId': _id,
                'patientId': 1,
                'triggerCodes': <String>[],
                'queryPreview': 'p',
              },
              'skip-me',
            ]),
            200,
          );
        }),
      );
      expect(items.single.heldItemId, _id);
      expect(seen.headers['Authorization'], 'Bearer hitl-jwt');
      expect(seen.headers['Accept'], 'application/json');
    });

    test('rethrows FormatException for non-list body', () async {
      await expectLater(
        svc.fetchQueue(client: _json({'items': []})),
        throwsA(isA<FormatException>()),
      );
    });

    test('rethrows HitlApiException with server message + error code',
        () async {
      await expectLater(
        svc.fetchQueue(
          client: _json({'message': '  Nope  ', 'error': ' FORBIDDEN '}, 403),
        ),
        throwsA(isA<HitlApiException>()
            .having((e) => e.statusCode, 'statusCode', 403)
            .having((e) => e.message, 'message', 'Nope')
            .having((e) => e.errorCode, 'errorCode', 'FORBIDDEN')),
      );
    });

    test('keeps default message for non-JSON error body', () async {
      final client = MockClient((_) async => http.Response('<html>', 500));
      await expectLater(
        svc.fetchQueue(client: client),
        throwsA(isA<HitlApiException>()
            .having((e) => e.message, 'message', contains('queue failed'))
            .having((e) => e.errorCode, 'errorCode', isNull)),
      );
    });

    test('keeps default message for blank message fields', () async {
      await expectLater(
        svc.fetchQueue(client: _json({'message': '   ', 'error': ''}, 400)),
        throwsA(isA<HitlApiException>()
            .having((e) => e.message, 'message', contains('HTTP 400'))),
      );
    });

    test('rethrows TimeoutException', () async {
      final never = MockClient((_) => Completer<http.Response>().future);
      await expectLater(
        svc.fetchQueue(
            client: never, timeout: const Duration(milliseconds: 1)),
        throwsA(isA<TimeoutException>()),
      );
    });
  });

  group('fetchDetail', () {
    test('rejects non-UUID ids before any request', () async {
      await expectLater(
        svc.fetchDetail('not-a-uuid', client: _json(_detail())),
        throwsA(isA<FormatException>()),
      );
    });

    test('parses the detail with an injected client', () async {
      late http.Request seen;
      final detail = await svc.fetchDetail(
        _id,
        client: MockClient((req) async {
          seen = req;
          return http.Response(jsonEncode(_detail()), 200);
        }),
      );
      expect(detail.heldItemId, _id);
      expect(detail.isPending, isTrue);
      expect(seen.url.path, endsWith('/v1/api/ai/hitl/$_id'));
    });

    test('parses the detail with an owned client', () async {
      final detail = await http.runWithClient(
        () => svc.fetchDetail(_id),
        () => _json(_detail(status: 'RELEASED')),
      );
      expect(detail.status, 'RELEASED');
    });

    test('rethrows FormatException for non-object body', () async {
      await expectLater(
        svc.fetchDetail(_id, client: _json([1])),
        throwsA(isA<FormatException>()),
      );
    });

    test('rethrows HitlApiException on 404', () async {
      await expectLater(
        svc.fetchDetail(_id, client: _json({'message': 'gone'}, 404)),
        throwsA(isA<HitlApiException>()
            .having((e) => e.statusCode, 'statusCode', 404)),
      );
    });

    test('rethrows TimeoutException', () async {
      final never = MockClient((_) => Completer<http.Response>().future);
      await expectLater(
        svc.fetchDetail(_id,
            client: never, timeout: const Duration(milliseconds: 1)),
        throwsA(isA<TimeoutException>()),
      );
    });
  });

  group('release', () {
    test('owned client posts notes + editedAnswer', () async {
      late http.Request seen;
      final detail = await http.runWithClient(
        () => svc.release(_id, editedAnswer: 'E', notes: 'N'),
        () => MockClient((req) async {
          seen = req;
          return http.Response(jsonEncode(_detail(status: 'RELEASED')), 200);
        }),
      );
      expect(detail.status, 'RELEASED');
      expect(jsonDecode(seen.body), {'editedAnswer': 'E', 'notes': 'N'});
      expect(seen.url.path, endsWith('/release'));
    });

    test('sends an empty body when nothing provided', () async {
      late http.Request seen;
      await svc.release(
        _id,
        client: MockClient((req) async {
          seen = req;
          return http.Response(jsonEncode(_detail()), 200);
        }),
      );
      expect(jsonDecode(seen.body), <String, dynamic>{});
    });

    test('rejects invalid ids', () async {
      await expectLater(
        svc.release('bad', client: _json(_detail())),
        throwsA(isA<FormatException>()),
      );
    });

    test('rethrows FormatException for non-object body', () async {
      await expectLater(
        svc.release(_id, client: _json('str')),
        throwsA(isA<FormatException>()),
      );
    });

    test('rethrows HitlApiException', () async {
      await expectLater(
        svc.release(_id, client: _json({'error': 'CONFLICT'}, 409)),
        throwsA(isA<HitlApiException>()
            .having((e) => e.errorCode, 'errorCode', 'CONFLICT')),
      );
    });

    test('rethrows TimeoutException', () async {
      final never = MockClient((_) => Completer<http.Response>().future);
      await expectLater(
        svc.release(_id,
            client: never, timeout: const Duration(milliseconds: 1)),
        throwsA(isA<TimeoutException>()),
      );
    });
  });

  group('reject', () {
    test('owned client posts reason', () async {
      late http.Request seen;
      final detail = await http.runWithClient(
        () => svc.reject(_id, reason: 'unsafe'),
        () => MockClient((req) async {
          seen = req;
          return http.Response(jsonEncode(_detail(status: 'REJECTED')), 200);
        }),
      );
      expect(detail.status, 'REJECTED');
      expect(jsonDecode(seen.body), {'reason': 'unsafe'});
      expect(seen.url.path, endsWith('/reject'));
    });

    test('sends empty body without reason', () async {
      late http.Request seen;
      await svc.reject(
        _id,
        client: MockClient((req) async {
          seen = req;
          return http.Response(jsonEncode(_detail()), 200);
        }),
      );
      expect(jsonDecode(seen.body), <String, dynamic>{});
    });

    test('rejects invalid ids', () async {
      await expectLater(
        svc.reject('bad', client: _json(_detail())),
        throwsA(isA<FormatException>()),
      );
    });

    test('rethrows FormatException for non-object body', () async {
      await expectLater(
        svc.reject(_id, client: _json([])),
        throwsA(isA<FormatException>()),
      );
    });

    test('rethrows HitlApiException', () async {
      await expectLater(
        svc.reject(_id, client: _json({}, 500)),
        throwsA(isA<HitlApiException>()
            .having((e) => e.message, 'message', contains('reject failed'))),
      );
    });

    test('rethrows TimeoutException', () async {
      final never = MockClient((_) => Completer<http.Response>().future);
      await expectLater(
        svc.reject(_id, client: never, timeout: const Duration(milliseconds: 1)),
        throwsA(isA<TimeoutException>()),
      );
    });
  });
}
