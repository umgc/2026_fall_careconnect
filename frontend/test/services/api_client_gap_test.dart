// Gap-filling tests for lib/services/api_client.dart (the Dio based ApiClient).
//
// Why a fake adapter: ApiClient exposes debugSetHttpClientAdapter, so every
// request runs through the real interceptors (auth header, 2xx handling, error
// normalization) while the transport returns canned responses. No network.
// HttpOverrides is also swapped for a fake so the 401 refresh path and the
// fire-and-forget telemetry calls can never reach a real host.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:care_connect_app/services/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_http_overrides.dart';

typedef _Handler = FutureOr<ResponseBody> Function(RequestOptions options);

class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.handler);
  _Handler handler;
  final List<RequestOptions> seen = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    seen.add(options);
    // Consume the body so multipart temp files are released.
    await requestStream?.drain<void>();
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(int status, Object? body) => ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

void main() {
  late HttpClientAdapter original;
  late _ScriptedAdapter adapter;
  FakeResponse Function(String method, Uri uri) httpResponder =
      (m, u) => FakeResponse(500, '{}');

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    HttpOverrides.global = FakeHttpOverrides((m, u) => httpResponder(m, u));
    original = ApiClient.instance.debugHttpClientAdapter;
  });

  tearDownAll(() {
    ApiClient.instance.debugSetHttpClientAdapter(original);
    HttpOverrides.global = null;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    httpResponder = (m, u) => FakeResponse(500, '{}');
    adapter = _ScriptedAdapter((o) => _json(200, {'ok': true}));
    ApiClient.instance.debugSetHttpClientAdapter(adapter);
  });

  void signIn({String token = 'tok-1'}) {
    final exp =
        DateTime.now().add(const Duration(hours: 2)).millisecondsSinceEpoch ~/
            1000;
    FlutterSecureStorage.setMockInitialValues({
      'jwt_token': token,
      'token_expiry': '$exp',
    });
  }

  group('ApiException', () {
    test('toString reports status, code and message', () {
      final e = ApiException(status: 418, code: 'TEA', message: 'short');
      expect(e.toString(), 'ApiException(status=418, code=TEA, message=short)');
    });
  });

  group('verbs', () {
    test('getJson returns decoded body and sends query + JSON accept',
        () async {
      adapter.handler = (o) => _json(200, {'a': 1});
      final r = await ApiClient.instance
          .getJson<Map<String, dynamic>>('/x', query: {'q': 'v'});
      expect(r, {'a': 1});
      expect(adapter.seen.single.method, 'GET');
      expect(adapter.seen.single.queryParameters, {'q': 'v'});
      expect(adapter.seen.single.headers['Accept'], 'application/json');
    });

    test('getJson applies the parser to the response data', () async {
      adapter.handler = (o) => _json(200, {'n': 5});
      final r = await ApiClient.instance
          .getJson<int>('/x', parser: (j) => (j as Map)['n'] as int);
      expect(r, 5);
    });

    test('postJson sends body as JSON', () async {
      final r = await ApiClient.instance
          .postJson<Map<String, dynamic>>('/p', body: {'k': 'v'});
      expect(r['ok'], true);
      expect(adapter.seen.single.method, 'POST');
      expect(adapter.seen.single.data, {'k': 'v'});
    });

    test('putJson uses PUT', () async {
      await ApiClient.instance.putJson<dynamic>('/p', body: {'k': 1});
      expect(adapter.seen.single.method, 'PUT');
      expect(adapter.seen.single.data, {'k': 1});
    });

    test('patchJson uses PATCH', () async {
      await ApiClient.instance.patchJson<dynamic>('/p', body: [1]);
      expect(adapter.seen.single.method, 'PATCH');
    });

    test('deleteJson uses DELETE and forwards custom headers', () async {
      await ApiClient.instance
          .deleteJson<dynamic>('/p', headers: {'X-Test': 'yes'});
      expect(adapter.seen.single.method, 'DELETE');
      expect(adapter.seen.single.headers['X-Test'], 'yes');
    });
  });

  group('auth header interceptor', () {
    test('attaches Bearer token from storage', () async {
      signIn(token: 'abc');
      await ApiClient.instance.getJson<dynamic>('/x');
      expect(adapter.seen.single.headers['Authorization'], 'Bearer abc');
    });

    test('does not override an explicit Authorization header', () async {
      signIn(token: 'abc');
      await ApiClient.instance
          .getJson<dynamic>('/x', headers: {'Authorization': 'Custom z'});
      expect(adapter.seen.single.headers['Authorization'], 'Custom z');
    });

    test('sends no Authorization header when signed out', () async {
      await ApiClient.instance.getJson<dynamic>('/x');
      expect(adapter.seen.single.headers.containsKey('Authorization'), isFalse);
    });
  });

  group('non-2xx responses', () {
    Future<ApiException> failure(int status, Object? body) async {
      adapter.handler = (o) => _json(status, body);
      try {
        await ApiClient.instance.getJson<dynamic>('/bad');
      } on DioException catch (e) {
        expect(e.type, DioExceptionType.badResponse);
        expect(e.response?.statusCode, status);
        return e.error as ApiException;
      }
      fail('expected DioException');
    }

    test('maps message and code from a JSON map body', () async {
      final e = await failure(400, {'message': 'bad input', 'code': 'E42'});
      expect(e.status, 400);
      expect(e.message, 'bad input');
      expect(e.code, 'E42');
    });

    test('falls back to the error field, then detail', () async {
      expect((await failure(400, {'error': 'boom'})).message, 'boom');
      expect((await failure(422, {'detail': 'dd'})).message, 'dd');
    });

    test('uses a plain string body as the message', () async {
      adapter.handler = (o) => ResponseBody.fromString(
            'server exploded',
            500,
            headers: {
              Headers.contentTypeHeader: ['text/plain'],
            },
          );
      try {
        await ApiClient.instance.getJson<dynamic>('/bad');
        fail('expected DioException');
      } on DioException catch (e) {
        final api = e.error as ApiException;
        expect(api.message, 'server exploded');
        expect(api.code, isNull);
      }
    });

    test('uses HTTP <status> when the body has no message', () async {
      final e = await failure(503, {'other': 1});
      expect(e.message, 'HTTP 503');
    });

    test('empty string body falls back to HTTP <status>', () async {
      adapter.handler = (o) => ResponseBody.fromString('', 404);
      try {
        await ApiClient.instance.getJson<dynamic>('/bad');
        fail('expected DioException');
      } on DioException catch (e) {
        expect((e.error as ApiException).message, 'HTTP 404');
      }
    });
  });

  group('401 handling', () {
    // NOTE: validateStatus accepts every status below 600, so Dio itself never
    // raises a bad-response error; the onResponse hook rejects non-2xx instead,
    // and Dio does not route that rejection into the same interceptor's
    // onError. These tests therefore drive the refresh branch with an adapter
    // that throws a 401 DioException, which is the only way onError sees one.
    DioException unauthorized(RequestOptions o) => DioException(
          requestOptions: o,
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: o,
            statusCode: 401,
            data: {'message': 'expired'},
          ),
        );

    test('refresh success retries the request once with the new token',
        () async {
      signIn(token: 'old');
      final hits = <String>[];
      httpResponder = (m, u) {
        hits.add('$m ${u.path}');
        return FakeResponse(
          200,
          jsonEncode({
            'id': 7,
            'email': 'a@b.c',
            'role': 'PATIENT',
            'token': 'new-tok',
          }),
        );
      };
      adapter.handler = (o) {
        if (o.extra['__ret'] == true) return _json(200, {'retried': true});
        throw unauthorized(o);
      };

      final r = await ApiClient.instance.getJson<Map<String, dynamic>>('/s');

      expect(r, {'retried': true});
      expect(hits.single, endsWith('/refresh-token'));
      expect(adapter.seen, hasLength(2));
      expect(adapter.seen.last.headers['Authorization'], 'Bearer new-tok');
    });

    test('a retried request that fails again is not refreshed twice', () async {
      signIn(token: 'old');
      var refreshes = 0;
      httpResponder = (m, u) {
        refreshes++;
        return FakeResponse(
          200,
          jsonEncode({
            'id': 7,
            'email': 'a@b.c',
            'role': 'PATIENT',
            'token': 'new-tok',
          }),
        );
      };
      adapter.handler = (o) => throw unauthorized(o);

      await expectLater(
        ApiClient.instance.getJson<dynamic>('/s'),
        throwsA(isA<DioException>()
            .having((e) => (e.error as ApiException).status, 'status', 401)),
      );
      expect(refreshes, 1);
      expect(adapter.seen, hasLength(2));
    });

    test('failed refresh (backend 500) surfaces the 401 and clears auth',
        () async {
      signIn();
      httpResponder = (m, u) => FakeResponse(500, '{}');
      adapter.handler = (o) => throw unauthorized(o);
      await expectLater(
        ApiClient.instance.getJson<dynamic>('/secure'),
        throwsA(isA<DioException>().having(
            (e) => (e.error as ApiException).message, 'msg', 'expired')),
      );
      expect(adapter.seen, hasLength(1));
      expect(await const FlutterSecureStorage().read(key: 'jwt_token'), isNull);
    });

    test('signed out: 401 is surfaced without any refresh call', () async {
      var refreshes = 0;
      httpResponder = (m, u) {
        refreshes++;
        return FakeResponse(500, '{}');
      };
      adapter.handler = (o) => throw unauthorized(o);
      await expectLater(
        ApiClient.instance.getJson<dynamic>('/secure'),
        throwsA(isA<DioException>()),
      );
      expect(refreshes, 0);
      expect(adapter.seen, hasLength(1));
    });
  });

  group('transport errors', () {
    Future<DioException> thrownFor(
      DioException Function(RequestOptions) make, {
      String path = '/x',
    }) async {
      adapter.handler = (o) => throw make(o);
      try {
        await ApiClient.instance.getJson<dynamic>(path);
      } on DioException catch (e) {
        return e;
      }
      fail('expected DioException');
    }

    for (final t in [
      DioExceptionType.connectionTimeout,
      DioExceptionType.sendTimeout,
      DioExceptionType.receiveTimeout,
    ]) {
      test('$t becomes "Network timeout"', () async {
        final e =
            await thrownFor((o) => DioException(requestOptions: o, type: t));
        expect(e.type, t);
        expect((e.error as ApiException).message, 'Network timeout');
      });
    }

    test('cancel becomes "Request cancelled"', () async {
      final e = await thrownFor((o) =>
          DioException(requestOptions: o, type: DioExceptionType.cancel));
      expect(e.type, DioExceptionType.cancel);
      expect((e.error as ApiException).message, 'Request cancelled');
    });

    test('SocketException becomes "No internet connection"', () async {
      final e = await thrownFor((o) => DioException(
            requestOptions: o,
            type: DioExceptionType.unknown,
            error: const SocketException('down'),
          ));
      expect(e.type, DioExceptionType.connectionError);
      expect((e.error as ApiException).message, 'No internet connection');
    });

    test('connectionError type without a socket error gets the generic message',
        () async {
      final e = await thrownFor((o) => DioException(
            requestOptions: o,
            type: DioExceptionType.connectionError,
            message: 'refused',
            error: 'refused',
          ));
      expect((e.error as ApiException).message, 'Network error: refused');
    });

    test('unknown error gets a generic "Network error" message', () async {
      final e = await thrownFor((o) => DioException(
            requestOptions: o,
            type: DioExceptionType.unknown,
            message: 'weird',
            error: StateError('x'),
          ));
      expect(e.type, DioExceptionType.unknown);
      expect((e.error as ApiException).message, 'Network error: weird');
    });

    test('unknown error that looks like a network failure is normalised',
        () async {
      final e = await thrownFor((o) => DioException(
            requestOptions: o,
            type: DioExceptionType.unknown,
            message: 'lost',
            error: Exception('Connection refused by host'),
          ));
      expect((e.error as ApiException).message, 'Network error: lost');
    });

    test('telemetry endpoint errors are normalised without recording',
        () async {
      final e = await thrownFor(
        (o) => DioException(
            requestOptions: o, type: DioExceptionType.connectionTimeout),
        path: '/v1/api/dev/telemetry',
      );
      expect((e.error as ApiException).message, 'Network timeout');
    });
  });

  group('timeouts helper', () {
    test('debugSetTimeouts arms short timeouts that reach requests', () async {
      ApiClient.instance.debugSetTimeouts(
        connect: const Duration(milliseconds: 7),
        receive: const Duration(milliseconds: 8),
        send: const Duration(milliseconds: 9),
      );
      await ApiClient.instance.getJson<dynamic>('/x');
      final o = adapter.seen.single;
      expect(o.connectTimeout, const Duration(milliseconds: 7));
      expect(o.receiveTimeout, const Duration(milliseconds: 8));
      expect(o.sendTimeout, const Duration(milliseconds: 9));
    });
  });

  group('uploadMultipart', () {
    late Directory dir;
    late File file;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('api_client_gap');
      file = File('${dir.path}${Platform.pathSeparator}note.txt');
      await file.writeAsString('hello');
    });

    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    test('posts FormData with the file and extra fields', () async {
      final r = await ApiClient.instance.uploadMultipart<Map<String, dynamic>>(
        '/upload',
        files: {'doc': file},
        fields: {'title': 'T'},
        headers: {'X-Up': '1'},
      );
      expect(r['ok'], true);
      final o = adapter.seen.single;
      expect(o.method, 'POST');
      expect(o.headers['X-Up'], '1');
      final form = o.data as FormData;
      expect(form.fields.map((f) => f.key), contains('title'));
      expect(form.files.single.key, 'doc');
      expect(form.files.single.value.filename, 'note.txt');
    });

    test('works without extra fields', () async {
      await ApiClient.instance
          .uploadMultipart<dynamic>('/upload', files: {'doc': file});
      final form = adapter.seen.single.data as FormData;
      expect(form.fields, isEmpty);
      expect(form.files, hasLength(1));
    });
  });
}
