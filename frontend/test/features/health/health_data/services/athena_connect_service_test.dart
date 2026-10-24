// AthenaConnectService against AthenaController:
//   GET  /api/athena/status     -> { connected, status, reason? }
//   POST /api/athena/connect    { "consent": true } -> { connected, status, reason?, sync? }
//   POST /api/athena/sync       -> { status, syncedAt, types }
//   POST /api/athena/disconnect -> { disconnected, removed }
//
// Requests go through http.runWithClient + MockClient; nothing touches the
// network.

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/features/health/health_data/services/athena_connect_service.dart';

Future<T> _with<T>(
  Future<T> Function() body,
  Future<http.Response> Function(http.Request req) handler, {
  List<http.Request>? seen,
}) =>
    http.runWithClient(
      body,
      () => MockClient((req) {
        seen?.add(req);
        return handler(req);
      }),
    );

Future<AthenaConnectError?> _error(Future<void> Function() call,
    Future<http.Response> Function(http.Request) handler) async {
  try {
    await _with(call, handler);
    return null;
  } on AthenaConnectException catch (e) {
    return e.error;
  }
}

const _syncJson = {
  'status': 'COMPLETED',
  'syncedAt': '2026-10-14T12:00:00Z',
  'types': [
    {'resourceType': 'Condition', 'outcome': 'STORED', 'count': 3},
    {'resourceType': 'MedicationRequest', 'outcome': 'STORED', 'count': 2},
    {'resourceType': 'Immunization', 'outcome': 'EMPTY', 'count': 0},
    {'resourceType': 'Coverage', 'outcome': 'NOT_GRANTED', 'count': 0},
    {'resourceType': 'Device', 'outcome': 'SCOPE_DENIED', 'count': 0},
    {'resourceType': 'Observation', 'outcome': 'UNAVAILABLE', 'count': 0},
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AthenaConnectService.isOffline = () async => false;
  });

  test('status GETs /api/athena/status and reads connected and reason',
      () async {
    final seen = <http.Request>[];
    final s = await _with(
      () => AthenaConnectService().status(),
      (_) async => http.Response(
          jsonEncode({
            'connected': false,
            'status': 'NOT_CONNECTED',
            'reason': 'NOT_CONSENTED'
          }),
          200),
      seen: seen,
    );
    expect(seen.single.method, 'GET');
    expect(seen.single.url.path, '/api/athena/status');
    expect(s!.connected, isFalse);
    expect(s.reason, AthenaNotConnectedReason.notConsented);
    expect(s.shown, isTrue);

    final c = await _with(
      () => AthenaConnectService().status(),
      (_) async => http.Response(
          jsonEncode({'connected': true, 'status': 'CONNECTED'}), 200),
    );
    expect(c!.connected, isTrue);
    expect(c.reason, isNull);
  });

  test('status: 404 (athena turned off) reads as not connected, like Epic; '
      '403 (not a patient) hides it; failures are null', () async {
    Future<AthenaStatus?> status(int code) => _with(
        () => AthenaConnectService().status(),
        (_) async => http.Response('{}', code));
    final off = (await status(404))!;
    expect(off.shown, isTrue);
    expect(off.connected, isFalse);
    expect(off.available, isFalse);
    expect(off.reason, AthenaNotConnectedReason.sourceUnavailable);
    expect((await status(403))!.shown, isFalse);
    expect(await status(500), isNull);
    expect(
        await _with(() => AthenaConnectService().status(),
            (_) async => throw http.ClientException('down')),
        isNull);
  });

  test('connect POSTs {"consent": true} and returns the first sync', () async {
    final seen = <http.Request>[];
    final s = await _with(
      () => AthenaConnectService().connect(),
      (_) async => http.Response(
          jsonEncode({
            'connected': true,
            'status': 'CONNECTED',
            'sync': _syncJson,
          }),
          200),
      seen: seen,
    );
    expect(seen.single.method, 'POST');
    expect(seen.single.url.path, '/api/athena/connect');
    expect(jsonDecode(seen.single.body), {'consent': true});
    expect(seen.single.headers['Content-Type'], startsWith('application/json'));
    expect(s.connected, isTrue);
    expect(s.sync!.completed, isTrue);
    expect(s.sync!.storedCount, 5);
    expect(s.sync!.notShared.map((t) => t.resourceType),
        ['Coverage', 'Device']);
    expect(s.sync!.failed.map((t) => t.resourceType), ['Observation']);
  });

  test('connect returns every link reason the backend can send', () async {
    const codes = {
      'NO_PATIENT_PROFILE': AthenaNotConnectedReason.noPatientProfile,
      'INCOMPLETE_PROFILE': AthenaNotConnectedReason.incompleteProfile,
      'NOT_MATCHED': AthenaNotConnectedReason.notMatched,
      'AMBIGUOUS_MATCH': AthenaNotConnectedReason.ambiguousMatch,
      'LINK_CONFLICT': AthenaNotConnectedReason.linkConflict,
      'SOURCE_UNAVAILABLE': AthenaNotConnectedReason.sourceUnavailable,
      'SOMETHING_NEW': AthenaNotConnectedReason.unknown,
    };
    for (final e in codes.entries) {
      final s = await _with(
        () => AthenaConnectService().connect(),
        (_) async => http.Response(
            jsonEncode({
              'connected': false,
              'status': 'NOT_CONNECTED',
              'reason': e.key
            }),
            200),
      );
      expect(s.connected, isFalse, reason: e.key);
      expect(s.reason, e.value, reason: e.key);
    }
  });

  test('connect and sync map error codes and statuses', () async {
    Future<http.Response> Function(http.Request) reply(int code,
            [String? errorCode]) =>
        (_) async => http.Response(
            errorCode == null ? '' : jsonEncode({'code': errorCode}), code);
    final connect = AthenaConnectService().connect;
    final sync = AthenaConnectService().sync;
    expect(await _error(connect, reply(409, 'SYNC_IN_PROGRESS')),
        AthenaConnectError.syncInProgress);
    expect(await _error(sync, reply(409, 'NOT_CONNECTED')),
        AthenaConnectError.notConnected);
    expect(await _error(sync, reply(503, 'SOURCE_UNAVAILABLE')),
        AthenaConnectError.sourceUnavailable);
    expect(await _error(connect, reply(401)), AthenaConnectError.signedOut);
    expect(await _error(connect, reply(403)), AthenaConnectError.notPatient);
    expect(await _error(connect, reply(404)), AthenaConnectError.disabled);
    expect(await _error(connect, reply(500)), AthenaConnectError.server);
    expect(
        await _error(
            connect, (_) async => throw http.ClientException('down')),
        AthenaConnectError.network);
  });

  test('nothing is requested while offline', () async {
    AthenaConnectService.isOffline = () async => true;
    final seen = <http.Request>[];
    try {
      await _with(() => AthenaConnectService().connect(),
          (_) async => http.Response('{}', 200),
          seen: seen);
      fail('expected offline');
    } on AthenaConnectException catch (e) {
      expect(e.error, AthenaConnectError.offline);
    }
    expect(seen, isEmpty);
  });

  test('sync POSTs /api/athena/sync and parses the per-type result', () async {
    final seen = <http.Request>[];
    final r = await _with(() => AthenaConnectService().sync(),
        (_) async => http.Response(jsonEncode(_syncJson), 200),
        seen: seen);
    expect(seen.single.url.path, '/api/athena/sync');
    expect(r.syncedAt, DateTime.utc(2026, 10, 14, 12).toLocal());
    expect(r.types, hasLength(6));
    expect(r.types[3].outcome, AthenaTypeOutcome.notGranted);
  });

  test('disconnect is true only on 200', () async {
    final seen = <http.Request>[];
    expect(
        await _with(
            () => AthenaConnectService().disconnect(),
            (_) async => http.Response(
                jsonEncode({'disconnected': true, 'removed': {}}), 200),
            seen: seen),
        isTrue);
    expect(seen.single.method, 'POST');
    expect(seen.single.url.path, '/api/athena/disconnect');
    expect(
        await _with(() => AthenaConnectService().disconnect(),
            (_) async => http.Response('', 500)),
        isFalse);
  });

  // A 401 refreshes the CareConnect sign-in once and retries, the same rule
  // as MedicareConnectService (pattern from its TC-MCR-CONN-033/034).
  group('a 401 refreshes the sign-in once', () {
    const secure = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    final store = <String, String>{};
    // Unsigned test JWTs: only the payload's exp is read.
    String jwt(String sub) =>
        'e30.${base64Url.encode(utf8.encode('{"sub":"$sub","exp":4102444800}')).replaceAll('=', '')}.sig';

    setUp(() {
      store
        ..clear()
        ..['jwt_token'] = jwt('old')
        ..['token_expiry'] = '4102444800';
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(secure, (call) async {
        final args = (call.arguments as Map?) ?? const {};
        final key = args['key'] as String?;
        switch (call.method) {
          case 'read':
            return store[key];
          case 'write':
            store[key!] = args['value'] as String;
            return null;
          case 'delete':
            store.remove(key);
            return null;
          case 'deleteAll':
            store.clear();
            return null;
          case 'containsKey':
            return store.containsKey(key);
          case 'readAll':
            return Map<String, String>.of(store);
        }
        return null;
      });
    });
    tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secure, null));

    test('status: a 401 refreshes once and retries with the new token',
        () async {
      final seen = <http.Request>[];
      final s = await _with(() => AthenaConnectService().status(), (req) async {
        if (req.url.path.endsWith('/refresh-token')) {
          return http.Response(
              jsonEncode({'id': 1, 'email': 'p@example.test', 'role': 'PATIENT',
                  'token': jwt('new')}),
              200);
        }
        final auth = req.headers['Authorization'] ?? '';
        return auth.contains(jwt('new').split('.')[1])
            ? http.Response(jsonEncode({'connected': true, 'status': 'CONNECTED'}), 200)
            : http.Response('{}', 401);
      }, seen: seen);
      expect(s!.connected, isTrue);
      expect(seen.map((r) => '${r.method} ${r.url.path}'), [
        'GET /api/athena/status',
        'POST /v1/api/auth/refresh-token',
        'GET /api/athena/status',
      ]);
      expect(seen.last.headers['Authorization'], 'Bearer ${jwt('new')}');
    });

    test('connect: a refused refresh is signed out after one attempt, with no '
        'second retry', () async {
      final seen = <http.Request>[];
      AthenaConnectError? error;
      try {
        await _with(() => AthenaConnectService().connect(),
            (_) async => http.Response('{}', 401), seen: seen);
      } on AthenaConnectException catch (e) {
        error = e.error;
      }
      expect(error, AthenaConnectError.signedOut);
      expect(seen.map((r) => '${r.method} ${r.url.path}'), [
        'POST /api/athena/connect',
        'POST /v1/api/auth/refresh-token',
      ]);
    });
  });

  test('a 200 whose body is not a JSON object is a server error', () async {
    for (final body in ['[]', 'not json']) {
      expect(
          await _error(() => AthenaConnectService().connect(),
              (_) async => http.Response(body, 200)),
          AthenaConnectError.server,
          reason: body);
      expect(
          await _error(() => AthenaConnectService().sync(),
              (_) async => http.Response(body, 200)),
          AthenaConnectError.server,
          reason: body);
    }
    expect(
        await _with(() => AthenaConnectService().status(),
            (_) async => http.Response('[]', 200)),
        isNull);
  });

  // R381-D01: the backend's proposed answer when athena is turned off.
  test('a DISABLED code reads as athenahealth turned off, whatever the status',
      () async {
    Future<http.Response> Function(http.Request) disabled(int status) =>
        (_) async => http.Response(jsonEncode({'code': 'DISABLED'}), status);
    for (final status in [404, 409, 500, 503]) {
      expect(await _error(AthenaConnectService().connect, disabled(status)),
          AthenaConnectError.disabled, reason: '$status');
      expect(await _error(AthenaConnectService().sync, disabled(status)),
          AthenaConnectError.disabled, reason: '$status');
      final s = await _with(
          () => AthenaConnectService().status(), disabled(status));
      expect(s!.available, isFalse, reason: '$status');
      expect(s.connected, isFalse, reason: '$status');
      expect(s.shown, isTrue, reason: '$status');
    }
  });
}
