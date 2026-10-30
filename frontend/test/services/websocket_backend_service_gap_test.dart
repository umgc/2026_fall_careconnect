// Gap-filling tests for CareConnectWebSocketService.
//
// The existing test file only covers the pre-connect state. These tests run
// the real connect/authenticate/message-routing/disconnect code against a
// throwaway WebSocket server bound to the loopback interface on the port the
// service derives for desktop test runs (http://localhost:8080 -> ws). No
// external host is contacted. SMS tests use the fake HTTP overrides instead,
// because that call goes through package:http.
//
// The service is a process-wide singleton, so every test disconnects in
// tearDown and dispose() is exercised last.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:care_connect_app/services/websocket_backend_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_http_overrides.dart';

const _port = 8080;

/// Loopback WebSocket server that records every text frame it receives.
class _Server {
  _Server(this._http);
  final HttpServer _http;
  final List<Map<String, dynamic>> received = [];
  final List<WebSocket> sockets = [];
  final List<int?> closeCodes = [];
  final _connected = Completer<WebSocket>();

  static Future<_Server> start() async {
    final http = await HttpServer.bind(InternetAddress.loopbackIPv4, _port);
    final s = _Server(http);
    http.listen((req) async {
      if (WebSocketTransformer.isUpgradeRequest(req)) {
        final ws = await WebSocketTransformer.upgrade(req);
        s.sockets.add(ws);
        if (!s._connected.isCompleted) s._connected.complete(ws);
        ws.listen(
          (d) => s.received.add(jsonDecode(d as String)),
          onDone: () => s.closeCodes.add(ws.closeCode),
        );
      } else {
        req.response.statusCode = 404;
        await req.response.close();
      }
    });
    return s;
  }

  Future<WebSocket> get firstClient => _connected.future;

  Future<void> stop() async {
    for (final s in sockets) {
      await s.close();
    }
    await _http.close(force: true);
  }
}

void _storeCredentials({
  String token = 'jwt-abc',
  Map<String, dynamic>? session = const {'id': 42, 'email': 'a@b.c'},
}) {
  final exp =
      DateTime.now().add(const Duration(hours: 2)).millisecondsSinceEpoch ~/
          1000;
  FlutterSecureStorage.setMockInitialValues({
    'jwt_token': token,
    'token_expiry': '$exp',
    if (session != null) 'user_session': jsonEncode(session),
  });
}

