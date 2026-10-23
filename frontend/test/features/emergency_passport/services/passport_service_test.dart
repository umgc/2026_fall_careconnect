// CC-12 Increment 2: the patient's own passport calls. Test Plan §3.27:
// TC-EMG-267…271 and 459…461 (the pull request's), 295…298 and 468 (Testing
// Lead: timeout, refresh that fails, answers the screen cannot use, the retried
// header, turning off).

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:care_connect_app/config/env_constant.dart';
import 'package:care_connect_app/features/emergency_passport/services/passport_service.dart';

import '../passport_test_support.dart';

PassportService _service(
  Future<http.Response> Function(http.Request) handler, {
  Future<Object?> Function()? refresh,
}) =>
    PassportService(
      client: MockClient(handler),
      headers: () async => {'Authorization': 'Bearer test'},
      refresh: refresh ?? () async => null,
    );

Matcher _fails(PassportError error) => throwsA(
    isA<PassportException>().having((e) => e.error, 'error', error));

void main() {
  test('TC-EMG-267: GET /v1/api/passport with the sign-in header', () async {
    late http.Request sent;
    final v = await _service((req) async {
      sent = req;
      return http.Response(jsonEncode(passportJson), 200);
    }).getPassport();
    expect(sent.method, 'GET');
    expect(sent.url.path, '/v1/api/passport');
    expect(sent.headers['Authorization'], 'Bearer test');
    expect(v.name, 'Mary Johnson');
  });

  test('TC-EMG-268: POST /token returns the code once, with a working # link',
      () async {
    late http.Request sent;
    final code = await _service((req) async {
      sent = req;
      return http.Response(
          jsonEncode({
            'token': 'abc',
            'url': 'http://localhost:3000/passport/abc',
            'createdAt': '2026-10-15T18:00:00Z',
          }),
          201);
    }).makeNewCode();
    expect(sent.method, 'POST');
    expect(sent.url.path, '/v1/api/passport/token');
    expect(code.url, 'http://localhost:3000/#/passport/abc');
    expect(code.createdAt, DateTime.utc(2026, 10, 15, 18));
  });

  test('TC-EMG-269: a 401 refreshes the sign-in once and retries', () async {
    var calls = 0;
    final v = await _service((req) async {
      calls++;
      return calls == 1
          ? http.Response('', 401)
          : http.Response(jsonEncode(passportJson), 200);
    }, refresh: () async => 'new session').getPassport();
    expect(calls, 2);
    expect(v.name, 'Mary Johnson');
  });

  for (final c in [
    (401, PassportError.signedOut),
    (403, PassportError.notPatient),
    (409, PassportError.server),
    (500, PassportError.server),
  ]) {
    test('TC-EMG-270: HTTP ${c.$1} -> ${c.$2}', () async {
      expect(
        () => _service((_) async => http.Response('{"error":"x"}', c.$1))
            .makeNewCode(),
        _fails(c.$2),
      );
    });
  }

  test('TC-EMG-271: no answer from the server -> network', () async {
    expect(
      () => _service((_) async => throw http.ClientException('offline'))
          .getPassport(),
      _fails(PassportError.network),
    );
  });

  // ---------- Testing Lead ----------

  testWidgets(
      'TC-EMG-295: a server that never answers is "network" after 20 seconds, '
      'for both calls, and not before', (t) async {
    for (final call in <String, Future<Object> Function(PassportService)>{
      'GET': (s) => s.getPassport(),
      'POST': (s) => s.makeNewCode(),
    }.entries) {
      final never = Completer<http.Response>();
      Object? outcome;
      call.value(_service((_) => never.future)).then(
          (v) => outcome = v, onError: (Object e) => outcome = e);
      await t.pump(const Duration(seconds: 19));
      expect(outcome, isNull, reason: '${call.key} gave up early');
      await t.pump(const Duration(seconds: 2));
      expect(outcome,
          isA<PassportException>()
              .having((e) => e.error, 'error', PassportError.network),
          reason: call.key);
    }
  });

  test(
      'TC-EMG-296: a 401 is "signedOut" when the refresh gives no session, '
      'throws, or the retry is refused again, and the request is never sent '
      'more than twice', () async {
    for (final c in <String, (Future<Object?> Function(), int)>{
      'refresh gives no session': (() async => null, 1),
      'refresh throws': (() async => throw StateError('offline'), 1),
      'retry refused': (() async => 'new session', 2),
    }.entries) {
      var calls = 0;
      var refreshes = 0;
      final s = _service((_) async {
        calls++;
        return http.Response('', 401);
      }, refresh: () {
        refreshes++;
        return c.value.$1();
      });
      await expectLater(s.getPassport(), _fails(PassportError.signedOut),
          reason: c.key);
      expect(calls, c.value.$2, reason: c.key);
      expect(refreshes, 1, reason: c.key);
    }
  });

  test(
      'TC-EMG-297: answers the screen cannot use are "server": a new code '
      'without its code or link, 200 where 201 is expected, a body that is '
      'not a JSON object, and bytes that are not UTF-8', () async {
    final cases = <String, (int, List<int>, bool)>{
      'no token': (
        201,
        utf8.encode(jsonEncode({'url': 'http://x/#/passport/a'})),
        true
      ),
      'no url': (201, utf8.encode(jsonEncode({'token': 'a'})), true),
      'POST answered 200': (
        200,
        utf8.encode(jsonEncode(
            {'token': 'a', 'url': 'http://x/#/passport/a', 'createdAt': ''})),
        true
      ),
      'GET a list': (200, utf8.encode('[]'), false),
      'GET not JSON': (200, utf8.encode('<html>'), false),
      'GET not UTF-8': (200, [0xff, 0xfe, 0x7b], false),
      'GET 201': (201, utf8.encode(jsonEncode(passportJson)), false),
    };
    for (final c in cases.entries) {
      final s = _service((_) async => http.Response.bytes(c.value.$2, c.value.$1));
      await expectLater(
          c.value.$3 ? s.makeNewCode() : s.getPassport(),
          _fails(PassportError.server),
          reason: c.key);
    }
  });

  test(
      'TC-EMG-298: the retry after a refresh carries the new sign-in header, '
      'both calls go to the configured backend, and a name with accents '
      'survives the UTF-8 body', () async {
    var token = 'old';
    final sent = <http.Request>[];
    final s = PassportService(
      client: MockClient((req) async {
        sent.add(req);
        if (req.headers['Authorization'] == 'Bearer old') {
          return http.Response('', 401);
        }
        return http.Response.bytes(
            utf8.encode(jsonEncode({...passportJson, 'name': 'José Núñez'})),
            200);
      }),
      headers: () async => {'Authorization': 'Bearer $token'},
      refresh: () async {
        token = 'new';
        return 'session';
      },
    );
    final v = await s.getPassport();
    expect(v.name, 'José Núñez');
    expect(sent.map((r) => r.headers['Authorization']),
        ['Bearer old', 'Bearer new']);
    final backend = Uri.parse(getBackendBaseUrl());
    for (final r in sent) {
      expect(r.url.host, backend.host);
      expect(r.url.port, backend.port);
    }
  });

  group('turn off', () {
    test('TC-EMG-459: DELETE /v1/api/passport/token with the sign-in header', () async {
      late http.Request sent;
      await _service((req) async {
        sent = req;
        return http.Response('', 204);
      }).turnOffCode();
      expect(sent.method, 'DELETE');
      expect(sent.url.path, '/v1/api/passport/token');
      expect(sent.headers['Authorization'], 'Bearer test');
    });

    for (final c in [
      (401, PassportError.signedOut),
      (403, PassportError.notPatient),
      (500, PassportError.server),
    ]) {
      test('TC-EMG-460: HTTP ${c.$1} -> ${c.$2}', () async {
        expect(
            () => _service((_) async => http.Response('', c.$1)).turnOffCode(),
            _fails(c.$2));
      });
    }

    test('TC-EMG-461: no answer from the server -> network', () async {
      expect(
          () => _service((_) async => throw http.ClientException('offline'))
              .turnOffCode(),
          _fails(PassportError.network));
    });

    // ---------- Testing Lead ----------

    test(
        'TC-EMG-468: a 401 refreshes the sign-in once and sends DELETE again; '
        'a 200 is success like 204; a second 401 is signedOut', () async {
      final methods = <String>[];
      await _service((req) async {
        methods.add(req.method);
        return http.Response('', methods.length == 1 ? 401 : 204);
      }, refresh: () async => 'new session').turnOffCode();
      expect(methods, ['DELETE', 'DELETE']);

      await _service((_) async => http.Response('{}', 200)).turnOffCode();

      var calls = 0;
      await expectLater(
          _service((_) async {
            calls++;
            return http.Response('', 401);
          }, refresh: () async => 'new session').turnOffCode(),
          _fails(PassportError.signedOut));
      expect(calls, 2);
    });
  });
}
