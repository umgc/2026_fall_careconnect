// Test-only HTTP interception (no app-code changes).
//
// `package:http`'s top-level functions (http.post/get/...) create an IOClient
// backed by a dart:io HttpClient. By installing an HttpOverrides we hand back a
// fake HttpClient that returns canned responses — so auth calls that bypass the
// ApiService seam (e.g. AuthService.resetPassword's direct http.post) can be
// driven deterministically in unit/widget tests.
//
// Usage:
//   setUp(() => HttpOverrides.global =
//       FakeHttpOverrides((method, uri) => FakeResponse(200, '{"message":"ok"}')));
//   tearDown(() => HttpOverrides.global = null);

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// What the fake should return for a given request.
class FakeResponse {
  FakeResponse(this.statusCode, this.body);
  final int statusCode;
  final String body;
}

typedef FakeResponder = FakeResponse Function(String method, Uri uri);

class FakeHttpOverrides extends HttpOverrides {
  FakeHttpOverrides(this.responder);
  final FakeResponder responder;

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _FakeHttpClient(responder);
}

class _FakeHttpClient implements HttpClient {
  _FakeHttpClient(this.responder);
  final FakeResponder responder;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _FakeHttpClientRequest(method, url, responder);

  // Tolerate every other member (property setters, close(), etc.).
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeHttpClientRequest implements HttpClientRequest {
  _FakeHttpClientRequest(this.method, this.uri, this.responder);
  final String method;
  final Uri uri;
  final FakeResponder responder;

  @override
  final HttpHeaders headers = _FakeHttpHeaders();

  @override
  void add(List<int> data) {}

  @override
  Future<dynamic> addStream(Stream<List<int>> stream) => stream.drain();

  @override
  Future<HttpClientResponse> close() async {
    final r = responder(method, uri);
    return _FakeHttpClientResponse(r.statusCode, r.body);
  }

  @override
  Future<HttpClientResponse> get done => close();

  // Tolerate followRedirects/maxRedirects/contentLength/... setters.
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _FakeHttpClientResponse(this.statusCode, this._body);
  @override
  final int statusCode;
  final String _body;

  late final List<int> _bytes = utf8.encode(_body);

  @override
  int get contentLength => _bytes.length;
  @override
  String get reasonPhrase => statusCode == 200 ? 'OK' : 'Error';
  @override
  bool get isRedirect => false;
  @override
  bool get persistentConnection => false;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  final HttpHeaders headers = _FakeHttpHeaders();

  // Typed getters that callers cast — must not fall through to noSuchMethod.
  @override
  List<RedirectInfo> get redirects => const <RedirectInfo>[];

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.fromIterable([_bytes]).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeHttpHeaders implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  void forEach(void Function(String name, List<String> values) action) {}
  @override
  ContentType? contentType;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
