// Coverage tests for the http-based ApiClient in
// lib/config/network/api_client.dart. Requests are intercepted with
// http.runWithClient so no network is touched.

import 'dart:convert';

import 'package:care_connect_app/config/network/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Future<T> _withClient<T>(
  Future<T> Function() body,
  Future<http.Response> Function(http.Request) handler,
) {
  return http.runWithClient(body, () => MockClient(handler));
}

void main() {
  final client = ApiClient();

  group('ApiClient.get', () {
    test('decodes a 200 body and sends JSON headers', () async {
      late http.Request seen;
      final result = await _withClient(
        () => client.get('/v1/api/thing'),
        (req) async {
          seen = req;
          return http.Response(jsonEncode({'ok': true}), 200);
        },
      );
      expect(result, {'ok': true});
      expect(seen.method, 'GET');
      expect(seen.url.path, '/v1/api/thing');
      expect(seen.headers['Accept'], 'application/json');
    });

    test('throws ApiException with status on non-200', () async {
      await expectLater(
        _withClient(
          () => client.get('/x'),
          (_) async => http.Response('nope', 404),
        ),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 404)
            .having((e) => e.message, 'message', contains('GET'))),
      );
    });

    test('wraps transport errors as network ApiException (status 0)',
        () async {
      await expectLater(
        _withClient(
          () => client.get('/x'),
          (_) async => throw http.ClientException('boom'),
        ),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 0)
            .having((e) => e.message, 'message', contains('Network error'))),
      );
    });
  });

  group('ApiClient.post', () {
    test('returns decoded body on 201 and encodes the payload', () async {
      late http.Request seen;
      final result = await _withClient(
        () => client.post('/p', {'a': 1}),
        (req) async {
          seen = req;
          return http.Response(jsonEncode({'id': 9}), 201);
        },
      );
      expect(result['id'], 9);
      expect(jsonDecode(seen.body), {'a': 1});
    });

    test('returns decoded body on 200', () async {
      final result = await _withClient(
        () => client.post('/p', {}),
        (_) async => http.Response(jsonEncode({'x': 'y'}), 200),
      );
      expect(result['x'], 'y');
    });

    test('throws ApiException on 500', () async {
      await expectLater(
        _withClient(
          () => client.post('/p', {}),
          (_) async => http.Response('err', 500),
        ),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 500)
            .having((e) => e.message, 'message', contains('POST'))),
      );
    });

    test('wraps malformed JSON as network ApiException', () async {
      await expectLater(
        _withClient(
          () => client.post('/p', {}),
          (_) async => http.Response('not json', 200),
        ),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 0)),
      );
    });
  });

  group('ApiClient.put', () {
    test('returns decoded body on 200', () async {
      late http.Request seen;
      final result = await _withClient(
        () => client.put('/u', {'n': 'v'}),
        (req) async {
          seen = req;
          return http.Response(jsonEncode({'updated': true}), 200);
        },
      );
      expect(result['updated'], isTrue);
      expect(seen.method, 'PUT');
    });

    test('throws ApiException on 409', () async {
      await expectLater(
        _withClient(
          () => client.put('/u', {}),
          (_) async => http.Response('', 409),
        ),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 409)
            .having((e) => e.message, 'message', contains('PUT'))),
      );
    });

    test('wraps transport errors', () async {
      await expectLater(
        _withClient(
          () => client.put('/u', {}),
          (_) async => throw StateError('down'),
        ),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 0)),
      );
    });
  });

  group('ApiClient.delete', () {
    test('returns success map for empty 204 body', () async {
      final result = await _withClient(
        () => client.delete('/d'),
        (_) async => http.Response('', 204),
      );
      expect(result, {'success': true});
    });

    test('decodes non-empty 200 body', () async {
      final result = await _withClient(
        () => client.delete('/d'),
        (req) async {
          expect(req.method, 'DELETE');
          return http.Response(jsonEncode({'deleted': 3}), 200);
        },
      );
      expect(result['deleted'], 3);
    });

    test('throws ApiException on 403', () async {
      await expectLater(
        _withClient(
          () => client.delete('/d'),
          (_) async => http.Response('', 403),
        ),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 403)
            .having((e) => e.message, 'message', contains('DELETE'))),
      );
    });

    test('wraps transport errors', () async {
      await expectLater(
        _withClient(
          () => client.delete('/d'),
          (_) async => throw http.ClientException('x'),
        ),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 0)),
      );
    });
  });
}
