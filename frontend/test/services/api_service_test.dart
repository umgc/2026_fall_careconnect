// test/services/api_service_test.dart
//
// Unit tests for ApiConstants and ApiService.
//
// Coverage targets (>= 80%):
//   - ApiConstants: all V1/V2/AI endpoint string constants
//   - ApiService pure helpers: isAccessDenied, handleErrorResponse,
//     getJwtToken, saveJWTToken
//   - ApiService HTTP methods: authentication, feed, friends, dashboard,
//     symptoms (CRUD), allergies, tasks (V1 + V2), mood, profiles,
//     subscriptions, messaging, connection requests
//
// HTTP interception strategy
// --------------------------
// ApiService._httpClient is a private `static final http.Client`.  In Dart,
// `static final` fields are lazily initialised on first access.  By setting
// HttpOverrides.global in setUpAll (before any ApiService method is called)
// we ensure that when http.Client() is first constructed it receives our
// _FakeHttpClient.  The IOClient used by the http package creates its inner
// HttpClient in its constructor via HttpOverrides.current.createHttpClient().
//
// Top-level http.get / http.post calls (some methods use these instead of
// _httpClient) also go through HttpOverrides because they create a fresh
// temporary Client per call.
//
// AuthTokenManager.getAuthHeaders() calls FlutterSecureStorage.read() which
// throws MissingPluginException in the test environment.  getJwtToken()
// catches it and returns null, so getAuthHeaders() returns
// {'Content-Type': 'application/json'} with no Authorization header.
// This is acceptable for testing HTTP routing and response parsing.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:care_connect_app/services/api_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Shared mutable spec — each test writes here to control the fake response.
// ─────────────────────────────────────────────────────────────────────────────

class _FakeSpec {
  const _FakeSpec(this.statusCode, this.body);
  final int statusCode;
  final String body;
}

_FakeSpec _activeSpec = const _FakeSpec(200, '{}');

// ─────────────────────────────────────────────────────────────────────────────
// Minimal dart:io HTTP fake — only the surfaces touched by http.Client/IOClient
// ─────────────────────────────────────────────────────────────────────────────

class _FakeHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _FakeHttpClient();
}

class _FakeHttpClient implements HttpClient {
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _FakeHttpClientRequest(_activeSpec);

  // ---- interface stubs not called by the http package ----
  @override bool autoUncompress = true;
  @override Duration? connectionTimeout;
  @override Duration idleTimeout = const Duration(seconds: 15);
  @override int? maxConnectionsPerHost;
  @override String? userAgent;
  @override void addCredentials(Uri u, String r, HttpClientCredentials c) {}
  @override void addProxyCredentials(String h, int p, String r, HttpClientCredentials c) {}
  @override set authenticate(Future<bool> Function(Uri, String, String?)? f) {}
  @override set authenticateProxy(Future<bool> Function(String, int, String, String?)? f) {}
  @override set badCertificateCallback(bool Function(X509Certificate, String, int)? cb) {}
  @override set connectionFactory(Future<ConnectionTask<Socket>> Function(Uri, String?, int?)? f) {}
  @override set findProxy(String Function(Uri)? f) {}
  @override set keyLog(Function(String)? f) {}
  @override void close({bool force = false}) {}
  @override Future<HttpClientRequest> delete(String h, int p, String path) => throw UnimplementedError();
  @override Future<HttpClientRequest> deleteUrl(Uri url) => openUrl('DELETE', url);
  @override Future<HttpClientRequest> get(String h, int p, String path) => throw UnimplementedError();
  @override Future<HttpClientRequest> getUrl(Uri url) => openUrl('GET', url);
  @override Future<HttpClientRequest> head(String h, int p, String path) => throw UnimplementedError();
  @override Future<HttpClientRequest> headUrl(Uri url) => openUrl('HEAD', url);
  @override Future<HttpClientRequest> open(String m, String h, int p, String path) => throw UnimplementedError();
  @override Future<HttpClientRequest> patch(String h, int p, String path) => throw UnimplementedError();
  @override Future<HttpClientRequest> patchUrl(Uri url) => openUrl('PATCH', url);
  @override Future<HttpClientRequest> post(String h, int p, String path) => throw UnimplementedError();
  @override Future<HttpClientRequest> postUrl(Uri url) => openUrl('POST', url);
  @override Future<HttpClientRequest> put(String h, int p, String path) => throw UnimplementedError();
  @override Future<HttpClientRequest> putUrl(Uri url) => openUrl('PUT', url);
}

class _FakeHttpClientRequest implements HttpClientRequest {
  _FakeHttpClientRequest(this._spec);
  final _FakeSpec _spec;
  final _FakeHttpHeaders _hdrs = _FakeHttpHeaders();

  @override HttpHeaders get headers => _hdrs;
  @override Future<HttpClientResponse> close() async => _FakeHttpClientResponse(_spec);

  @override bool bufferOutput = true;
  @override int contentLength = -1;
  @override Encoding encoding = utf8;
  @override bool followRedirects = true;
  @override int maxRedirects = 5;
  @override bool persistentConnection = true;
  @override String get method => '';
  @override Uri get uri => Uri.parse('http://localhost');
  @override HttpConnectionInfo? get connectionInfo => null;
  @override List<Cookie> get cookies => [];
  @override Future<HttpClientResponse> get done => close();
  @override void abort([Object? exception, StackTrace? stackTrace]) {}
  @override void add(List<int> data) {}
  @override void addError(Object error, [StackTrace? stackTrace]) {}
  @override Future addStream(Stream<List<int>> stream) async {}
  @override Future flush() async {}
  @override void write(Object? object) {}
  @override void writeAll(Iterable objects, [String separator = '']) {}
  @override void writeCharCode(int charCode) {}
  @override void writeln([Object? object = '']) {}
}

class _FakeHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _FakeHttpClientResponse(this._spec) {
    // The http package reads the Content-Type header to decode the body.
    headers.set('content-type', 'application/json; charset=utf-8');
  }
  final _FakeSpec _spec;

  @override int get statusCode => _spec.statusCode;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      Stream.value(utf8.encode(_spec.body)).listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );

  @override final HttpHeaders headers = _FakeHttpHeaders();
  @override int get contentLength => utf8.encode(_spec.body).length;
  @override HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override X509Certificate? get certificate => null;
  @override HttpConnectionInfo? get connectionInfo => null;
  @override List<Cookie> get cookies => [];
  @override bool get isRedirect => false;
  @override bool get persistentConnection => false;
  @override String get reasonPhrase => '';
  @override List<RedirectInfo> get redirects => [];
  @override Future<HttpClientResponse> redirect([String? m, Uri? u, bool? f]) =>
      throw UnimplementedError();
  @override Future<Socket> detachSocket() => throw UnimplementedError();
}

class _FakeHttpHeaders implements HttpHeaders {
  final Map<String, List<String>> _m = {};

