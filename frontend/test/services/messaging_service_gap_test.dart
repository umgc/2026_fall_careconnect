// Gap coverage for MessagingService over a connected (in-memory) socket:
// sendMessage payloads, local history persistence and the 100-message cap,
// call invitations, restoring saved history on initialize, and socket errors.
// The socket is a FakeWebSocketChannel, so no network is needed.
import 'dart:async';
import 'dart:convert';

import 'package:care_connect_app/services/messaging_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../test_support/fake_web_socket_channel.dart';

void main() {
  late List<FakeWebSocketChannel> sockets;

  setUp(() {
    final expiry = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
    FlutterSecureStorage.setMockInitialValues({
      'jwt_token': 'test-jwt',
      'token_expiry': '$expiry',
    });
    SharedPreferences.setMockInitialValues({});
    sockets = [];
    MessagingService.resetForTest();
    MessagingService.connectChannel = (_) {
      final socket = FakeWebSocketChannel();
      sockets.add(socket);
      return socket;
    };
  });

  tearDown(() {
    MessagingService.resetForTest();
    MessagingService.connectChannel = WebSocketChannel.connect;
  });

  Future<bool> send(String text, {Map<String, dynamic>? data}) =>
      MessagingService.sendMessage(
        recipientId: 'b',
        senderId: 'a',
        senderName: 'Alice',
        message: text,
        messageType: 'text',
        data: data,
      );

  test('sendMessage writes the payload to the socket and stores it', () async {
    await MessagingService.registerUser(userId: 'a');

    final ok = await send('hello', data: {'k': 'v'});

    expect(ok, isTrue);
    final sent = sockets.single.sent.whereType<Map<String, dynamic>>().last;
    expect(sent['recipientId'], 'b');
    expect(sent['senderName'], 'Alice');
    expect(sent['message'], 'hello');
    expect(sent['messageType'], 'text');
    expect(sent['data'], {'k': 'v'});
    expect(DateTime.tryParse(sent['timestamp'] as String), isNotNull);

    final prefs = await SharedPreferences.getInstance();
    final stored =
        jsonDecode(prefs.getString('local_messages')!) as Map<String, dynamic>;
    expect(stored.keys.single, 'a_b');
    expect((stored['a_b'] as List).single['message'], 'hello');
  });

  test('sendMessage defaults data to an empty map', () async {
    await MessagingService.registerUser(userId: 'a');
    await send('no data');
    final sent = sockets.single.sent.whereType<Map<String, dynamic>>().last;
    expect(sent['data'], isEmpty);
  });

  test('stored history is shared by both participants and capped at 100',
      () async {
    await MessagingService.registerUser(userId: 'a');
    for (var i = 0; i < 102; i++) {
      await send('m$i');
    }

    final fromA = await http.runWithClient(
      () => MessagingService.getConversation(
        userId1: 'a',
        userId2: 'b',
        limit: 500,
      ),
      () => MockClient((_) async => http.Response('', 500)),
    );
    final fromB = await http.runWithClient(
      () => MessagingService.getConversation(
        userId1: 'b',
        userId2: 'a',
        limit: 500,
      ),
      () => MockClient((_) async => http.Response('', 500)),
    );

    expect(fromA, hasLength(100));
    expect(fromB, hasLength(100));
    final texts = fromA.map((m) => m['message']).toSet();
    expect(texts.contains('m0'), isFalse, reason: 'oldest are dropped');
    expect(texts.contains('m101'), isTrue);
  });

  test('sendVideoCallInvitation sends a call_request with call details',
      () async {
    await MessagingService.registerUser(userId: 'a');

    await MessagingService.sendVideoCallInvitation(
      recipientId: 'b',
      callerId: 'a',
      callerName: 'Alice',
      callId: 'call-9',
      isVideoCall: true,
    );
    await MessagingService.sendVideoCallInvitation(
      recipientId: 'b',
      callerId: 'a',
      callerName: 'Alice',
      callId: 'call-10',
      isVideoCall: false,
    );

    final calls = sockets.single.sent
        .whereType<Map<String, dynamic>>()
        .where((m) => m['messageType'] == 'call_request')
        .toList();
    expect(calls, hasLength(2));
    expect(calls[0]['message'], 'Incoming video call');
    expect(calls[0]['data']['callId'], 'call-9');
    expect(calls[0]['data']['isVideoCall'], 'true');
    expect(calls[0]['data']['action'], 'call_invitation');
    expect(calls[1]['message'], 'Incoming audio call');
    expect(calls[1]['data']['isVideoCall'], 'false');
  });

  test('initialize restores saved local history', () async {
    SharedPreferences.setMockInitialValues({
      'local_messages': jsonEncode({
        'a_b': [
          {'id': '1', 'timestamp': '2026-01-01T10:00:00', 'message': 'saved'},
        ],
      }),
    });

    await MessagingService.initialize();
    await MessagingService.initialize(); // second call is a no-op

    expect(sockets, hasLength(1));
    final messages = await http.runWithClient(
      () => MessagingService.getConversation(userId1: 'b', userId2: 'a'),
      () => MockClient((_) async => http.Response('', 500)),
    );
    expect(messages.single['message'], 'saved');
  });

  test('initialize survives corrupt saved history', () async {
    SharedPreferences.setMockInitialValues({'local_messages': 'not json'});
    await MessagingService.initialize();
    expect(sockets, hasLength(1));
  });

  test('initialize swallows a connection failure', () async {
    MessagingService.connectChannel = (_) => throw StateError('no network');
    await MessagingService.initialize();
    expect(
      await send('x'),
      isFalse,
      reason: 'no channel was established',
    );
  });

  test('a socket error drops the connection without throwing', () async {
    final failing = _ErroringChannel();
    MessagingService.resetForTest();
    MessagingService.connectChannel = (_) => failing;
    await MessagingService.registerUser(userId: 'a');
    expect(await send('before error'), isTrue);

    failing.incoming.addError(StateError('boom'));
    await Future<void>.delayed(Duration.zero);

    expect(await send('after'), isFalse);
  });

  test('markMessagesAsRead flags stored messages as read', () async {
    await MessagingService.registerUser(userId: 'a');
    await send('unread');

    late http.Request seen;
    final ok = await http.runWithClient(
      () => MessagingService.markMessagesAsRead(
        conversationId: 'b_a',
        userId: 'a',
      ),
      () => MockClient((r) async {
        seen = r;
        return http.Response('{}', 200);
      }),
    );

    expect(ok, isTrue);
    expect(seen.method, 'PATCH');
    expect(seen.url.path, endsWith('messages/mark-read'));
    expect(jsonDecode(seen.body), {'conversationId': 'b_a'});

    final prefs = await SharedPreferences.getInstance();
    final stored =
        jsonDecode(prefs.getString('local_messages')!) as Map<String, dynamic>;
    expect(
      (stored['a_b'] as List).every((m) => m['read'] == true),
      isTrue,
    );
  });
}

/// Minimal channel whose server side can inject a stream error.
class _ErroringChannel implements WebSocketChannel {
  final StreamController<dynamic> incoming = StreamController<dynamic>();
  final _sink = _NullSink();

  @override
  Stream<dynamic> get stream => incoming.stream;

  @override
  WebSocketSink get sink => _sink;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NullSink implements WebSocketSink {
  @override
  void add(dynamic data) {}

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
