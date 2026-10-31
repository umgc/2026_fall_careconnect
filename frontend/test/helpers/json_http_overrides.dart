// Test-only HTTP interception for code that builds its own HTTP client
// internally (a `Dio()` created inside a widget, `http.get(...)` top-level
// calls, etc.). Unlike `fake_http_overrides.dart`, responses here carry a
// `content-type: application/json` header so Dio's transformer decodes the
// body into a Map/List exactly as it would against the real backend.
//
// Usage:
//   final http = JsonHttpOverrides((method, uri, body) {
//     if (uri.path.endsWith('/status')) return JsonReply(200, {'ok': true});
//     return JsonReply(404, {'error': 'missing'});
//   });
//   HttpOverrides.global = http;
//   addTearDown(() => HttpOverrides.global = null);

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// What the fake should return for a request. [body] is JSON-encoded unless
/// it is already a String.
class JsonReply {
  JsonReply(this.statusCode, [this.body]);
  final int statusCode;
  final Object? body;

  String get encoded {
    final b = body;
    if (b == null) return '';
    if (b is String) return b;
    return jsonEncode(b);
  }
}

/// Recorded request (method, uri, body text sent by the client).
class RecordedRequest {
  RecordedRequest(this.method, this.uri, this.body);
  final String method;
  final Uri uri;
  final String body;
}

typedef JsonResponder = JsonReply Function(String method, Uri uri, String body);

class JsonHttpOverrides extends HttpOverrides {
  JsonHttpOverrides(this.responder);
  final JsonResponder responder;
  final List<RecordedRequest> requests = <RecordedRequest>[];

  @override
  HttpClient createHttpClient(SecurityContext? context) => _Client(this);
}

class _Client implements HttpClient {
  _Client(this.owner);
  final JsonHttpOverrides owner;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _Request(owner, method, url);

  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _Request(owner, 'GET', url);

  @override
  Future<HttpClientRequest> postUrl(Uri url) async =>
      _Request(owner, 'POST', url);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Request implements HttpClientRequest {
  _Request(this.owner, this.method, this.uri);
  final JsonHttpOverrides owner;
  @override
  final String method;
  @override
  final Uri uri;
  final List<int> _sent = <int>[];

  @override
  final HttpHeaders headers = _Headers();

  @override
  void add(List<int> data) => _sent.addAll(data);

  @override
  void write(Object? object) => _sent.addAll(utf8.encode('$object'));

  @override
  Future<dynamic> addStream(Stream<List<int>> stream) =>
      stream.forEach(_sent.addAll);

  @override
  Future<HttpClientResponse> close() async {
    final body = utf8.decode(_sent, allowMalformed: true);
    owner.requests.add(RecordedRequest(method, uri, body));
    final r = owner.responder(method, uri, body);
    return _Response(r.statusCode, r.encoded);
  }

  @override
  Future<HttpClientResponse> get done => close();

  @override
  void abort([Object? exception, StackTrace? stackTrace]) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(this.statusCode, String body) : _bytes = utf8.encode(body);
  @override
  final int statusCode;
  final List<int> _bytes;

  @override
  int get contentLength => _bytes.length;
  @override
  String get reasonPhrase => statusCode < 400 ? 'OK' : 'Error';
  @override
  bool get isRedirect => false;
  @override
  bool get persistentConnection => false;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  final HttpHeaders headers = _Headers(json: true);
  @override
  List<RedirectInfo> get redirects => const <RedirectInfo>[];
  @override
  X509Certificate? get certificate => null;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.fromIterable(
      _bytes.isEmpty ? const <List<int>>[] : [_bytes],
    ).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Headers implements HttpHeaders {
  _Headers({this.json = false});
  final bool json;

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  void forEach(void Function(String name, List<String> values) action) {
    if (json) action('content-type', ['application/json; charset=utf-8']);
  }

  @override
  String? value(String name) =>
      json && name.toLowerCase() == 'content-type'
          ? 'application/json; charset=utf-8'
          : null;

  @override
  ContentType? contentType;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