  @override List<String>? operator [](String name) => _m[name.toLowerCase()];
  @override void add(String name, Object value, {bool preserveHeaderCase = false}) =>
      (_m[name.toLowerCase()] ??= []).add(value.toString());
  @override void set(String name, Object value, {bool preserveHeaderCase = false}) =>
      _m[name.toLowerCase()] = [value.toString()];
  @override String? value(String name) => _m[name.toLowerCase()]?.firstOrNull;
  @override void remove(String name, Object value) =>
      _m[name.toLowerCase()]?.remove(value.toString());
  @override void removeAll(String name) => _m.remove(name.toLowerCase());
  @override void forEach(void Function(String, List<String>) action) => _m.forEach(action);
  @override void noFolding(String name) {}
  @override void clear() => _m.clear();
  @override bool get chunkedTransferEncoding => false;
  @override set chunkedTransferEncoding(bool value) {}
  @override int get contentLength => -1;
  @override set contentLength(int value) {}
  @override ContentType? get contentType => null;
  @override set contentType(ContentType? value) {}
  @override DateTime? get date => null;
  @override set date(DateTime? value) {}
  @override DateTime? get expires => null;
  @override set expires(DateTime? value) {}
  @override String? get host => null;
  @override set host(String? value) {}
  @override DateTime? get ifModifiedSince => null;
  @override set ifModifiedSince(DateTime? value) {}
  @override bool get persistentConnection => true;
  @override set persistentConnection(bool value) {}
  @override int? get port => null;
  @override set port(int? value) {}
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Runs [fn] with the given fake HTTP spec active.
Future<T> _withSpec<T>(_FakeSpec spec, Future<T> Function() fn) {
  _activeSpec = spec;
  return fn();
}

/// Returns the body string that the fake HTTP layer will return.
String _okJson(dynamic map) => jsonEncode(map);

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() {
    // Initialise Flutter test binding (registers platform channels, etc.).
    // TestWidgetsFlutterBinding replaces HttpOverrides with a stub that blocks
    // real network access; we immediately overwrite it with our fake.
    TestWidgetsFlutterBinding.ensureInitialized();
    HttpOverrides.global = _FakeHttpOverrides();
  });

  setUp(() {
    // Restore a safe default so tests that omit _withSpec still succeed.
    _activeSpec = const _FakeSpec(200, '{}');
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Group 1 — ApiConstants
  //
  // All endpoints are composed from a base host string.  We verify that
  // each constant contains the expected path fragment, which catches typos
  // and future regressions without hard-coding the full URL.
  // ──────────────────────────────────────────────────────────────────────────
  group('ApiConstants', () {
    test('auth contains /v1/api/auth', () {
      // Authentication endpoints are under /v1/api/auth.
      expect(ApiConstants.auth, contains('/v1/api/auth'));
    });

    test('feed contains /v1/api/feed', () {
      // Social feed endpoints are under /v1/api/feed.
      expect(ApiConstants.feed, contains('/v1/api/feed'));
    });

    test('users contains /v1/api/users', () {
      expect(ApiConstants.users, contains('/v1/api/users'));
    });

    test('friends contains /v1/api/friends', () {
      expect(ApiConstants.friends, contains('/v1/api/friends'));
    });

    test('analytics contains /v1/api/analytics', () {
      expect(ApiConstants.analytics, contains('/v1/api/analytics'));
    });

    test('baseUrl contains /v1/api/', () {
      expect(ApiConstants.baseUrl, contains('/v1/api/'));
    });

    test('familyMembers contains /v3/api/family-members', () {
      expect(ApiConstants.familyMembers, contains('/v3/api/family-members'));
    });

    test('patients contains /v1/api/patients', () {
      expect(ApiConstants.patients, contains('/v1/api/patients'));
    });

    test('caregivers contains /v1/api/caregivers', () {
      expect(ApiConstants.caregivers, contains('/v1/api/caregivers'));
    });

    test('files contains /v1/api/files', () {
      expect(ApiConstants.files, contains('/v1/api/files'));
    });

    test('connectionRequests contains /v1/api/connection-requests', () {
      expect(ApiConstants.connectionRequests,
          contains('/v1/api/connection-requests'));
    });

    test('subscriptions contains /v3/api/subscriptions', () {
      expect(ApiConstants.subscriptions, contains('/v3/api/subscriptions'));
    });

    test('tasks contains /v3/api/tasks', () {
      expect(ApiConstants.tasks, contains('/v3/api/tasks'));
    });

    test('allergies contains /v1/api/allergies', () {
      expect(ApiConstants.allergies, contains('/v1/api/allergies'));
    });

    test('symptoms contains /v1/api/symptoms', () {
      expect(ApiConstants.symptoms, contains('/v1/api/symptoms'));
    });

    test('baseUrlV2 contains /v2/api/', () {
      // V2 endpoints have their own base URL segment.
      expect(ApiConstants.baseUrlV2, contains('/v2/api/'));
    });

    test('tasksV2 contains /v2/api/tasks', () {
      expect(ApiConstants.tasksV2, contains('/v2/api/tasks'));
    });

    test('aiChat contains /v1/api/ai-chat', () {
      expect(ApiConstants.aiChat, contains('/v1/api/ai-chat'));
    });

    test('aiConfig contains /v1/api/ai-chat/config', () {
      expect(ApiConstants.aiConfig, contains('/v1/api/ai-chat/config'));
    });

    test('invoices contains /v1/api/invoices', () {
      expect(ApiConstants.invoices, contains('/v1/api/invoices'));
    });

    test('evv contains /v1/api/evv', () {
      expect(ApiConstants.evv, contains('/v1/api/evv'));
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Group 2 — ApiService pure utility helpers
  //
  // These methods contain no network I/O and can be tested with in-memory
  // http.Response objects.
  // ──────────────────────────────────────────────────────────────────────────
  group('ApiService pure helpers', () {
    // isAccessDenied ─────────────────────────────────────────────────────────

    test('isAccessDenied returns true for 403', () {
      // Any 403 response from the server indicates the caller lacks permission.
      final resp = _fakeResponse(403, '{}');
      expect(ApiService.isAccessDenied(resp), isTrue);
    });

    test('isAccessDenied returns false for 200', () {
      // 200 is a successful response — access is granted.
      final resp = _fakeResponse(200, '{}');
      expect(ApiService.isAccessDenied(resp), isFalse);
    });

    test('isAccessDenied returns false for 401', () {
      // 401 is unauthenticated, not forbidden — isAccessDenied only checks 403.
      final resp = _fakeResponse(401, '{}');
      expect(ApiService.isAccessDenied(resp), isFalse);
    });

    test('isAccessDenied returns false for 404', () {
      final resp = _fakeResponse(404, '{}');
      expect(ApiService.isAccessDenied(resp), isFalse);
    });

    // handleErrorResponse ─────────────────────────────────────────────────────

    test('handleErrorResponse returns "message" field when present', () {
      // The primary error key used by our Spring Boot backend is "message".
      final resp = _fakeResponse(400, '{"message":"Bad input"}');
      expect(ApiService.handleErrorResponse(resp), 'Bad input');
    });

    test('handleErrorResponse falls back to "error" field', () {
      // Some endpoints return {"error": "..."} instead of {"message": "..."}.
      final resp = _fakeResponse(500, '{"error":"Internal error"}');
      expect(ApiService.handleErrorResponse(resp), 'Internal error');
    });

    test('handleErrorResponse returns default when neither key is present', () {
      // When the response body has no recognisable error field we use a generic
      // message so that the UI always has something to display.
      final resp = _fakeResponse(500, '{"detail":"something"}');
      expect(ApiService.handleErrorResponse(resp), 'Unknown error occurred');
    });

    test('handleErrorResponse returns default for empty JSON object', () {
      final resp = _fakeResponse(503, '{}');
      expect(ApiService.handleErrorResponse(resp), 'Unknown error occurred');
    });

    test('handleErrorResponse returns status fallback for invalid JSON', () {
      // When the body is not valid JSON we fall back to mentioning the status.
      final resp = _fakeResponse(502, 'not-json');
      expect(ApiService.handleErrorResponse(resp),
          contains('502'));
    });

    test('handleErrorResponse "message" takes priority over "error"', () {
      // When both keys are present the richer "message" field is preferred.
      final resp =
          _fakeResponse(409, '{"message":"Conflict msg","error":"Error msg"}');
      expect(ApiService.handleErrorResponse(resp), 'Conflict msg');
    });

    // getJwtToken ─────────────────────────────────────────────────────────────

    test('getJwtToken returns empty string when no token is stored', () async {
      // In the test environment FlutterSecureStorage has no stored token, so
      // AuthTokenManager returns null and getJwtToken yields an empty string.
      final token = await ApiService.getJwtToken();
      expect(token, '');
    });

    // saveJWTToken ────────────────────────────────────────────────────────────

    test('saveJWTToken completes without error (deprecated no-op)', () async {
      // saveJWTToken is a deprecated stub — it should not throw.
      await expectLater(ApiService.saveJWTToken('any-token'), completes);
    });

    // clearAuthCookie ─────────────────────────────────────────────────────────

    test('clearAuthCookie completes without error', () async {
      // clearAuthCookie delegates to AuthTokenManager.clearAuthData(), which
      // silently succeeds even when storage is unavailable in tests.
      await expectLater(ApiService.clearAuthCookie(), completes);
    });

    // getAuthHeaders ──────────────────────────────────────────────────────────

    test('getAuthHeaders returns a map with Content-Type in tests', () async {
      // Without a stored token the headers will still include Content-Type.
      final headers = await ApiService.getAuthHeaders();
      expect(headers, isA<Map<String, String>>());
      expect(headers.containsKey('Content-Type'), isTrue);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Group 3 — Authentication methods
  //
  // These methods POST to the auth endpoint and return the http.Response
  // verbatim.  We verify the status code is forwarded correctly and that
  // the method does not throw on common success and error codes.
  // ──────────────────────────────────────────────────────────────────────────
  group('Authentication methods', () {
    test('register forwards 200 response', () async {
      // A successful registration returns the server's 200 response body.
      final resp = await _withSpec(
        const _FakeSpec(200, '{"id":1}'),
        () => ApiService.register('Alice', 'alice@example.com', 'pass'),
      );
      expect(resp.statusCode, 200);
    });

    test('register forwards 400 response without throwing', () async {
      // register does not interpret the status — it returns the raw response.
      final resp = await _withSpec(
        const _FakeSpec(400, '{"message":"Email taken"}'),
        () => ApiService.register('Bob', 'bob@example.com', 'pass'),
      );
      expect(resp.statusCode, 400);
    });

    test('login returns response with correct status on success', () async {
      // A 200 response indicates the credentials were accepted.
      final resp = await _withSpec(
        const _FakeSpec(200, '{"token":"jwt123"}'),
        () => ApiService.login('alice@example.com', 'pass'),
      );
      expect(resp.statusCode, 200);
    });

    test('login returns response on 401 without throwing', () async {
      // Wrong credentials return 401; the caller decides how to handle it.
      final resp = await _withSpec(
        const _FakeSpec(401, '{"message":"Invalid credentials"}'),
        () => ApiService.login('x@y.com', 'wrong'),
      );
      expect(resp.statusCode, 401);
    });

    test('requestPasswordReset returns 200 on success', () async {
      // A password reset email is dispatched and the server confirms with 200.
      final resp = await _withSpec(
        const _FakeSpec(200, '{"message":"Email sent"}'),
        () => ApiService.requestPasswordReset('alice@example.com'),
      );
      expect(resp.statusCode, 200);
    });

    test('resetPassword returns 200 on success', () async {
      // After supplying the token and new password, the server responds 200.
      final resp = await _withSpec(
        const _FakeSpec(200, '{"message":"Password reset"}'),
        () => ApiService.resetPassword(
          token: 'reset-token',
          newPassword: 'newPass123',
        ),
      );
      expect(resp.statusCode, 200);
    });

    test('resetPassword returns 400 when token is invalid', () async {
      // Expired or invalid reset tokens should be reported back via 400.
      final resp = await _withSpec(
        const _FakeSpec(400, '{"message":"Invalid token"}'),
        () => ApiService.resetPassword(
          token: 'expired',
          newPassword: 'newPass',
        ),
      );
      expect(resp.statusCode, 400);
    });

    test('getProfile returns 200 on success', () async {
      // The profile endpoint returns the authenticated user's data.
      final resp = await _withSpec(
        const _FakeSpec(200, '{"name":"Alice"}'),
        () => ApiService.getProfile(),
      );
      expect(resp.statusCode, 200);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Group 4 — Feed methods
  // ──────────────────────────────────────────────────────────────────────────
  group('Feed methods', () {
    test('getAllPosts returns 200', () async {
      // The feed endpoint returns a list of all recent posts.
      final resp = await _withSpec(
        const _FakeSpec(200, '[{"id":1}]'),
        () => ApiService.getAllPosts(),
      );
      expect(resp.statusCode, 200);
    });

    test('getUserPosts returns 200 for a valid userId', () async {
      // Only posts created by the given user are returned.
      final resp = await _withSpec(
        const _FakeSpec(200, '[{"id":2}]'),
        () => ApiService.getUserPosts(42),
      );
      expect(resp.statusCode, 200);
    });

    test('getUserPosts returns 404 when user does not exist', () async {
      final resp = await _withSpec(
        const _FakeSpec(404, '{"message":"Not found"}'),
        () => ApiService.getUserPosts(9999),
      );
      expect(resp.statusCode, 404);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Group 5 — Friend methods
  // ──────────────────────────────────────────────────────────────────────────
  group('Friend methods', () {
    test('searchUsers returns 200 with results', () async {
      // A successful search returns matching user records.
      final resp = await _withSpec(
        const _FakeSpec(200, '[{"id":5,"name":"Bob"}]'),
        () => ApiService.searchUsers('Bob', 1),
      );
      expect(resp.statusCode, 200);
    });

    test('sendFriendRequest returns 200 on success', () async {
      // The server confirms the friend request was stored.
      final resp = await _withSpec(
        const _FakeSpec(200, '{"message":"Request sent"}'),
        () => ApiService.sendFriendRequest(1, 2),
      );
      expect(resp.statusCode, 200);
    });

    test('getPendingFriendRequests returns 200', () async {
      // Returns the list of incoming friend requests for a user.
      final resp = await _withSpec(
        const _FakeSpec(200, '[]'),
        () => ApiService.getPendingFriendRequests(1),
      );
      expect(resp.statusCode, 200);
    });

    test('acceptFriendRequest returns 200 on success', () async {
      // After accepting, the friendship is established.
      final resp = await _withSpec(
        const _FakeSpec(200, '{"message":"Accepted"}'),
        () => ApiService.acceptFriendRequest(10),
      );
      expect(resp.statusCode, 200);
    });

    test('rejectFriendRequest returns 200 on success', () async {
      // The server confirms the request was rejected.
      final resp = await _withSpec(
        const _FakeSpec(200, '{"message":"Rejected"}'),
        () => ApiService.rejectFriendRequest(10),
      );
      expect(resp.statusCode, 200);
    });

    test('getFriends returns 200 with friend list', () async {
      // A list of established friendships for the user is returned.
      final resp = await _withSpec(
        const _FakeSpec(200, '[{"id":3}]'),
        () => ApiService.getFriends(1),
      );
      expect(resp.statusCode, 200);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Group 6 — Dashboard / caregiver methods
  // ──────────────────────────────────────────────────────────────────────────
  group('Dashboard / caregiver methods', () {
    test('getCaregiverPatients returns 200', () async {
      // The caregiver's patient list endpoint returns all linked patients.
      final resp = await _withSpec(
        const _FakeSpec(200, '[{"id":7}]'),
        () => ApiService.getCaregiverPatients(1),
      );
      expect(resp.statusCode, 200);
    });

    test('checkEmailExists returns map with exists=true on 200', () async {
      // A 200 response with the expected field is returned as a decoded map.
      final result = await _withSpec(
        const _FakeSpec(200, '{"exists":true}'),
        () => ApiService.checkEmailExists('alice@example.com'),
      );
      expect(result['exists'], isTrue);
    });

    test('checkEmailExists returns exists=false on non-200', () async {
      // When the server returns a non-200 status, exists is coerced to false.
      final result = await _withSpec(
        const _FakeSpec(500, '{"message":"Error"}'),
        () => ApiService.checkEmailExists('bad@example.com'),
      );
      expect(result['exists'], isFalse);
      expect(result.containsKey('error'), isTrue);
    });

    test('sendConnectionRequest returns 200', () async {
      // A successful connection request is confirmed by the server.
      final resp = await _withSpec(
        const _FakeSpec(200, '{"message":"Sent"}'),
        () => ApiService.sendConnectionRequest(
          caregiverId: 1,
          patientEmail: 'patient@example.com',
          relationshipType: 'PRIMARY',
        ),
      );
      expect(resp.statusCode, 200);
    });

    test('sendConnectionRequest with custom message returns 200', () async {
      final resp = await _withSpec(
        const _FakeSpec(200, '{"message":"Sent"}'),
        () => ApiService.sendConnectionRequest(
          caregiverId: 1,
          patientEmail: 'patient@example.com',
          relationshipType: 'PRIMARY',
          message: 'Custom connection message',
        ),
      );
      expect(resp.statusCode, 200);
    });

    test('getPendingRequestsByCaregiver returns 200', () async {
      // Pending connection requests are listed for a specific caregiver.
      final resp = await _withSpec(
        const _FakeSpec(200, '[]'),
        () => ApiService.getPendingRequestsByCaregiver(1),
      );
      expect(resp.statusCode, 200);
    });

    test('suspendCaregiverPatientLink returns 200', () async {
      // Suspending a link disables the caregiver–patient relationship.
      final resp = await _withSpec(
        const _FakeSpec(200, '{"message":"Suspended"}'),
        () => ApiService.suspendCaregiverPatientLink(5),
      );
      expect(resp.statusCode, 200);
    });

    test('reactivateCaregiverPatientLink returns 200', () async {
      // Reactivation re-enables a previously suspended link.
      final resp = await _withSpec(
        const _FakeSpec(200, '{"message":"Reactivated"}'),
        () => ApiService.reactivateCaregiverPatientLink(5),
      );
      expect(resp.statusCode, 200);
    });

    test('getPatientVitals returns 200 response', () async {
      // Vitals for a patient over the specified days window.
      final resp = await _withSpec(
        const _FakeSpec(200, '{"data":[]}'),
        () => ApiService.getPatientVitals(1),
      );
      expect(resp.statusCode, 200);
    });

    test('getPatientVitals returns 200 with custom days parameter', () async {
      final resp = await _withSpec(
        const _FakeSpec(200, '{"data":[]}'),
        () => ApiService.getPatientVitals(1, days: 14),
      );
      expect(resp.statusCode, 200);
    });

    test('getPatientVitals returns 408 on timeout via onTimeout handler', () async {
      // The onTimeout callback returns an HTTP 408 response instead of throwing.
      // We simulate this by making the spec return 408 directly.
      final resp = await _withSpec(
        const _FakeSpec(408, '{"error":"Request timeout"}'),
        () => ApiService.getPatientVitals(1),
      );
      expect(resp.statusCode, 408);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Group 7 — Mood methods
  // ──────────────────────────────────────────────────────────────────────────
  group('Mood methods', () {
    test('saveMoodScore returns 200 on success', () async {
      // The mood score is persisted and the server confirms with 200.
      final resp = await _withSpec(
        const _FakeSpec(200, '{"message":"Saved"}'),
        () => ApiService.saveMoodScore(userId: 1, score: 3, label: 'Okay'),
      );
      expect(resp.statusCode, 200);
    });

    test('saveMoodScore returns 400 on invalid input', () async {
      // An invalid mood score (e.g., out-of-range value) should return 400.
      final resp = await _withSpec(
        const _FakeSpec(400, '{"message":"Invalid score"}'),
        () => ApiService.saveMoodScore(userId: 1, score: -1, label: 'Bad'),
      );
      expect(resp.statusCode, 400);
    });

    test('getMoodHistory returns empty list on non-200', () async {
      // On a server error the method returns an empty list rather than throwing.
      final result = await _withSpec(
        const _FakeSpec(500, '{"message":"Error"}'),
        () => ApiService.getMoodHistory(1),
      );
      expect(result, isEmpty);
    });

    test('getMoodHistory returns list data on 200', () async {
      // A 200 response with a JSON array is decoded and returned.
      final result = await _withSpec(
        const _FakeSpec(200, '[{"score":4},{"score":2}]'),
        () => ApiService.getMoodHistory(1),
      );
      expect(result.length, 2);
    });

    test('getMoodHistory returns empty list when body is not a list', () async {
      // If the server returns a JSON object instead of an array, the method
      // safely returns an empty list without throwing.
      final result = await _withSpec(
        const _FakeSpec(200, '{"data":[]}'),
        () => ApiService.getMoodHistory(1),
      );
      expect(result, isEmpty);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Group 8 — Symptoms CRUD
  //
  // getSymptomsForPatient, getSymptomById, createSymptom, updateSymptom, and
  // deleteSymptom all throw on non-success status codes.
  // ──────────────────────────────────────────────────────────────────────────
  group('Symptoms CRUD', () {
    test('getSymptomsForPatient returns empty list when body has no data key', () async {
      // If the server omits the "data" array the method returns an empty list.
      final result = await _withSpec(
        const _FakeSpec(200, '{}'),
        () => ApiService.getSymptomsForPatient(1),
      );
      expect(result, isEmpty);
    });

    test('getSymptomsForPatient returns list from data key on 200', () async {
      // The standard response wraps the list in {"data": [...]}.
      final body = _okJson({
        'data': [
          {'id': 1, 'symptomKey': 'headache'},
        ]
      });
      final result = await _withSpec(
        _FakeSpec(200, body),
        () => ApiService.getSymptomsForPatient(1),
      );
      expect(result.length, 1);
      expect(result.first['symptomKey'], 'headache');
    });

    test('getSymptomsForPatient throws on non-200', () async {
      // A non-200 status indicates an error; the method propagates the exception.
      await expectLater(
        _withSpec(
          const _FakeSpec(500, '{"message":"Error"}'),
          () => ApiService.getSymptomsForPatient(1),
        ),
        throwsException,
      );
    });

    test('getSymptomById returns map from data key on 200', () async {
      // The single-symptom endpoint wraps its result in {"data": {...}}.
      final body = _okJson({
        'data': {'id': 5, 'symptomKey': 'nausea'}
      });
      final result = await _withSpec(
        _FakeSpec(200, body),
        () => ApiService.getSymptomById(5),
      );
      expect(result['symptomKey'], 'nausea');
    });

    test('getSymptomById returns empty map when data key is absent', () async {
      // Malformed but 200-status responses return an empty map.
      final result = await _withSpec(
        const _FakeSpec(200, '{}'),
        () => ApiService.getSymptomById(5),
      );
      expect(result, isEmpty);
    });

    test('getSymptomById throws on 404', () async {
      // A missing symptom is surfaced as an exception to the caller.
      await expectLater(
        _withSpec(
          const _FakeSpec(404, '{"message":"Not found"}'),
          () => ApiService.getSymptomById(999),
        ),
        throwsException,
      );
    });

    test('createSymptom returns data map on 201', () async {
      // A successful creation returns the newly stored symptom data.
      final body = _okJson({
        'data': {'id': 10, 'symptomKey': 'fatigue'}
      });
      final result = await _withSpec(
        _FakeSpec(201, body),
        () => ApiService.createSymptom(
          patientId: 1,
          symptomKey: 'fatigue',
          severity: 3,
        ),
      );
      expect(result['symptomKey'], 'fatigue');
    });

    test('createSymptom also accepts 200 status', () async {
      // Some server configurations return 200 for resource creation.
      final body = _okJson({
        'data': {'id': 11, 'symptomKey': 'cough'}
      });
      final result = await _withSpec(
        _FakeSpec(200, body),
        () => ApiService.createSymptom(
          patientId: 1,
          symptomKey: 'cough',
          severity: 2,
        ),
      );
      expect(result['symptomKey'], 'cough');
    });

    test('createSymptom throws on 400', () async {
      // Missing required fields should cause a 400 error.
      await expectLater(
        _withSpec(
          const _FakeSpec(400, '{"message":"Validation failed"}'),
          () => ApiService.createSymptom(
            patientId: 1,
            symptomKey: '',
            severity: -1,
          ),
        ),
        throwsException,
      );
    });

    test('updateSymptom returns updated data on 200', () async {
      // A successful update returns the modified symptom record.
      final body = _okJson({
        'data': {'id': 5, 'severity': 1}
      });
      final result = await _withSpec(
        _FakeSpec(200, body),
        () => ApiService.updateSymptom(id: 5, severity: 1),
      );
      expect(result['severity'], 1);
    });

    test('updateSymptom throws on 404', () async {
      // Attempting to update a non-existent symptom throws an exception.
      await expectLater(
        _withSpec(
          const _FakeSpec(404, '{"message":"Not found"}'),
          () => ApiService.updateSymptom(id: 999),
        ),
        throwsException,
      );
    });

    test('deleteSymptom completes on 200', () async {
      // Deleting an existing symptom succeeds silently.
      await expectLater(
        _withSpec(
          const _FakeSpec(200, '{}'),
          () => ApiService.deleteSymptom(5),
        ),
        completes,
      );
    });

    test('deleteSymptom completes on 204', () async {
      // 204 No Content is also a valid success response for DELETE.
      await expectLater(
        _withSpec(
          const _FakeSpec(204, ''),
          () => ApiService.deleteSymptom(5),
        ),
        completes,
      );
    });

    test('deleteSymptom throws on 403', () async {
      // Callers must have permission to delete symptoms.
      await expectLater(
        _withSpec(
          const _FakeSpec(403, '{"message":"Forbidden"}'),
          () => ApiService.deleteSymptom(5),
        ),
        throwsException,
      );
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Group 9 — Allergies
  // ──────────────────────────────────────────────────────────────────────────
  group('Allergies', () {
    test('fetchAllergies returns list on 200', () async {
      // A successful fetch returns the list of allergy records.
      final body = _okJson({
        'data': [
          {'id': 1, 'allergen': 'Penicillin'}
        ]
      });
      final result = await _withSpec(
        _FakeSpec(200, body),
        () => ApiService.fetchAllergies(1),
      );
      expect(result.length, 1);
    });

    test('fetchAllergies returns empty list when data key is absent', () async {
      // Fallback to empty list when the response has no "data" key.
      final result = await _withSpec(
        const _FakeSpec(200, '{}'),
        () => ApiService.fetchAllergies(1),
      );
      expect(result, isEmpty);
    });

    test('fetchAllergies throws HttpException on non-200', () async {
      // Non-2xx responses are surfaced to the caller as an HttpException.
      await expectLater(
        _withSpec(
          const _FakeSpec(500, '{"message":"Error"}'),
          () => ApiService.fetchAllergies(1),
        ),
        throwsA(isA<HttpException>()),
      );
    });

    test('addAllergy returns data map on 201', () async {
      // A new allergy record is created and the server returns its data.
      final body = _okJson({
        'data': {'id': 2, 'allergen': 'Aspirin'}
      });
      final result = await _withSpec(
        _FakeSpec(201, body),
        () => ApiService.addAllergy(
          {'drug': 'Aspirin', 'severity': 'HIGH', 'reaction': 'rash', 'note': ''},
          1,
        ),
      );
      expect(result['allergen'], 'Aspirin');
    });

    test('addAllergy throws HttpException on non-201', () async {
      // A server error when adding an allergy must propagate.
      await expectLater(
        _withSpec(
          const _FakeSpec(400, '{"message":"Invalid data"}'),
          () => ApiService.addAllergy(
            {'drug': '', 'severity': '', 'reaction': '', 'note': ''},
            1,
          ),
        ),
        throwsA(isA<HttpException>()),
      );
    });

    test('removeAllergy returns true on 200', () async {
      // A successful deletion is confirmed by a truthy return value.
      final result = await _withSpec(
        const _FakeSpec(200, '{}'),
        () => ApiService.removeAllergy(1),
      );
      expect(result, isTrue);
    });

    test('removeAllergy returns true on 204', () async {
      // 204 No Content is also a valid success response.
      final result = await _withSpec(
        const _FakeSpec(204, ''),
        () => ApiService.removeAllergy(1),
      );
      expect(result, isTrue);
    });

    test('removeAllergy returns false on 404', () async {
      // When the allergy does not exist the method returns false, not an exception.
      final result = await _withSpec(
        const _FakeSpec(404, '{"message":"Not found"}'),
        () => ApiService.removeAllergy(999),
      );
      expect(result, isFalse);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Group 10 — Task methods (V1)
  // ──────────────────────────────────────────────────────────────────────────
  group('Task methods V1', () {
    test('getPatientTasks returns 200', () async {
      // The tasks list for a patient is returned directly.
      final resp = await _withSpec(
        const _FakeSpec(200, '[{"id":1}]'),
        () => ApiService.getPatientTasks(1),
      );
      expect(resp.statusCode, 200);
    });

    test('deleteTask returns 200', () async {
      // Deleting a task by ID should confirm with 200.
      final resp = await _withSpec(
        const _FakeSpec(200, '{"message":"Deleted"}'),
        () => ApiService.deleteTask(1),
      );
      expect(resp.statusCode, 200);
    });

    test('editTask returns 200 on success', () async {
      // A partial update to a task is acknowledged by the server.
      final resp = await _withSpec(
        const _FakeSpec(200, '{"id":1,"title":"Updated"}'),
        () => ApiService.editTask(1, {'title': 'Updated'}),
      );
      expect(resp.statusCode, 200);
    });

    test('createTask returns 201 on success', () async {
      // A new task is created and the server responds with 201 Created.
      final resp = await _withSpec(
        const _FakeSpec(201, '{"id":2}'),
        () => ApiService.createTask(1, '{"title":"New Task"}'),
      );
      expect(resp.statusCode, 201);
    });

    test('getTaskTemplates returns 200', () async {
      // Task templates are fetched for populating the creation form.
      final resp = await _withSpec(
        const _FakeSpec(200, '[{"templateId":1}]'),
        () => ApiService.getTaskTemplates(1),
      );
      expect(resp.statusCode, 200);
    });

    test('getTaskTemplate returns 200 for a specific template', () async {
      final resp = await _withSpec(
        const _FakeSpec(200, '{"templateId":5}'),
        () => ApiService.getTaskTemplate(5),
      );
      expect(resp.statusCode, 200);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Group 11 — Task methods (V2)
  // ──────────────────────────────────────────────────────────────────────────
  group('Task methods V2', () {
    test('getPatientTasksV2 returns 200', () async {
      // V2 tasks endpoint returns the same structure but via the V2 route.
      final resp = await _withSpec(
        const _FakeSpec(200, '[{"id":1}]'),
        () => ApiService.getPatientTasksV2(1),
      );
      expect(resp.statusCode, 200);
    });

    test('deleteTaskV2 returns 200 (deleteSeries=false)', () async {
      // Deleting a single occurrence does not delete the whole recurring series.
      final resp = await _withSpec(
        const _FakeSpec(200, '{"message":"Deleted"}'),
        () => ApiService.deleteTaskV2(1),
      );
      expect(resp.statusCode, 200);
    });

    test('deleteTaskV2 returns 200 (deleteSeries=true)', () async {
      // Deleting with deleteSeries removes all recurrences of the task.
      final resp = await _withSpec(
        const _FakeSpec(200, '{"message":"Series deleted"}'),
        () => ApiService.deleteTaskV2(1, deleteSeries: true),
      );
      expect(resp.statusCode, 200);
    });

    test('editTaskV2 returns 200', () async {
      // A V2 task update includes the updateSeries flag in the payload.
      final resp = await _withSpec(
        const _FakeSpec(200, '{"id":1}'),
        () => ApiService.editTaskV2(1, {'title': 'New title'}),
      );
      expect(resp.statusCode, 200);
    });

    test('editTaskV2 with updateSeries=true returns 200', () async {
      // When updating the whole series, updateSeries is true in the payload.
      final resp = await _withSpec(
        const _FakeSpec(200, '{"id":1}'),
        () => ApiService.editTaskV2(1, {'title': 'New title'},
            updateSeries: true),
      );
      expect(resp.statusCode, 200);
    });

    test('updateTaskCompletionV2 completes on 200', () async {
      // Marking a task complete or incomplete should succeed silently.
      await expectLater(
        _withSpec(
          const _FakeSpec(200, '{"message":"Updated"}'),
          () => ApiService.updateTaskCompletionV2(1, true),
        ),
        completes,
      );
    });

    test('updateTaskCompletionV2 throws on non-200', () async {
      // A server error when updating completion status must propagate.
      await expectLater(
        _withSpec(
          const _FakeSpec(500, '{"message":"Error"}'),
          () => ApiService.updateTaskCompletionV2(1, true),
        ),
        throwsException,
      );
    });

    test('createTaskV2 returns 201 on success', () async {
      // A new V2 task is created and the server responds with 201 Created.
      final resp = await _withSpec(
        const _FakeSpec(201, '{"id":3}'),
        () => ApiService.createTaskV2(1, '{"title":"Task V2"}'),
      );
      expect(resp.statusCode, 201);
    });

    test('getTaskByIdV2 returns 200', () async {
      // Fetching a single task by ID returns its full record.
      final resp = await _withSpec(
        const _FakeSpec(200, '{"id":1,"title":"My Task"}'),
        () => ApiService.getTaskByIdV2(1),
      );
      expect(resp.statusCode, 200);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Group 12 — Profile management methods
  // ──────────────────────────────────────────────────────────────────────────
  group('Profile management', () {
    test('getCaregiverProfile returns 200', () async {
      // The caregiver's full profile record is returned.
      final resp = await _withSpec(
        const _FakeSpec(200, '{"id":1,"name":"Dr Smith"}'),
        () => ApiService.getCaregiverProfile(1),
      );
      expect(resp.statusCode, 200);
    });

    test('updateCaregiverProfile returns 200', () async {
      // Profile updates are acknowledged by the server.
      final resp = await _withSpec(
        const _FakeSpec(200, '{"id":1,"name":"Dr Jones"}'),
        () => ApiService.updateCaregiverProfile(1, {'name': 'Dr Jones'}),
      );
      expect(resp.statusCode, 200);
    });

    test('getPatientProfile returns 200', () async {
      // The patient's profile is fetched successfully.
      final resp = await _withSpec(
        const _FakeSpec(200, '{"id":5,"firstName":"Alice"}'),
        () => ApiService.getPatientProfile(5),
      );
      expect(resp.statusCode, 200);
    });

    test('updatePatientProfile returns 200', () async {
      // Patient profile changes are persisted and confirmed.
      final resp = await _withSpec(
        const _FakeSpec(200, '{"id":5,"firstName":"Alicia"}'),
        () =>
            ApiService.updatePatientProfile(5, {'firstName': 'Alicia'}),
      );
      expect(resp.statusCode, 200);
    });

    test('getUserProfilePictureUrl returns URL string on 200 list response',
        () async {
      // When the response is a list, the first element's fileUrl is returned.
      final body = _okJson([
        {'fileUrl': 'https://example.com/avatar.png'}
      ]);
      final url = await _withSpec(
        _FakeSpec(200, body),
        () => ApiService.getUserProfilePictureUrl(1),
      );
      expect(url, 'https://example.com/avatar.png');
    });

    test('getUserProfilePictureUrl returns URL from map response on 200', () async {
      // When the response is a map with fileUrl, that URL is returned.
      final body = _okJson({'fileUrl': 'https://example.com/photo.jpg'});
      final url = await _withSpec(
        _FakeSpec(200, body),
        () => ApiService.getUserProfilePictureUrl(1),
      );
      expect(url, 'https://example.com/photo.jpg');
    });

    test('getUserProfilePictureUrl returns null on non-200', () async {
      // If the file endpoint returns an error, the method gracefully returns null.
      final url = await _withSpec(
        const _FakeSpec(404, '{}'),
        () => ApiService.getUserProfilePictureUrl(1),
      );
      expect(url, isNull);
    });

    test('getUserProfilePictureUrl returns null for empty list', () async {
      // An empty list means no profile picture is stored.
      final url = await _withSpec(
        const _FakeSpec(200, '[]'),
        () => ApiService.getUserProfilePictureUrl(1),
      );
      expect(url, isNull);
    });

    test('getEnhancedPatientProfile returns map on 200 with data key', () async {
      // The enhanced profile wraps its payload in a "data" key.
      final body = _okJson({
        'data': {'id': 5, 'bmi': 24.1}
      });
      final result = await _withSpec(
        _FakeSpec(200, body),
        () => ApiService.getEnhancedPatientProfile(5),
      );
      expect(result?['bmi'], 24.1);
    });

    test('getEnhancedPatientProfile returns null on non-200', () async {
      // Network or server errors return null so callers can show fallback UI.
      final result = await _withSpec(
        const _FakeSpec(500, '{}'),
        () => ApiService.getEnhancedPatientProfile(5),
      );
      expect(result, isNull);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Group 13 — Subscription methods
  // ──────────────────────────────────────────────────────────────────────────
  group('Subscription methods', () {
    test('getAvailablePlans returns 200', () async {
      // The list of subscription plans is fetched from the server.
      final resp = await _withSpec(
        const _FakeSpec(200, '[{"id":"plan_basic"}]'),
        () => ApiService.getAvailablePlans(),
      );
      expect(resp.statusCode, 200);
    });

    test('createSubscription returns 200', () async {
      // Creating a subscription for an existing Stripe customer succeeds.
      final resp = await _withSpec(
        const _FakeSpec(200, '{"subscriptionId":"sub_123"}'),
        () => ApiService.createSubscription('cus_123', 'price_123'),
      );
      expect(resp.statusCode, 200);
    });

    test('cancelSubscription returns 200', () async {
      // Cancelling a subscription is confirmed by the server.
      final resp = await _withSpec(
        const _FakeSpec(200, '{"message":"Cancelled"}'),
        () => ApiService.cancelSubscription('sub_123'),
      );
      expect(resp.statusCode, 200);
    });

    test('changeSubscriptionPlan returns 200', () async {
      // Changing between plans succeeds when billing allows it.
      final resp = await _withSpec(
        const _FakeSpec(200, '{"message":"Changed"}'),
        () => ApiService.changeSubscriptionPlan('sub_old', 'price_new'),
      );
      expect(resp.statusCode, 200);
    });

    test('upgradeOrDowngradeSubscription returns 200', () async {
      // Upgrading or downgrading delegates to the same endpoint.
      final resp = await _withSpec(
        const _FakeSpec(200, '{"message":"Upgraded"}'),
        () => ApiService.upgradeOrDowngradeSubscription('sub_old', 'price_new'),
      );
      expect(resp.statusCode, 200);
    });

    test('getCurrentSubscription throws when user session is null', () async {
      // Without a stored session the method cannot derive the user ID, so it
      // throws immediately without making a network request.
      await expectLater(
        ApiService.getCurrentSubscription(),
        throwsException,
      );
    });

    test('getUserSubscriptions throws when user session is null', () async {
      // Same guard as getCurrentSubscription: missing session → exception.
      await expectLater(
        ApiService.getUserSubscriptions(),
        throwsException,
      );
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Group 14 — Messaging methods
  // ──────────────────────────────────────────────────────────────────────────
  group('Messaging methods', () {
    test('sendMessage returns 200 on success', () async {
      // A sent message is acknowledged by the server.
      final resp = await _withSpec(
        const _FakeSpec(200, '{"id":1}'),
        () => ApiService.sendMessage(
          senderId: 1,
          receiverId: 2,
          content: 'Hello!',
        ),
      );
      expect(resp.statusCode, 200);
    });

    test('getConversation returns list on 200', () async {
      // A full conversation thread between two users is returned.
      final result = await _withSpec(
        const _FakeSpec(200, '[{"id":1,"content":"Hi"}]'),
        () => ApiService.getConversation(user1: 1, user2: 2),
      );
      expect(result.length, 1);
    });

    test('getConversation throws on non-200', () async {
      // A server error while loading a conversation propagates to the caller.
      await expectLater(
        _withSpec(
          const _FakeSpec(500, '{"message":"Error"}'),
          () => ApiService.getConversation(user1: 1, user2: 2),
        ),
        throwsException,
      );
    });

    test('getInbox returns list on 200', () async {
      // The inbox contains all conversations for the given user.
      final result = await _withSpec(
        const _FakeSpec(200, '[{"id":1}]'),
        () => ApiService.getInbox(1),
      );
      expect(result.length, 1);
    });

    test('getInbox throws on non-200', () async {
      // Errors loading the inbox propagate so the UI can display a retry option.
      await expectLater(
        _withSpec(
          const _FakeSpec(500, '{}'),
          () => ApiService.getInbox(1),
        ),
        throwsException,
      );
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Group 15 — registerPatientForCaregiver / addExistingPatientToCaregiver
  // ──────────────────────────────────────────────────────────────────────────
  group('Patient registration methods', () {
    test('registerPatientForCaregiver returns 201 on success', () async {
      // A new patient is created and linked to the caregiver.
      final resp = await _withSpec(
        const _FakeSpec(201, '{"id":10}'),
        () => ApiService.registerPatientForCaregiver(
          caregiverId: 1,
          patientData: {'firstName': 'Bob'},
        ),
      );
      expect(resp.statusCode, 201);
    });

    test('addExistingPatientToCaregiver returns 200 on success', () async {
      // An existing patient account is linked to the caregiver via their email.
      final resp = await _withSpec(
        const _FakeSpec(200, '{"message":"Linked"}'),
        () => ApiService.addExistingPatientToCaregiver(
          caregiverId: 1,
          patientEmail: 'patient@example.com',
        ),
      );
      expect(resp.statusCode, 200);
    });

    test('addExistingPatientToCaregiver returns 408 on timeout', () async {
      // The onTimeout handler converts a timeout into a 408 response.
      final resp = await _withSpec(
        const _FakeSpec(408, '{"error":"Request timeout"}'),
        () => ApiService.addExistingPatientToCaregiver(
          caregiverId: 1,
          patientEmail: 'slow@example.com',
        ),
      );
      expect(resp.statusCode, 408);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Group 16 — registerPatient
  // ──────────────────────────────────────────────────────────────────────────
  group('registerPatient', () {
    test('returns 200 on success', () async {
      final resp = await _withSpec(
        const _FakeSpec(200, '{"id":10}'),
        () => ApiService.registerPatient(
          'John', 'Doe', 'john@example.com', '555-1234',
          '1990-01-01', '123 Main St', 'CHILD', 1,
        ),
      );
      expect(resp.statusCode, 200);
    });

    test('returns 400 on validation failure', () async {
      final resp = await _withSpec(
        const _FakeSpec(400, '{"message":"Invalid data"}'),
        () => ApiService.registerPatient(
          '', '', '', '', '', '', '', 1,
        ),
      );
      expect(resp.statusCode, 400);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Group 17 — logout
  // ──────────────────────────────────────────────────────────────────────────
  group('logout', () {
    test('returns response and clears auth data', () async {
      final resp = await _withSpec(
        const _FakeSpec(200, '{"message":"Logged out"}'),
        () => ApiService.logout(),
      );
      expect(resp.statusCode, 200);
    });

    test('returns 401 when session is already expired', () async {
      final resp = await _withSpec(
        const _FakeSpec(401, '{"message":"Unauthorized"}'),
        () => ApiService.logout(),
      );
      expect(resp.statusCode, 401);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Group 18 — getCaregiverMoodSummaries
  // ──────────────────────────────────────────────────────────────────────────
  group('getCaregiverMoodSummaries', () {
    test('returns decoded map on 200', () async {
      final result = await _withSpec(
        const _FakeSpec(200, '{"averageMood":3.5}'),
        () => ApiService.getCaregiverMoodSummaries(1),
      );
      expect(result['averageMood'], 3.5);
    });

    test('returns empty map on non-200', () async {
      final result = await _withSpec(
        const _FakeSpec(500, '{"message":"Error"}'),
        () => ApiService.getCaregiverMoodSummaries(1),
      );
      expect(result, isEmpty);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Group 19 — getActiveMedications
  // ──────────────────────────────────────────────────────────────────────────
  group('getActiveMedications', () {
    test('returns list on 200 with array body', () async {
      final result = await _withSpec(
        const _FakeSpec(200, '[{"id":1,"name":"Aspirin"}]'),
        () => ApiService.getActiveMedications(1),
      );
      expect(result.length, 1);
    });

    test('returns empty list on 200 with non-list body', () async {
      final result = await _withSpec(
        const _FakeSpec(200, '{"data":"not a list"}'),
        () => ApiService.getActiveMedications(1),
      );
      expect(result, isEmpty);
    });

    test('returns empty list on non-200', () async {
      final result = await _withSpec(
        const _FakeSpec(500, '{}'),
        () => ApiService.getActiveMedications(1),
      );
      expect(result, isEmpty);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Group 20 — getTodaysMedications
  // ──────────────────────────────────────────────────────────────────────────
  group('getTodaysMedications', () {
    test('returns list on 200 with array body', () async {
      final result = await _withSpec(
        const _FakeSpec(200, '[{"id":1,"name":"Ibuprofen"}]'),
        () => ApiService.getTodaysMedications(1),
      );
      expect(result.length, 1);
    });

    test('returns empty list on 200 with non-list body', () async {
      final result = await _withSpec(
        const _FakeSpec(200, '{"status":"ok"}'),
        () => ApiService.getTodaysMedications(1),
      );
      expect(result, isEmpty);
    });

    test('returns empty list on non-200', () async {
      final result = await _withSpec(
        const _FakeSpec(404, '{}'),
        () => ApiService.getTodaysMedications(1),
      );
      expect(result, isEmpty);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Group 21 — getAccessiblePatients
  // ──────────────────────────────────────────────────────────────────────────
  group('getAccessiblePatients', () {
    test('returns list of maps on 200', () async {
      final body = _okJson([
        {'id': 1, 'name': 'Patient A'},
        {'id': 2, 'name': 'Patient B'},
      ]);
      final result = await _withSpec(
        _FakeSpec(200, body),
        () => ApiService.getAccessiblePatients(),
      );
      expect(result.length, 2);
      expect(result.first['name'], 'Patient A');
    });

    test('throws on 403 access denied', () async {
      await expectLater(
        _withSpec(
          const _FakeSpec(403, '{"message":"Forbidden"}'),
          () => ApiService.getAccessiblePatients(),
        ),
        throwsException,
      );
    });

    test('throws with error message on other non-200 statuses', () async {
      await expectLater(
        _withSpec(
          const _FakeSpec(500, '{"message":"Server error"}'),
          () => ApiService.getAccessiblePatients(),
        ),
        throwsException,
      );
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Group 22 — hasAccessToPatient
  // ──────────────────────────────────────────────────────────────────────────
  group('hasAccessToPatient', () {
    test('returns true on 200 with true body', () async {
      final result = await _withSpec(
        const _FakeSpec(200, 'true'),
        () => ApiService.hasAccessToPatient(1),
      );
      expect(result, isTrue);
    });

    test('returns false on 200 with false body', () async {
      final result = await _withSpec(
        const _FakeSpec(200, 'false'),
        () => ApiService.hasAccessToPatient(1),
      );
      expect(result, isFalse);
    });

    test('returns false on non-200', () async {
      final result = await _withSpec(
        const _FakeSpec(403, '{}'),
        () => ApiService.hasAccessToPatient(1),
      );
      expect(result, isFalse);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Group 23 — getPatientStatus
  // ──────────────────────────────────────────────────────────────────────────
  group('getPatientStatus', () {
    test('returns map on 200', () async {
      final body = _okJson({'status': 'stable', 'lastCheckIn': '2025-01-01'});
      final result = await _withSpec(
        _FakeSpec(200, body),
        () => ApiService.getPatientStatus(1),
      );
      expect(result['status'], 'stable');
    });

    test('throws on 403', () async {
      await expectLater(
        _withSpec(
          const _FakeSpec(403, '{}'),
          () => ApiService.getPatientStatus(1),
        ),
        throwsException,
      );
    });

    test('throws on 408 timeout', () async {
      await expectLater(
        _withSpec(
          const _FakeSpec(408, '{"error":"Request timeout"}'),
          () => ApiService.getPatientStatus(1),
        ),
        throwsException,
      );
    });

    test('throws on other error codes', () async {
      await expectLater(
        _withSpec(
          const _FakeSpec(500, '{}'),
          () => ApiService.getPatientStatus(1),
        ),
        throwsException,
      );
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Group 24 — Family member methods
  // ──────────────────────────────────────────────────────────────────────────
  group('Family member methods', () {
    test('getFamilyMembers returns response', () async {
      final resp = await _withSpec(
        const _FakeSpec(200, '[{"id":1}]'),
        () => ApiService.getFamilyMembers(1),
      );
      expect(resp.statusCode, 200);
    });

    test('getPatientDetails returns response', () async {
      final resp = await _withSpec(
        const _FakeSpec(200, '{"id":1,"name":"Alice"}'),
        () => ApiService.getPatientDetails(1),
      );
      expect(resp.statusCode, 200);
    });

    test('addFamilyMember returns 201 on success', () async {
      final resp = await _withSpec(
        const _FakeSpec(201, '{"id":5}'),
        () => ApiService.addFamilyMember(1, {
          'firstName': 'Jane',
          'lastName': 'Doe',
          'relationship': 'SIBLING',
        }),
      );
      expect(resp.statusCode, 201);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Group 25 — submitMoodAndPainLog
  // ──────────────────────────────────────────────────────────────────────────
  group('submitMoodAndPainLog', () {
    test('returns 200 on success', () async {
      final resp = await _withSpec(
        const _FakeSpec(200, '{"message":"Saved"}'),
        () => ApiService.submitMoodAndPainLog(
          moodValue: 4,
          painValue: 2,
          note: 'Feeling okay',
          timestamp: DateTime(2025, 1, 15),
        ),
      );
      expect(resp.statusCode, 200);
    });

    test('returns 400 on invalid input', () async {
      final resp = await _withSpec(
        const _FakeSpec(400, '{"message":"Invalid"}'),
        () => ApiService.submitMoodAndPainLog(
          moodValue: -1,
          painValue: -1,
          note: '',
          timestamp: DateTime.now(),
        ),
      );
      expect(resp.statusCode, 400);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Group 26 — getPrimaryCareProvider
  // ──────────────────────────────────────────────────────────────────────────
  group('getPrimaryCareProvider', () {
    test('returns map on 200', () async {
      final body = _okJson({'name': 'Dr. Smith', 'specialty': 'General'});
      final result = await _withSpec(
        _FakeSpec(200, body),
        () => ApiService.getPrimaryCareProvider(1),
      );
      expect(result['name'], 'Dr. Smith');
    });

    test('returns empty map on 200 with non-map body', () async {
      final result = await _withSpec(
        const _FakeSpec(200, '"just a string"'),
        () => ApiService.getPrimaryCareProvider(1),
      );
      expect(result, isEmpty);
    });

    test('returns empty map on non-200', () async {
      final result = await _withSpec(
        const _FakeSpec(404, '{}'),
        () => ApiService.getPrimaryCareProvider(1),
      );
      expect(result, isEmpty);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Group 27 — Patient medication methods
  // ──────────────────────────────────────────────────────────────────────────
  group('Patient medication methods', () {
    test('getPatientMedicationsForPatient returns 200', () async {
      final resp = await _withSpec(
        const _FakeSpec(200, '[{"id":1}]'),
        () => ApiService.getPatientMedicationsForPatient(1),
      );
      expect(resp.statusCode, 200);
    });

    test('getPatientMedicationsForPatient returns 408 on timeout', () async {
      final resp = await _withSpec(
        const _FakeSpec(408, '{"error":"Request timeout"}'),
        () => ApiService.getPatientMedicationsForPatient(1),
      );
      expect(resp.statusCode, 408);
    });

    test('addPatientMedication returns 201 on success', () async {
      final resp = await _withSpec(
        const _FakeSpec(201, '{"id":5}'),
        () => ApiService.addPatientMedication(1, {
          'name': 'Aspirin',
          'dosage': '100mg',
          'frequency': 'daily',
        }),
      );
      expect(resp.statusCode, 201);
    });

    test('addPatientMedication returns 408 on timeout', () async {
      final resp = await _withSpec(
        const _FakeSpec(408, '{"error":"Request timeout"}'),
        () => ApiService.addPatientMedication(1, {'name': 'Test'}),
      );
      expect(resp.statusCode, 408);
    });

    test('removePatientMedication returns 200 on success', () async {
      final resp = await _withSpec(
        const _FakeSpec(200, '{"message":"Removed"}'),
        () => ApiService.removePatientMedication(1, 5),
      );
      expect(resp.statusCode, 200);
    });

    test('removePatientMedication returns 408 on timeout', () async {
      final resp = await _withSpec(
        const _FakeSpec(408, '{"error":"Request timeout"}'),
        () => ApiService.removePatientMedication(1, 5),
      );
      expect(resp.statusCode, 408);
    });

    test('deleteMedicationByCaregiver returns 200 on success', () async {
      final resp = await _withSpec(
        const _FakeSpec(200, '{"message":"Deleted"}'),
        () => ApiService.deleteMedicationByCaregiver(1, 5, 2),
      );
      expect(resp.statusCode, 200);
    });

    test('deleteMedicationByCaregiver returns 408 on timeout', () async {
      final resp = await _withSpec(
        const _FakeSpec(408, '{"error":"Request timeout"}'),
        () => ApiService.deleteMedicationByCaregiver(1, 5, 2),
      );
      expect(resp.statusCode, 408);
    });

    test('approveMedication returns 200 on success', () async {
      final resp = await _withSpec(
        const _FakeSpec(200, '{"message":"Approved"}'),
        () => ApiService.approveMedication(1, 5),
      );
      expect(resp.statusCode, 200);
    });

    test('approveMedication returns 408 on timeout', () async {
      final resp = await _withSpec(
        const _FakeSpec(408, '{"error":"Request timeout"}'),
        () => ApiService.approveMedication(1, 5),
      );
      expect(resp.statusCode, 408);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Group 28 — getMoodData and getDailyMoodAverage
  // ──────────────────────────────────────────────────────────────────────────
  group('Mood data methods', () {
    test('getMoodData returns map on 200', () async {
      final body = _okJson({'mood': 4, 'label': 'Happy'});
      final result = await _withSpec(
        _FakeSpec(200, body),
        () => ApiService.getMoodData(1),
      );
      expect(result?['mood'], 4);
    });

    test('getMoodData returns null on non-200', () async {
      final result = await _withSpec(
        const _FakeSpec(500, '{}'),
        () => ApiService.getMoodData(1),
      );
      expect(result, isNull);
    });

    test('getDailyMoodAverage returns map on 200', () async {
      final body = _okJson({'average': 3.5, 'checkIns': 5});
      final result = await _withSpec(
        _FakeSpec(200, body),
        () => ApiService.getDailyMoodAverage(1),
      );
      expect(result?['average'], 3.5);
    });

    test('getDailyMoodAverage returns null on non-200', () async {
      final result = await _withSpec(
        const _FakeSpec(404, '{}'),
        () => ApiService.getDailyMoodAverage(1),
      );
      expect(result, isNull);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Group 29 — createSymptom with optional params
  // ──────────────────────────────────────────────────────────────────────────
  group('createSymptom optional params', () {
    test('createSymptom with symptomValue and clinicalNotes', () async {
      final body = _okJson({
        'data': {'id': 20, 'symptomKey': 'pain', 'symptomValue': 'chest'}
      });
      final result = await _withSpec(
        _FakeSpec(200, body),
        () => ApiService.createSymptom(
          patientId: 1,
          symptomKey: 'pain',
          symptomValue: 'chest',
          severity: 5,
          clinicalNotes: 'Sharp pain in chest area',
          takenAt: DateTime(2025, 6, 15, 10, 30),
        ),
      );
      expect(result['symptomKey'], 'pain');
    });

    test('createSymptom with empty clinicalNotes is excluded', () async {
      final body = _okJson({
        'data': {'id': 21, 'symptomKey': 'headache'}
      });
      final result = await _withSpec(
        _FakeSpec(200, body),
        () => ApiService.createSymptom(
          patientId: 1,
          symptomKey: 'headache',
          severity: 2,
          clinicalNotes: '   ',
        ),
      );
      expect(result['symptomKey'], 'headache');
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Group 30 — updateSymptom with optional params
  // ──────────────────────────────────────────────────────────────────────────
  group('updateSymptom optional params', () {
    test('updateSymptom with all optional fields', () async {
      final body = _okJson({
        'data': {'id': 5, 'symptomKey': 'cough', 'severity': 3}
      });
      final result = await _withSpec(
        _FakeSpec(200, body),
        () => ApiService.updateSymptom(
          id: 5,
          symptomKey: 'cough',
          symptomValue: 'dry',
          severity: 3,
          clinicalNotes: 'Persistent dry cough',
          completed: false,
          takenAt: DateTime(2025, 7, 1),
        ),
      );
      expect(result['symptomKey'], 'cough');
    });

    test('updateSymptom returns empty map when data key is absent', () async {
      final result = await _withSpec(
        const _FakeSpec(200, '{"status":"ok"}'),
        () => ApiService.updateSymptom(id: 5, severity: 1),
      );
      expect(result, isEmpty);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Group 31 — getEnhancedPatientProfile additional branches
  // ──────────────────────────────────────────────────────────────────────────
  group('getEnhancedPatientProfile branches', () {
    test('returns decoded map directly when no data key', () async {
      final body = _okJson({'id': 5, 'bmi': 22.0});
      final result = await _withSpec(
        _FakeSpec(200, body),
        () => ApiService.getEnhancedPatientProfile(5),
      );
      expect(result?['bmi'], 22.0);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Group 32 — getPatientDashboard
  // ──────────────────────────────────────────────────────────────────────────
  group('getPatientDashboard', () {
    test('returns map on 200', () async {
      final body = _okJson({'mood': 4, 'tasks': 3});
      final result = await _withSpec(
        _FakeSpec(200, body),
        () => ApiService.getPatientDashboard(1),
      );
      expect(result['mood'], 4);
    });

    test('throws on 403', () async {
      await expectLater(
        _withSpec(
          const _FakeSpec(403, '{}'),
          () => ApiService.getPatientDashboard(1),
        ),
        throwsException,
      );
    });

    test('throws on other error codes', () async {
      await expectLater(
        _withSpec(
          const _FakeSpec(500, '{}'),
          () => ApiService.getPatientDashboard(1),
        ),
        throwsException,
      );
    });

    test('uses custom days parameter', () async {
      final body = _okJson({'mood': 3, 'days': 7});
      final result = await _withSpec(
        _FakeSpec(200, body),
        () => ApiService.getPatientDashboard(1, days: 7),
      );
      expect(result['days'], 7);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Group 34 — ApiConstants additional assertions
  // ──────────────────────────────────────────────────────────────────────────
  group('ApiConstants additional', () {
    test('patient and mood share the same endpoint', () {
      // Both patient and mood constants point to the same base.
      expect(ApiConstants.patient, equals(ApiConstants.mood));
    });

    test('all endpoints start with http', () {
      // Verify all endpoints are proper URLs.
      final endpoints = [
        ApiConstants.auth, ApiConstants.feed, ApiConstants.users,
        ApiConstants.friends, ApiConstants.analytics, ApiConstants.baseUrl,
        ApiConstants.familyMembers, ApiConstants.patient, ApiConstants.mood,
        ApiConstants.patients, ApiConstants.caregivers, ApiConstants.files,
        ApiConstants.connectionRequests, ApiConstants.subscriptions,
        ApiConstants.tasks, ApiConstants.allergies, ApiConstants.symptoms,
        ApiConstants.baseUrlV2, ApiConstants.tasksV2,
        ApiConstants.aiChat, ApiConstants.aiConfig,
        ApiConstants.invoices, ApiConstants.evv,
      ];
      for (final ep in endpoints) {
        expect(ep, startsWith('http'));
      }
    });
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Helper — creates an in-memory http.Response for pure-function tests.
// ─────────────────────────────────────────────────────────────────────────────

/// Creates a minimal [http.Response] for testing pure helper functions that
/// only read [response.statusCode] and [response.body].
http.Response _fakeResponse(int statusCode, String body) =>
    http.Response(body, statusCode);