Future<void> _pump([int ms = 150]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  final svc = CareConnectWebSocketService.instance;

  // flutter_test reports TargetPlatform.android, which makes the service
  // target the emulator alias 10.0.2.2. Pin a desktop platform so the base URL
  // resolves to http://localhost:8080, where the local test server listens.
  setUpAll(() => debugDefaultTargetPlatformOverride = TargetPlatform.windows);
  tearDownAll(() => debugDefaultTargetPlatformOverride = null);

  setUp(() {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  tearDown(() async {
    await svc.disconnect();
  });

  group('connect with unusable credentials', () {
    // A server is still needed: WebSocketChannel.connect() starts dialing
    // before authentication is attempted.
    late _Server server;
    setUp(() async => server = await _Server.start());
    tearDown(() async {
      await svc.disconnect();
      await server.stop();
    });

    test('missing token fails authentication and resets state', () async {
      final states = <bool>[];
      final sub = svc.connectionStream.listen(states.add);
      FlutterSecureStorage.setMockInitialValues({});

      await expectLater(
        svc.connect(),
        throwsA(predicate((e) => '$e'.contains('No authentication token'))),
      );

      expect(svc.isConnected, isFalse);
      expect(svc.isAuthenticated, isFalse);
      await _pump(20);
      expect(states, containsAllInOrder([true, false]));
      await sub.cancel();
    });

    test('token without a user session is rejected', () async {
      _storeCredentials(session: null);
      await expectLater(
        svc.connect(),
        throwsA(predicate((e) => '$e'.contains('No current user session'))),
      );
      expect(svc.isConnected, isFalse);
    });

    test('session without an id is rejected', () async {
      _storeCredentials(session: {'email': 'a@b.c'});
      await expectLater(
        svc.connect(),
        throwsA(predicate((e) => '$e'.contains('User ID not found'))),
      );
      expect(svc.isAuthenticated, isFalse);
    });
  });

  group('connected session', () {
    late _Server server;

    setUp(() async {
      server = await _Server.start();
      _storeCredentials();
    });

    tearDown(() async {
      await svc.disconnect();
      await server.stop();
    });

    test('connect authenticates and joins the user room', () async {
      await svc.connect();
      await server.firstClient;
      await _pump();

      expect(svc.isConnected, isTrue);
      expect(svc.isAuthenticated, isTrue);
      expect(server.received[0], {
        'type': 'authenticate',
        'token': 'jwt-abc',
        'userId': '42',
      });
      expect(server.received[1], {'type': 'join-user-room', 'userId': '42'});
    });

    test('connect is a no-op when already connected', () async {
      await svc.connect();
      await server.firstClient;
      await _pump();
      final before = server.received.length;

      await svc.connect();
      await _pump();

      expect(server.received.length, before);
      expect(server.sockets, hasLength(1));
    });

    test('sendCallInvitation delivers the invitation frame', () async {
      await svc.connect();
      await server.firstClient;

      final ok = svc.sendCallInvitation(
        recipientId: 'r9',
        callType: 'video',
        callId: 'call-1',
      );
      await _pump();

      expect(ok, isTrue);
      final msg = server.received
          .singleWhere((m) => m['type'] == 'send-video-call-invitation');
      expect(msg['recipientId'], 'r9');
      expect(msg['callType'], 'video');
      expect(msg['callId'], 'call-1');
      expect(msg['senderId'], '42');
      expect(DateTime.tryParse(msg['timestamp'] as String), isNotNull);
    });

    test('video-call-invitation goes to callStream only', () async {
      await svc.connect();
      final ws = await server.firstClient;
      final calls = <Map<String, dynamic>>[];
      final msgs = <Map<String, dynamic>>[];
      final s1 = svc.callStream.listen(calls.add);
      final s2 = svc.messageStream.listen(msgs.add);

      ws.add(jsonEncode({'type': 'video-call-invitation', 'callId': 'c1'}));
      await _pump();

      expect(calls.single['callId'], 'c1');
      expect(msgs, isEmpty);
      await s1.cancel();
      await s2.cancel();
    });

    test('unknown message types are forwarded to messageStream', () async {
      await svc.connect();
      final ws = await server.firstClient;
      final msgs = <Map<String, dynamic>>[];
      final calls = <Map<String, dynamic>>[];
      final s1 = svc.messageStream.listen(msgs.add);
      final s2 = svc.callStream.listen(calls.add);

      ws.add(jsonEncode({'type': 'chat', 'text': 'hi'}));
      await _pump();

      expect(msgs.single, {'type': 'chat', 'text': 'hi'});
      expect(calls, isEmpty);
      await s1.cancel();
      await s2.cancel();
    });

    test('authentication-failed clears the authenticated flag', () async {
      await svc.connect();
      final ws = await server.firstClient;
      expect(svc.isAuthenticated, isTrue);

      ws.add(jsonEncode({'type': 'authentication-failed'}));
      await _pump();

      expect(svc.isAuthenticated, isFalse);
      expect(svc.isConnected, isTrue);
      // Without authentication, invitations are refused.
      expect(
        svc.sendCallInvitation(recipientId: 'r', callType: 'v', callId: 'c'),
        isFalse,
      );
    });

    test('authentication-success restores the authenticated flag', () async {
      await svc.connect();
      final ws = await server.firstClient;
      ws.add(jsonEncode({'type': 'authentication-failed'}));
      await _pump();
      expect(svc.isAuthenticated, isFalse);

      ws.add(jsonEncode({'type': 'authentication-success'}));
      await _pump();

      expect(svc.isAuthenticated, isTrue);
    });

    test('malformed frames are ignored and do not break later routing',
        () async {
      await svc.connect();
      final ws = await server.firstClient;
      final msgs = <Map<String, dynamic>>[];
      final sub = svc.messageStream.listen(msgs.add);

      ws.add('this is not json');
      ws.add(jsonEncode({'type': 'after-garbage'}));
      await _pump();

      expect(msgs.map((m) => m['type']), ['after-garbage']);
      expect(svc.isConnected, isTrue);
      await sub.cancel();
    });

    test('server closing the socket marks the service disconnected', () async {
      await svc.connect();
      final ws = await server.firstClient;
      final states = <bool>[];
      final sub = svc.connectionStream.listen(states.add);

      await ws.close();
      await _pump(300);

      expect(svc.isConnected, isFalse);
      expect(svc.isAuthenticated, isFalse);
      expect(states, contains(false));
      await sub.cancel();
    });

    test('disconnect closes the socket and resets state', () async {
      await svc.connect();
      await server.firstClient;
      final states = <bool>[];
      final sub = svc.connectionStream.listen(states.add);

      await svc.disconnect();

      expect(svc.isConnected, isFalse);
      expect(svc.isAuthenticated, isFalse);
      await _pump(300);
      expect(server.closeCodes, [1000]);
      expect(states, contains(false));
      // After disconnect no invitation can be sent.
      expect(
        svc.sendCallInvitation(recipientId: 'r', callType: 'v', callId: 'c'),
        isFalse,
      );
      await sub.cancel();
    });
  });

  group('sendSMSNotification', () {
    tearDown(() => HttpOverrides.global = null);

    test('returns false without a token and makes no request', () async {
      var calls = 0;
      HttpOverrides.global = FakeHttpOverrides((m, u) {
        calls++;
        return FakeResponse(200, '{}');
      });
      final ok = await svc.sendSMSNotification(
        phoneNumber: '+15550100',
        message: 'hi',
      );
      expect(ok, isFalse);
      expect(calls, 0);
    });

    test('POSTs to the sms endpoint and returns true on 200', () async {
      _storeCredentials();
      String? method;
      Uri? uri;
      HttpOverrides.global = FakeHttpOverrides((m, u) {
        method = m;
        uri = u;
        return FakeResponse(200, '{}');
      });

      final ok = await svc.sendSMSNotification(
        phoneNumber: '+15550100',
        message: 'hello',
      );

      expect(ok, isTrue);
      expect(method, 'POST');
      expect(uri!.path, '/v1/api/sms/send');
    });

    test('returns false on a non-200 response', () async {
      _storeCredentials();
      HttpOverrides.global =
          FakeHttpOverrides((m, u) => FakeResponse(500, 'nope'));
      final ok = await svc.sendSMSNotification(
        phoneNumber: '+15550100',
        message: 'hello',
      );
      expect(ok, isFalse);
    });
  });
}
