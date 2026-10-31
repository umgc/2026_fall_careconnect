// Additional coverage for the Dio-based ApiClient: bearer-token injection,
// multipart upload, 401 refresh + retry, and network-error normalisation /
// telemetry. A scripted HttpClientAdapter replaces the network.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:care_connect_app/services/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef _Fetch = Future<ResponseBody> Function(RequestOptions options);

class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.fetchFn);
  _Fetch fetchFn;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (requestStream != null) {
      await requestStream.drain<void>();
    }
    return fetchFn(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object body, [int status = 200]) => ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

ApiException _apiErrorOf(Object e) =>
    (e as DioException).error as ApiException;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final client = ApiClient.instance;
  late HttpClientAdapter original;
  late _ScriptedAdapter adapter;

  setUpAll(() {
    original = client.debugHttpClientAdapter;
  });

  tearDownAll(() {
    client.debugSetHttpClientAdapter(original);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final expiry = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
    FlutterSecureStorage.setMockInitialValues({
      'jwt_token': 'dio-jwt',
      'token_expiry': '$expiry',
    });
    adapter = _ScriptedAdapter((_) async => _json({'ok': true}));
    client.debugSetHttpClientAdapter(adapter);
  });

  // Swallow any telemetry / refresh HTTP traffic.
  Future<T> quiet<T>(Future<T> Function() body,
          [Future<http.Response> Function(http.Request)? h]) =>
      http.runWithClient(
          body,
          () => MockClient(
              h ?? (_) async => http.Response('{"enabled":false}', 200)));

  test('attaches the stored bearer token', () async {
    final r = await quiet(() => client.getJson<Map<String, dynamic>>('/a'));
    expect(r['ok'], isTrue);
    expect(adapter.requests.single.headers['Authorization'], 'Bearer dio-jwt');
  });

  test('uploadMultipart sends fields and files', () async {
    final dir = Directory.systemTemp.createTempSync('api_client_cov');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}${Platform.pathSeparator}up.txt')
      ..writeAsStringSync('content');

    final r = await quiet(() => client.uploadMultipart<Map<String, dynamic>>(
          '/upload',
          files: {'file': file},
          fields: {'category': 'docs'},
          parser: (j) => Map<String, dynamic>.from(j as Map),
        ));
    expect(r['ok'], isTrue);
    final req = adapter.requests.single;
    expect(req.data, isA<FormData>());
    final form = req.data as FormData;
    expect(form.fields.single.value, 'docs');
    expect(form.files.single.value.filename, 'up.txt');
  });

  test('401 refreshes the token and retries once', () async {
    var calls = 0;
    adapter.fetchFn = (o) async {
      calls++;
      if (calls == 1) {
        // Errors thrown by the adapter reach the onError interceptor.
        throw DioException(
          requestOptions: o,
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: o,
            statusCode: 401,
            data: {'error': 'expired'},
          ),
        );
      }
      return _json({'n': 2});
    };
    final r = await quiet(
      () => client.getJson<Map<String, dynamic>>('/secure'),
      (req) async => req.url.path.endsWith('/refresh-token')
          ? http.Response(
              jsonEncode({
                'id': 1,
                'email': 'a@b.c',
                'role': 'PATIENT',
                'token': 'new-jwt',
              }),
              200)
          : http.Response('{}', 200),
    );
    expect(r['n'], 2);
    expect(adapter.requests, hasLength(2));
    expect(adapter.requests.last.extra['__ret'], isTrue);
    expect(adapter.requests.last.headers['Authorization'], 'Bearer new-jwt');
  });

  group('network error normalisation', () {
    Future<ApiException> failWith(Object error, {String path = '/x'}) async {
      adapter.fetchFn = (o) async {
        if (error is DioExceptionType) {
          throw DioException(requestOptions: o, type: error);
        }
        throw error;
      };
      try {
        await quiet(() => client.getJson<dynamic>(path));
      } catch (e) {
        return _apiErrorOf(e);
      }
      fail('expected an error');
    }

    test('timeouts map to Network timeout', () async {
      for (final t in [
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
      ]) {
        expect((await failWith(t)).message, 'Network timeout');
      }
    });

    test('cancel maps to Request cancelled', () async {
      expect((await failWith(DioExceptionType.cancel)).message,
          'Request cancelled');
    });

    test('socket errors map to No internet connection', () async {
      expect((await failWith(const SocketException('down'))).message,
          'No internet connection');
    });

    test('connection errors without socket fall back to Network error',
        () async {
      expect((await failWith(DioExceptionType.connectionError)).message,
          startsWith('Network error'));
    });

    test('unknown network-like errors fall back to Network error', () async {
      expect(
          (await failWith(const HttpException('Connection closed'))).message,
          startsWith('Network error'));
    });

    test('telemetry endpoints skip telemetry recording', () async {
      expect(
          (await failWith(DioExceptionType.connectionTimeout,
                  path: '/v1/api/dev/telemetry'))
              .message,
          'Network timeout');
    });
  });
}
