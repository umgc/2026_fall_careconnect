// Extra CallNotificationService coverage: connection reuse,
// connect failures (factory throws, socket errors / closes before auth),
// undecodable frames, send failures while connected, and disposing with an
// outgoing invitation still pending.

import 'dart:async';

import 'package:care_connect_app/services/call_notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../test_support/fake_web_socket_channel.dart';

/// Socket whose incoming stream and sink failures are driven by the test.
class _ScriptedSocket extends FakeWebSocketChannel {
  _ScriptedSocket() : super(authReply: null);

  final StreamController<dynamic> incoming = StreamController<dynamic>();
  bool failSends = false;

  late final _ThrowingSink _throwingSink = _ThrowingSink(this, super.sink);

  @override
  Stream<dynamic> get stream => incoming.stream;

  @override
  WebSocketSink get sink => _throwingSink;
}

class _ThrowingSink implements WebSocketSink {
  _ThrowingSink(this._owner, this._inner);

  final _ScriptedSocket _owner;
  final WebSocketSink _inner;

  @override
  void add(dynamic data) {
    if (_owner.failSends) throw StateError('socket closed');
    _inner.add(data);
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) =>
      _inner.close(closeCode, closeReason);

  @override
  Future<void> get done => _inner.done;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late List<WebSocketChannel> sockets;
  late WebSocketChannel Function() nextSocket;
  late BuildContext hostContext;

  setUp(() {
    final expiry = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
    FlutterSecureStorage.setMockInitialValues({
      'jwt_token': 'test-jwt',
      'token_expiry': '$expiry',
    });
    sockets = [];
    nextSocket = FakeWebSocketChannel.new;
    CallNotificationService.connectChannel = (_) {
      final socket = nextSocket();
      sockets.add(socket);
      return socket;
    };
  });

  tearDown(() {
    CallNotificationService.dispose();
    CallNotificationService.connectChannel = WebSocketChannel.connect;
    CallNotificationService.resetTestState();
  });

  Future<void> host(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) {
          hostContext = context;
          return const Text('home');
        }),
      ),
    ));
  }

  Future<bool> init(String userId) => CallNotificationService.initialize(
        userId: userId,
        userRole: 'PATIENT',
        context: hostContext,
        userDisplayName: 'Pat',
      );

  /// Connects with a scripted socket that authenticates successfully.
  Future<_ScriptedSocket> connectScripted(WidgetTester tester) async {
    final socket = _ScriptedSocket();
    nextSocket = () => socket;
    final pending = init('7');
    await tester.pump();
    socket.incoming.add('{"type":"authentication-success"}');
    await tester.pump();
    expect(await pending, isTrue);
    return socket;
  }

  testWidgets('re-initialising the same user reuses the socket',
      (tester) async {
    await host(tester);
    expect(await init('7'), isTrue);
    expect(await init('7'), isTrue);
    expect(sockets, hasLength(1));
  });

  testWidgets('a socket factory failure is reported as not connected',
      (tester) async {
    await host(tester);
    nextSocket = () => throw StateError('no network');
    expect(await init('7'), isFalse);
  });

  testWidgets('a socket error before authentication fails the connect',
      (tester) async {
    await host(tester);
    final socket = _ScriptedSocket();
    nextSocket = () => socket;
    final pending = init('7');
    await tester.pump();
    socket.incoming.addError(StateError('handshake failed'));
    await tester.pump();
    expect(await pending, isFalse);
  });

  testWidgets('undecodable frames are ignored', (tester) async {
    await host(tester);
    final socket = await connectScripted(tester);
    socket.incoming.add('not json at all');
    socket.incoming.add('[1, 2, 3]');
    await tester.pump();
    expect(find.text('home'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('send failures while connected return false', (tester) async {
    await host(tester);
    final socket = await connectScripted(tester);
    socket.failSends = true;

    expect(
      await CallNotificationService.sendSentimentChannelState(
        callId: 'c1',
        otherPartyId: '2',
        channel: 'voice',
        muted: true,
      ),
      isFalse,
    );
    expect(
      await CallNotificationService.sendEndCallSignal(
        callId: 'c1',
        otherPartyId: '2',
      ),
      isFalse,
    );
    expect(
      await CallNotificationService.sendCallInvitation(
        recipientId: '2',
        recipientRole: 'CAREGIVER',
        callId: 'c1',
        isVideoCall: true,
      ),
      isFalse,
    );
    await tester.pump();
    expect(find.text('Failed to send call invitation. Please try again.'),
        findsOneWidget);
  });

  testWidgets('disposing completes a pending invitation as undelivered',
      (tester) async {
    await host(tester);
    expect(await init('7'), isTrue);
    final invitation = CallNotificationService.sendCallInvitation(
      recipientId: '2',
      recipientRole: 'CAREGIVER',
      callId: 'c-pending',
      isVideoCall: false,
    );
    await tester.pump();
    final socket = sockets.single as FakeWebSocketChannel;
    expect(socket.sentOfType('send-video-call-invitation'), hasLength(1));
    CallNotificationService.dispose();
    expect(await invitation, isFalse);
  });
}
