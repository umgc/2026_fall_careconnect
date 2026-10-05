// MedicareConnectService against the connect-url contract (PR #252 / #255):
//   GET  /v1/api/medicare/connect-url -> { "url": "..." }
//   GET  /v1/api/medicare/status      -> { connected, status, connectedAt }
//   POST /v1/api/medicare/disconnect
//
// The service calls the top-level http.get/http.post, so every request here
// goes through http.runWithClient + MockClient; nothing touches the network.
// AuthTokenManager reads flutter_secure_storage, which has no plugin in the
// test host; its own try/catch falls back to the default headers.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:care_connect_app/features/health/health_data/services/medicare_connect_service.dart';

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

Future<MedicareConnectError?> _connectUrlError(
    Future<http.Response> Function(http.Request) handler) async {
  try {
    await _with(() => MedicareConnectService().fetchConnectUrl(), handler);
    return null;
  } on MedicareConnectException catch (e) {
    return e.error;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'TC-MCR-CONN-014: fetchConnectUrl GETs /v1/api/medicare/connect-url and '
      'returns the one-time link', () async {
    final seen = <http.Request>[];
    final uri = await _with(
      () => MedicareConnectService().fetchConnectUrl(),
      (_) async => http.Response(
          jsonEncode({'url': 'https://api.example.test/oauth2/connect?link=abc'}),
          200),
      seen: seen,
    );
    expect(uri.toString(), 'https://api.example.test/oauth2/connect?link=abc');
    expect(seen, hasLength(1));
    expect(seen.single.method, 'GET');
    expect(seen.single.url.path, '/v1/api/medicare/connect-url');
  });

  test(
      'TC-MCR-CONN-015: fetchConnectUrl maps 401 to signed out, 403 to not the '
      'patient, and any other non-200 to a server error', () async {
    Future<http.Response> Function(http.Request) status(int code) =>
        (_) async => http.Response('{}', code);
    expect(await _connectUrlError(status(401)), MedicareConnectError.signedOut);
    expect(await _connectUrlError(status(403)), MedicareConnectError.notPatient);
    expect(await _connectUrlError(status(404)), MedicareConnectError.server);
    expect(await _connectUrlError(status(409)), MedicareConnectError.server);
    expect(await _connectUrlError(status(500)), MedicareConnectError.server);
  });

  test(
      'TC-MCR-CONN-016: a 200 without a usable absolute url is a server error, '
      'never a launch of something else', () async {
    for (final body in [
      'not json',
      '[]',
      '{}',
      '{"url": 42}',
      '{"url": "/relative/path"}',
      '{"url": ""}',
    ]) {
      expect(
          await _connectUrlError((_) async => http.Response(body, 200)),
          MedicareConnectError.server,
          reason: body);
    }
  });

  test('TC-MCR-CONN-017: a transport failure is reported as a network error',
      () async {
    expect(
        await _connectUrlError(
            (_) async => throw http.ClientException('offline')),
        MedicareConnectError.network);
  });

  test(
      'TC-MCR-CONN-018: status reads LINKED/UNLINKED and connectedAt, and '
      'returns null (not "not connected") when it cannot check', () async {
    Future<MedicareStatus?> status(
            Future<http.Response> Function(http.Request) h,
            [List<http.Request>? seen]) =>
        _with(() => MedicareConnectService().status(), h, seen: seen);

    final seen = <http.Request>[];
    final linked = await status(
        (_) async => http.Response(
            jsonEncode({
              'connected': true,
              'status': 'LINKED',
              'connectedAt': '2026-10-01T14:30:00Z'
            }),
            200),
        seen);
    expect(seen.single.method, 'GET');
    expect(seen.single.url.path, '/v1/api/medicare/status');
    expect(linked!.connected, isTrue);
    expect(linked.connectedAt!.toUtc(), DateTime.utc(2026, 10, 1, 14, 30));

    final unlinked = await status((_) async => http.Response(
        jsonEncode({'connected': false, 'status': 'UNLINKED', 'connectedAt': null}),
        200));
    expect(unlinked!.connected, isFalse);
    expect(unlinked.connectedAt, isNull);

    expect(await status((_) async => http.Response('{}', 500)), isNull);
    expect(await status((_) async => http.Response('{}', 401)), isNull);
    expect(await status((_) async => http.Response('not json', 200)), isNull);
    expect(await status((_) async => http.Response('[]', 200)), isNull);
    expect(
        await status((_) async => throw http.ClientException('offline')), isNull);
  });

  test(
      'TC-MCR-CONN-019: disconnect POSTs /v1/api/medicare/disconnect and is '
      'true only on 200/204', () async {
    Future<bool> disconnect(Future<http.Response> Function(http.Request) h,
            [List<http.Request>? seen]) =>
        _with(() => MedicareConnectService().disconnect(), h, seen: seen);

    final seen = <http.Request>[];
    expect(
        await disconnect(
            (_) async => http.Response(
                jsonEncode({'connected': false, 'status': 'UNLINKED'}), 200),
            seen),
        isTrue);
    expect(seen.single.method, 'POST');
    expect(seen.single.url.path, '/v1/api/medicare/disconnect');
    expect(await disconnect((_) async => http.Response('', 204)), isTrue);
    expect(await disconnect((_) async => http.Response('{}', 401)), isFalse);
    expect(await disconnect((_) async => http.Response('{}', 500)), isFalse);
    expect(
        await disconnect((_) async => throw http.ClientException('offline')),
        isFalse);
  });

  test(
      'TC-MCR-CONN-027: with no network connect() requests nothing and '
      'reports offline (FR-MCR-26)', () async {
    final previous = MedicareConnectService.isOffline;
    MedicareConnectService.isOffline = () async => true;
    addTearDown(() => MedicareConnectService.isOffline = previous);
    final seen = <http.Request>[];
    MedicareConnectError? error;
    try {
      await _with(() => MedicareConnectService().connect(),
          (_) async => http.Response('{"url":"https://x.test/"}', 200),
          seen: seen);
    } on MedicareConnectException catch (e) {
      error = e.error;
    }
    expect(error, MedicareConnectError.offline);
    expect(seen, isEmpty);
  });

  test(
      'TC-MCR-CONN-020: parse accepts the US spelling, surrounding spaces and '
      'any case', () {
    expect(MedicareConnectResult.parse('canceled'),
        MedicareConnectResult.cancelled);
    expect(MedicareConnectResult.parse(' Connected '),
        MedicareConnectResult.connected);
    expect(MedicareConnectResult.parse('ALREADY_LINKED'),
        MedicareConnectResult.alreadyLinked);
    expect(MedicareConnectResult.parse(''), isNull);
  });
}
