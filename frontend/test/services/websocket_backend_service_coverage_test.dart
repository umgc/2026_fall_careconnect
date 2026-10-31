// Additional coverage for CareConnectWebSocketService that does not need a
// live socket: the REST SMS helper (intercepted with http.runWithClient),
// disconnect() without a channel, and dispose().
//
// connect() is not exercised: it hardcodes WebSocketChannel.connect against
// the backend URL, which cannot be redirected deterministically in tests.

import 'dart:async';
import 'dart:convert';

import 'package:care_connect_app/services/websocket_backend_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void _storeToken({bool withToken = true}) {
  final expiry = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
  FlutterSecureStorage.setMockInitialValues({
    if (withToken) 'jwt_token': 'ws-jwt',
    if (withToken) 'token_expiry': '$expiry',
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final svc = CareConnectWebSocketService.instance;

  group('sendSMSNotification', () {
    test('returns false without a token', () async {
      _storeToken(withToken: false);
      final ok =
          await svc.sendSMSNotification(phoneNumber: '555', message: 'hello');
      expect(ok, isFalse);
    });

    test('posts to the SMS endpoint and returns true on 200', () async {
      _storeToken();
      late http.Request seen;
      final ok = await http.runWithClient(
        () => svc.sendSMSNotification(phoneNumber: '555', message: 'hello'),
        () => MockClient((req) async {
          seen = req;
          return http.Response('{}', 200);
        }),
      );
      expect(ok, isTrue);
      expect(seen.url.path, '/v1/api/sms/send');
      expect(seen.headers['Authorization'], 'Bearer ws-jwt');
      expect(jsonDecode(seen.body), {'phoneNumber': '555', 'message': 'hello'});
    });

    test('returns false on non-200', () async {
      _storeToken();
      final ok = await http.runWithClient(
        () => svc.sendSMSNotification(phoneNumber: '1', message: 'm'),
        () => MockClient((_) async => http.Response('bad', 500)),
      );
      expect(ok, isFalse);
    });

    test('returns false when the request throws', () async {
      _storeToken();
      final ok = await http.runWithClient(
        () => svc.sendSMSNotification(phoneNumber: '1', message: 'm'),
        () => MockClient((_) async => throw http.ClientException('down')),
      );
      expect(ok, isFalse);
    });
  });

  test('disconnect without a channel reports disconnected', () async {
    final states = <bool>[];
    final sub = svc.connectionStream.listen(states.add);
    await svc.disconnect();
    await Future<void>.delayed(Duration.zero);
    expect(states, [false]);
    expect(svc.isConnected, isFalse);
    expect(svc.isAuthenticated, isFalse);
    await sub.cancel();
  });

  test('dispose closes all streams', () async {
    final done = Future.wait([
      svc.messageStream.toList(),
      svc.callStream.toList(),
      svc.connectionStream.toList(),
    ]);
    // dispose() fires disconnect() without awaiting it, so disconnect's
    // trailing connectionController.add(false) lands after the controllers
    // are closed. Capture that asynchronous error instead of failing.
    final asyncErrors = <Object>[];
    await runZonedGuarded(() async {
      svc.dispose();
      await Future<void>.delayed(Duration.zero);
    }, (e, _) => asyncErrors.add(e));
    final results = await done;
    expect(results, hasLength(3));
    expect(asyncErrors.whereType<StateError>(), isNotEmpty);
  });
}
