// Additional coverage for MessagingService: successful WebSocket sends with
// local persistence (and 100-message trimming), loading persisted messages on
// initialize, socket error handling, initialisation failures and the
// local-merge paths of getConversation / markMessagesAsRead.

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

/// Channel whose stream can emit errors and whose sink can be made to throw
/// for non-authenticate messages.
class _ControllableChannel implements WebSocketChannel {
  final StreamController<dynamic> incoming = StreamController<dynamic>();
  final List<String> sent = [];
  bool throwOnSend = false;

  late final WebSocketSink _sink = _ControllableSink(this);

  @override
  Stream<dynamic> get stream => incoming.stream;

  @override
  WebSocketSink get sink => _sink;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ControllableSink implements WebSocketSink {
  _ControllableSink(this._channel);
  final _ControllableChannel _channel;

  @override
  void add(dynamic data) {
    final text = data.toString();
    if (_channel.throwOnSend && !text.contains('"authenticate"')) {
      throw StateError('sink closed');
    }
    _channel.sent.add(text);
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void _storeToken() {
  final expiry = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
  FlutterSecureStorage.setMockInitialValues({
    'jwt_token': 'msg-jwt',
    'token_expiry': '$expiry',
  });
}

Future<Map<String, dynamic>> _savedMessages() async {
  final prefs = await SharedPreferences.getInstance();
  return jsonDecode(prefs.getString('local_messages')!) as Map<String, dynamic>;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _storeToken();
  });

  tearDown(() {
    MessagingService.resetForTest();
    MessagingService.connectChannel = WebSocketChannel.connect;
  });

  test('sendMessage over a registered socket persists the message locally',
      () async {
    final socket = FakeWebSocketChannel();
    MessagingService.connectChannel = (_) => socket;
    await MessagingService.registerUser(userId: '10');

    final ok = await MessagingService.sendMessage(
      recipientId: '20',
      senderId: '10',
      senderName: 'Ten',
      message: 'hello',
      messageType: 'text',
      data: {'k': 'v'},
    );
    expect(ok, isTrue);

    final sent = socket.sent.whereType<Map<String, dynamic>>().last;
    expect(sent['message'], 'hello');
    expect(sent['recipientId'], '20');
    expect(sent['data'], {'k': 'v'});

    final saved = await _savedMessages();
    expect((saved['10_20'] as List).last['message'], 'hello');

    // getConversation merges in-memory local messages with backend ones.
    final convo = await http.runWithClient(
      () => MessagingService.getConversation(userId1: '20', userId2: '10'),
      () => MockClient((_) async => http.Response(
            jsonEncode([
              {
                'id': 'b1',
                'timestamp': '2020-01-01T00:00:00.000Z',
                'message': 'from backend',
              },
            ]),
            200,
          )),
    );
    expect(convo.first['message'], 'from backend');
    expect(convo.map((m) => m['message']), contains('hello'));

    // markMessagesAsRead flags the local messages and persists them.
    final read = await http.runWithClient(
      () => MessagingService.markMessagesAsRead(
          conversationId: '20_10', userId: '10'),
      () => MockClient((_) async => http.Response('', 200)),
    );
    expect(read, isTrue);
    final afterRead = await _savedMessages();
    expect(
      (afterRead['10_20'] as List).every((m) => m['read'] == true),
      isTrue,
    );
  });

  test('keeps only the last 100 messages per conversation', () async {
    final socket = FakeWebSocketChannel();
    MessagingService.connectChannel = (_) => socket;
    await MessagingService.registerUser(userId: 'a');

    for (var i = 0; i < 101; i++) {
      await MessagingService.sendMessage(
        recipientId: 'trim',
        senderId: 'a',
        senderName: 'A',
        message: 'm$i',
        messageType: 'text',
      );
    }
    final saved = await _savedMessages();
    final list = saved['a_trim'] as List;
    expect(list, hasLength(100));
    expect(list.last['message'], 'm100');
    expect(list.first['message'], isNot('m0'));
  });

  test('sendVideoCallInvitation sends a call_request message', () async {
    final socket = FakeWebSocketChannel();
    MessagingService.connectChannel = (_) => socket;
    await MessagingService.registerUser(userId: 'c1');

    await MessagingService.sendVideoCallInvitation(
      recipientId: 'c2',
      callerId: 'c1',
      callerName: 'Caller',
      callId: 'call-1',
      isVideoCall: false,
    );
    final sent = socket.sent.whereType<Map<String, dynamic>>().last;
    expect(sent['messageType'], 'call_request');
    expect(sent['message'], 'Incoming audio call');
    expect(sent['data']['callId'], 'call-1');
  });

  test('sendMessage returns false when the socket sink throws', () async {
    final channel = _ControllableChannel();
    MessagingService.connectChannel = (_) => channel;
    await MessagingService.registerUser(userId: 'x');
    channel.throwOnSend = true;

    final ok = await MessagingService.sendMessage(
      recipientId: 'y',
      senderId: 'x',
      senderName: 'X',
      message: 'boom',
      messageType: 'text',
    );
    expect(ok, isFalse);
  });

  test('a socket error drops the registration', () async {
    final channel = _ControllableChannel();
    MessagingService.connectChannel = (_) => channel;
    await MessagingService.registerUser(userId: 'e1');

    channel.incoming.addError(StateError('network down'), StackTrace.current);
    await Future<void>.delayed(Duration.zero);

    final ok = await MessagingService.sendMessage(
      recipientId: 'e2',
      senderId: 'e1',
      senderName: 'E',
      message: 'after error',
      messageType: 'text',
    );
    expect(ok, isFalse, reason: 'channel was cleared by the error handler');
  });

  test('initialize swallows connection factory failures', () async {
    MessagingService.connectChannel =
        (_) => throw StateError('cannot connect');
    await MessagingService.initialize();

    final ok = await MessagingService.sendMessage(
      recipientId: '1',
      senderId: '2',
      senderName: 'n',
      message: 'm',
      messageType: 'text',
    );
    expect(ok, isFalse);
  });

  test('initialize loads persisted local messages', () async {
    SharedPreferences.setMockInitialValues({
      'local_messages': jsonEncode({
        'p1_p2': [
          {
            'id': 'persisted',
            'timestamp': '2024-01-01T00:00:00.000Z',
            'message': 'old',
          },
        ],
      }),
    });
    MessagingService.connectChannel = (_) => FakeWebSocketChannel();
    await MessagingService.initialize();

    final convo = await http.runWithClient(
      () => MessagingService.getConversation(userId1: 'p2', userId2: 'p1'),
      () => MockClient((_) async => http.Response('[]', 500)),
    );
    expect(convo.single['message'], 'old');
  });

  test('initialize tolerates corrupt persisted messages', () async {
    SharedPreferences.setMockInitialValues({'local_messages': 'not-json'});
    final socket = FakeWebSocketChannel();
    MessagingService.connectChannel = (_) => socket;
    await MessagingService.initialize();
    // Still usable afterwards.
    await MessagingService.registerUser(userId: 'z');
    expect(socket.sentOfType('authenticate'), hasLength(1));
  });

  test('getConversation returns [] when processing fails', () async {
    final convo = await http.runWithClient(
      () => MessagingService.getConversation(
          userId1: 'q1', userId2: 'q2', limit: -1),
      () => MockClient((_) async => http.Response('[]', 200)),
    );
    expect(convo, isEmpty);
  });
}
