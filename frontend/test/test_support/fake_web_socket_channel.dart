// In-memory WebSocketChannel for service tests.
//
// Services that accept a socket factory (e.g. CallNotificationService.
// connectChannel) can be handed one of these instead of a real network socket.
// Tests read what the client sent from [FakeWebSocketChannel.sent] and drive
// the server side with [serverSend] / [serverClose].

import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

class FakeWebSocketChannel implements WebSocketChannel {
  /// [authReply] is sent back automatically when the client sends
  /// `{"type":"authenticate"}` — `'authentication-success'`,
  /// `'authentication-failed'`, or null for no reply.
  FakeWebSocketChannel({this.authReply = 'authentication-success'});

  final String? authReply;
  final StreamController<dynamic> _incoming = StreamController<dynamic>();

  /// Every message the client sent, decoded from JSON when possible.
  final List<dynamic> sent = <dynamic>[];

  /// Whether the client closed its end.
  bool get closedByClient => _sink.closed;

  late final _FakeSink _sink = _FakeSink(this);

  /// Messages the client sent with the given `type`.
  List<Map<String, dynamic>> sentOfType(String type) => sent
      .whereType<Map<String, dynamic>>()
      .where((m) => m['type'] == type)
      .toList();

  /// Delivers a JSON message from the server.
  void serverSend(Map<String, dynamic> message) =>
      _incoming.add(jsonEncode(message));

  /// Closes the connection from the server side (the client sees onDone once
  /// the event loop runs, e.g. after `tester.pump()`). Not awaitable: the close
  /// future never completes if the client already cancelled its subscription.
  void serverClose() => unawaited(_incoming.close());

  void _onClientSend(dynamic data) {
    dynamic decoded = data;
    if (data is String) {
      try {
        decoded = jsonDecode(data);
      } catch (_) {
        decoded = data;
      }
    }
    sent.add(decoded);
    if (authReply != null &&
        decoded is Map<String, dynamic> &&
        decoded['type'] == 'authenticate' &&
        !_incoming.isClosed) {
      serverSend({'type': authReply});
    }
  }

  @override
  Stream<dynamic> get stream => _incoming.stream;

  @override
  WebSocketSink get sink => _sink;

  @override
  Future<void> get ready => Future<void>.value();

  @override
  String? get protocol => null;

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  // Stream-channel transforms are not used by the services under test.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSink implements WebSocketSink {
  _FakeSink(this._channel);

  final FakeWebSocketChannel _channel;
  bool closed = false;

  @override
  void add(dynamic data) => _channel._onClientSend(data);

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    closed = true;
  }

  @override
  Future<void> get done => Future<void>.value();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
