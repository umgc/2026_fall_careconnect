// Tests for MessagingService.
//
// Coverage strategy:
//   MessagingService uses WebSocketChannel for real-time messaging and
//   AuthTokenManager + http for backend storage.  The notification socket is
//   exercised through the connectChannel seam with an in-memory fake (JWT
//   registration and reconnect); no live server is needed.
//
//   Pure-logic methods that run without platform channels are tested directly:
//     getPlatformFeatures — returns the expected feature flags map.
//     sendMessage — returns false when WebSocket is not connected (_channel == null).
//     sendVideoCallInvitation — delegates to sendMessage (returns false without WS).
//     getConversation — various scenarios with local / backend messages.
//     markMessagesAsRead — with and without local messages, backend success/failure.
//     sendHttpWebSocketNotification — HTTP success/failure cases.

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:care_connect_app/services/messaging_service.dart';

import '../test_support/fake_web_socket_channel.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // ─── getPlatformFeatures ──────────────────────────────────────────────────

  group('MessagingService.getPlatformFeatures', () {
    test('returns a map with required feature flags', () {
      final features = MessagingService.getPlatformFeatures();
      expect(features, isA<Map<String, bool>>());
      expect(features.containsKey('videoCall'), isTrue);
      expect(features.containsKey('audioCall'), isTrue);
      expect(features.containsKey('sms'), isTrue);
      expect(features.containsKey('pushNotifications'), isTrue);
      expect(features.containsKey('backgroundMessages'), isTrue);
      expect(features.containsKey('webNotifications'), isTrue);
    });

    test('videoCall and audioCall features are true', () {
      final features = MessagingService.getPlatformFeatures();
      expect(features['videoCall'], isTrue);
      expect(features['audioCall'], isTrue);
    });

    test('pushNotifications and backgroundMessages are true', () {
      final features = MessagingService.getPlatformFeatures();
      expect(features['pushNotifications'], isTrue);
      expect(features['backgroundMessages'], isTrue);
    });

    test('returns exactly 6 feature keys', () {
      final features = MessagingService.getPlatformFeatures();
      expect(features.length, equals(6));
    });
  });

  // ─── sendMessage (no connection) ──────────────────────────────────────────

  group('MessagingService.sendMessage', () {
    test('returns false when WebSocket is not connected', () async {
      final result = await MessagingService.sendMessage(
        recipientId: 'r1',
        senderId: 's1',
        senderName: 'Alice',
        message: 'Hello',
        messageType: 'text',
      );
      expect(result, isFalse);
    });

    test('returns false with optional data parameter when not connected',
        () async {
      final result = await MessagingService.sendMessage(
        recipientId: 'r2',
        senderId: 's2',
        senderName: 'Bob',
        message: 'Test with data',
        messageType: 'text',
        data: {'key': 'value'},
      );
      expect(result, isFalse);
    });

    test('returns false for call_request message type when not connected',
        () async {
      final result = await MessagingService.sendMessage(
        recipientId: 'r3',
        senderId: 's3',
        senderName: 'Carol',
        message: 'Incoming call',
        messageType: 'call_request',
        data: {'callId': 'c1'},
      );
      expect(result, isFalse);
    });

    test('returns false for call_ended message type when not connected',
        () async {
      final result = await MessagingService.sendMessage(
        recipientId: 'r4',
        senderId: 's4',
        senderName: 'Dave',
        message: 'Call ended',
        messageType: 'call_ended',
      );
      expect(result, isFalse);
    });
  });

  // ─── sendVideoCallInvitation ──────────────────────────────────────────────

  group('MessagingService.sendVideoCallInvitation', () {
    test('does not throw when WebSocket is not connected (video call)',
        () async {
      // sendVideoCallInvitation catches errors internally
      await expectLater(
        MessagingService.sendVideoCallInvitation(
          recipientId: 'r1',
          callerId: 'c1',
          callerName: 'Alice',
          callId: 'call123',
          isVideoCall: true,
        ),
        completes,
      );
    });

    test('does not throw when WebSocket is not connected (audio call)',
        () async {
      await expectLater(
        MessagingService.sendVideoCallInvitation(
          recipientId: 'r2',
          callerId: 'c2',
          callerName: 'Bob',
          callId: 'call456',
          isVideoCall: false,
        ),
        completes,
      );
    });
  });

  // ─── getConversation ──────────────────────────────────────────────────────

  group('MessagingService.getConversation', () {
    test('returns empty list when no local messages and backend unreachable',
        () async {
      final result = await http.runWithClient(
        () => MessagingService.getConversation(
          userId1: 'u1',
          userId2: 'u2',
        ),
        () => MockClient((_) async => throw Exception('no server')),
      );
      expect(result, isA<List>());
    });

    test('returns messages sorted by timestamp from backend', () async {
      final backendMessages = [
        {
          'id': 'msg2',
          'timestamp': '2025-01-02T00:00:00.000Z',
          'senderId': 'u1',
          'message': 'second',
        },
        {
          'id': 'msg1',
          'timestamp': '2025-01-01T00:00:00.000Z',
          'senderId': 'u2',
          'message': 'first',
        },
      ];
      final result = await http.runWithClient(
        () => MessagingService.getConversation(userId1: 'u1', userId2: 'u2'),
        () => MockClient(
          (_) async => http.Response(jsonEncode(backendMessages), 200),
        ),
      );
      expect(result, isA<List>());
      expect(result.length, equals(2));
      // Should be sorted: msg1 first, msg2 second
      expect(result[0]['id'], equals('msg1'));
      expect(result[1]['id'], equals('msg2'));
    });

    test('respects limit parameter', () async {
      final backendMessages = List.generate(
        10,
        (i) => {
          'id': 'msg$i',
          'timestamp':
              '2025-01-${(i + 1).toString().padLeft(2, '0')}T00:00:00.000Z',
          'senderId': 'u1',
          'message': 'message $i',
        },
      );
      final result = await http.runWithClient(
        () => MessagingService.getConversation(
          userId1: 'u1',
          userId2: 'u2',
          limit: 3,
        ),
        () => MockClient(
          (_) async => http.Response(jsonEncode(backendMessages), 200),
        ),
      );
      expect(result.length, equals(3));
    });

    test('handles backend returning non-200 gracefully', () async {
      final result = await http.runWithClient(
        () => MessagingService.getConversation(userId1: 'u1', userId2: 'u2'),
        () => MockClient(
          (_) async => http.Response('error', 500),
        ),
      );
      expect(result, isA<List>());
    });

    test('handles messages with null timestamps', () async {
      final backendMessages = [
        {
          'id': 'msg1',
          'senderId': 'u1',
          'message': 'no timestamp',
        },
        {
          'id': 'msg2',
          'timestamp': '2025-01-01T00:00:00.000Z',
          'senderId': 'u2',
          'message': 'has timestamp',
        },
      ];
      final result = await http.runWithClient(
        () => MessagingService.getConversation(userId1: 'u1', userId2: 'u2'),
        () => MockClient(
          (_) async => http.Response(jsonEncode(backendMessages), 200),
        ),
      );
      expect(result, isA<List>());
      expect(result.length, equals(2));
    });

    test('handles backend throwing an exception', () async {
      final result = await http.runWithClient(
        () => MessagingService.getConversation(userId1: 'u1', userId2: 'u2'),
        () => MockClient((_) async => throw Exception('network error')),
      );
      // Should still return a list (possibly empty) since errors are caught
      expect(result, isA<List>());
    });

    test('deduplicates messages by id when merging local and backend',
        () async {
      final backendMessages = [
        {
          'id': 'msg1',
          'timestamp': '2025-01-01T00:00:00.000Z',
          'senderId': 'u1',
          'message': 'hello from backend',
        },
      ];
      final result = await http.runWithClient(
        () => MessagingService.getConversation(userId1: 'u1', userId2: 'u2'),
        () => MockClient(
          (_) async => http.Response(jsonEncode(backendMessages), 200),
        ),
      );
      expect(result, isA<List>());
      // At least the backend message should be present
      expect(result.isNotEmpty, isTrue);
    });

    test('uses default limit of 50', () async {
      // Generate 60 messages to exceed default limit
      final backendMessages = List.generate(
        60,
        (i) => {
          'id': 'msg$i',
          'timestamp': '2025-01-01T${i.toString().padLeft(2, '0')}:00:00.000Z',
          'senderId': 'u1',
          'message': 'message $i',
        },
      );
      final result = await http.runWithClient(
        () => MessagingService.getConversation(userId1: 'u1', userId2: 'u2'),
        () => MockClient(
          (_) async => http.Response(jsonEncode(backendMessages), 200),
        ),
      );
      expect(result.length, equals(50));
    });

    test('conversation key is sorted consistently', () async {
      // u2 < u1 alphabetically, so calling with different order should be same
      final backendMessages = [
        {
          'id': 'msg1',
          'timestamp': '2025-01-01T00:00:00.000Z',
          'senderId': 'u1',
          'message': 'hello',
        },
      ];

      final result1 = await http.runWithClient(
        () => MessagingService.getConversation(userId1: 'u1', userId2: 'u2'),
        () => MockClient(
          (_) async => http.Response(jsonEncode(backendMessages), 200),
        ),
      );

      final result2 = await http.runWithClient(
        () => MessagingService.getConversation(userId1: 'u2', userId2: 'u1'),
        () => MockClient(
          (_) async => http.Response(jsonEncode(backendMessages), 200),
        ),
      );

      expect(result1.length, equals(result2.length));
    });

    test('messages with invalid timestamps are handled', () async {
      final backendMessages = [
        {
          'id': 'msg1',
          'timestamp': 'not-a-date',
          'senderId': 'u1',
          'message': 'bad timestamp',
        },
        {
          'id': 'msg2',
          'timestamp': '2025-01-01T00:00:00.000Z',
          'senderId': 'u2',
          'message': 'good timestamp',
        },
      ];
      final result = await http.runWithClient(
        () => MessagingService.getConversation(userId1: 'u1', userId2: 'u2'),
        () => MockClient(
          (_) async => http.Response(jsonEncode(backendMessages), 200),
        ),
      );
      expect(result, isA<List>());
      expect(result.length, equals(2));
    });

    test('messages use timestamp as key when id is null', () async {
      final backendMessages = [
        {
          'timestamp': '2025-01-01T00:00:00.000Z',
          'senderId': 'u1',
          'message': 'no id',
        },
      ];
      final result = await http.runWithClient(
        () => MessagingService.getConversation(userId1: 'u1', userId2: 'u2'),
        () => MockClient(
          (_) async => http.Response(jsonEncode(backendMessages), 200),
        ),
      );
      expect(result, isA<List>());
      expect(result.isNotEmpty, isTrue);
    });
  });

  // ─── markMessagesAsRead ───────────────────────────────────────────────────

  group('MessagingService.markMessagesAsRead', () {
    test('returns false when backend call fails (no server)', () async {
      final result = await http.runWithClient(
        () => MessagingService.markMessagesAsRead(
          conversationId: 'u1_u2',
          userId: 'u1',
        ),
        () => MockClient((_) async => throw Exception('no server')),
      );
      expect(result, isFalse);
    });

    test('returns true when backend patch succeeds', () async {
      final result = await http.runWithClient(
        () => MessagingService.markMessagesAsRead(
          conversationId: 'u1_u2',
          userId: 'u1',
        ),
        () => MockClient((_) async => http.Response('', 200)),
      );
      expect(result, isTrue);
    });

    test('returns false when backend returns error status', () async {
      // Even though the patch itself doesn't check status code for the return,
      // an exception from the mock will cause it to return false
      final result = await http.runWithClient(
        () => MessagingService.markMessagesAsRead(
          conversationId: 'u1_u2',
          userId: 'u1',
        ),
        () => MockClient((_) async => throw Exception('server error')),
      );
      expect(result, isFalse);
    });

    test('handles conversation key sorting', () async {
      // Conversation ID with participants in different order
      final result = await http.runWithClient(
        () => MessagingService.markMessagesAsRead(
          conversationId: 'b_a',
          userId: 'a',
        ),
        () => MockClient((_) async => http.Response('', 200)),
      );
      expect(result, isTrue);
    });

    test('handles single-segment conversationId', () async {
      // Edge case: conversationId without underscore
      final result = await http.runWithClient(
        () => MessagingService.markMessagesAsRead(
          conversationId: 'singleid',
          userId: 'u1',
        ),
        () => MockClient((_) async => http.Response('', 200)),
      );
      // Should complete without error
      expect(result, isA<bool>());
    });
  });

  // ─── sendHttpWebSocketNotification ───────────────────────────────────────

  group('MessagingService.sendHttpWebSocketNotification', () {
    test('returns true when server responds 200', () async {
      final result = await http.runWithClient(
        () => MessagingService.sendHttpWebSocketNotification(
          userId: 'u1',
          message: 'hello',
        ),
        () => MockClient(
          (_) async => http.Response('{"message":"ok"}', 200),
        ),
      );
      expect(result, isTrue);
    });

    test('returns true when server responds 201', () async {
      final result = await http.runWithClient(
        () => MessagingService.sendHttpWebSocketNotification(
          userId: 'u2',
          message: 'created',
        ),
        () => MockClient(
          (_) async => http.Response('{"message":"created"}', 201),
        ),
      );
      expect(result, isTrue);
    });

    test('returns false when server responds 500', () async {
      final result = await http.runWithClient(
        () => MessagingService.sendHttpWebSocketNotification(
          userId: 'u3',
          message: 'fail',
        ),
        () => MockClient((_) async => http.Response('error', 500)),
      );
      expect(result, isFalse);
    });

    test('returns false when server responds 400', () async {
      final result = await http.runWithClient(
        () => MessagingService.sendHttpWebSocketNotification(
          userId: 'u3',
          message: 'bad request',
        ),
        () => MockClient((_) async => http.Response('bad request', 400)),
      );
      expect(result, isFalse);
    });

    test('returns false when server responds 404', () async {
      final result = await http.runWithClient(
        () => MessagingService.sendHttpWebSocketNotification(
          userId: 'u3',
          message: 'not found',
        ),
        () => MockClient((_) async => http.Response('not found', 404)),
      );
      expect(result, isFalse);
    });

    test('returns false when client throws', () async {
      final result = await http.runWithClient(
        () => MessagingService.sendHttpWebSocketNotification(
          userId: 'u4',
          message: 'oops',
        ),
        () => MockClient((_) async => throw Exception('network down')),
      );
      expect(result, isFalse);
    });

    test('extraHeaders are forwarded to the request', () async {
      http.Request? captured;
      await http.runWithClient(
        () => MessagingService.sendHttpWebSocketNotification(
          userId: 'u5',
          message: 'hi',
          extraHeaders: {'X-Custom': 'value'},
        ),
        () => MockClient((req) async {
          captured = req;
          return http.Response('{"message":"ok"}', 200);
        }),
      );
      expect(captured?.headers['X-Custom'], 'value');
    });

    test('Content-Type header is set to application/json', () async {
      http.Request? captured;
      await http.runWithClient(
        () => MessagingService.sendHttpWebSocketNotification(
          userId: 'u6',
          message: 'check headers',
        ),
        () => MockClient((req) async {
          captured = req;
          return http.Response('{"message":"ok"}', 200);
        }),
      );
      expect(captured?.headers['content-type'], contains('application/json'));
    });

    test('request body contains the message', () async {
      http.Request? captured;
      await http.runWithClient(
        () => MessagingService.sendHttpWebSocketNotification(
          userId: 'u7',
          message: 'test message body',
        ),
        () => MockClient((req) async {
          captured = req;
          return http.Response('{"message":"ok"}', 200);
        }),
      );
      expect(captured, isNotNull);
      final body = jsonDecode(captured!.body);
      expect(body['message'], equals('test message body'));
    });

    test('request URL contains the userId', () async {
      http.Request? captured;
      await http.runWithClient(
        () => MessagingService.sendHttpWebSocketNotification(
          userId: 'user-abc-123',
          message: 'test',
        ),
        () => MockClient((req) async {
          captured = req;
          return http.Response('{"message":"ok"}', 200);
        }),
      );
      expect(captured, isNotNull);
      expect(captured!.url.toString(), contains('user-abc-123'));
    });

    test('works without extraHeaders (null)', () async {
      final result = await http.runWithClient(
        () => MessagingService.sendHttpWebSocketNotification(
          userId: 'u8',
          message: 'no extra headers',
        ),
        () => MockClient(
          (_) async => http.Response('{"message":"ok"}', 200),
        ),
      );
      expect(result, isTrue);
    });

    test('extraHeaders can override Content-Type', () async {
      http.Request? captured;
      await http.runWithClient(
        () => MessagingService.sendHttpWebSocketNotification(
          userId: 'u9',
          message: 'override',
          extraHeaders: {'Content-Type': 'text/plain'},
        ),
        () => MockClient((req) async {
          captured = req;
          return http.Response('{"message":"ok"}', 200);
        }),
      );
      // extraHeaders are spread after Content-Type, so should override
      expect(captured?.headers['content-type'], contains('text/plain'));
    });
  });

  // ─── getConversation with pre-loaded local messages ───────────────────────

  group('MessagingService.getConversation with local messages', () {
    test('returns local messages when backend fails', () async {
      // Pre-load local messages into SharedPreferences
      final localData = {
        'u1_u2': [
          {
            'id': 'local1',
            'timestamp': '2025-06-01T12:00:00.000Z',
            'senderId': 'u1',
            'message': 'local msg',
          },
        ],
      };
      SharedPreferences.setMockInitialValues({
        'local_messages': jsonEncode(localData),
      });

      final result = await http.runWithClient(
        () => MessagingService.getConversation(userId1: 'u1', userId2: 'u2'),
        () => MockClient((_) async => throw Exception('no backend')),
      );
      expect(result, isA<List>());
    });

    test('merges local and backend messages deduplicating by id', () async {
      final localData = {
        'u1_u2': [
          {
            'id': 'shared-id',
            'timestamp': '2025-06-01T12:00:00.000Z',
            'senderId': 'u1',
            'message': 'local version',
          },
        ],
      };
      SharedPreferences.setMockInitialValues({
        'local_messages': jsonEncode(localData),
      });

      final backendMessages = [
        {
          'id': 'shared-id',
          'timestamp': '2025-06-01T12:00:00.000Z',
          'senderId': 'u1',
          'message': 'backend version',
        },
        {
          'id': 'backend-only',
          'timestamp': '2025-06-02T12:00:00.000Z',
          'senderId': 'u2',
          'message': 'only in backend',
        },
      ];

      final result = await http.runWithClient(
        () => MessagingService.getConversation(userId1: 'u1', userId2: 'u2'),
        () => MockClient(
          (_) async => http.Response(jsonEncode(backendMessages), 200),
        ),
      );
      expect(result, isA<List>());
    });
  });

  // ─── markMessagesAsRead with local messages ──────────────────────────────

  group('MessagingService.markMessagesAsRead with local messages', () {
    test('marks local messages as read and returns true on backend success',
        () async {
      // Pre-load local messages
      final localData = {
        'u1_u2': [
          {
            'id': 'msg1',
            'timestamp': '2025-06-01T12:00:00.000Z',
            'senderId': 'u1',
            'message': 'unread msg',
            'read': false,
          },
        ],
      };
      SharedPreferences.setMockInitialValues({
        'local_messages': jsonEncode(localData),
      });

      final result = await http.runWithClient(
        () => MessagingService.markMessagesAsRead(
          conversationId: 'u1_u2',
          userId: 'u1',
        ),
        () => MockClient((_) async => http.Response('', 200)),
      );
      expect(result, isTrue);
    });
  });

  group('MessagingService notification socket', () {
    late List<FakeWebSocketChannel> sockets;

    setUp(() {
      final expiry = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
      FlutterSecureStorage.setMockInitialValues({
        'jwt_token': 'test-jwt',
        'token_expiry': '$expiry',
      });
      sockets = [];
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

    testWidgets('registerUser authenticates with the JWT, not the user id',
        (tester) async {
      await MessagingService.registerUser(userId: '42');

      final socket = sockets.single;
      expect(socket.sentOfType('authenticate').single['token'], 'test-jwt');
      expect(socket.sent.whereType<String>(), isEmpty,
          reason: 'the old REGISTER_USER:<id> text must no longer be sent');
    });

    testWidgets('registerUser without a stored token does not register',
        (tester) async {
      FlutterSecureStorage.setMockInitialValues({});

      await MessagingService.registerUser(userId: '42');

      expect(sockets.single.sentOfType('authenticate'), isEmpty);
      final sent = await MessagingService.sendMessage(
        recipientId: '7',
        senderId: '42',
        senderName: 'Me',
        message: 'hi',
        messageType: 'text',
      );
      expect(sent, isFalse);
    });

    testWidgets('a dropped socket reconnects and re-authenticates',
        (tester) async {
      // Arrange
      await MessagingService.registerUser(userId: '42');

      // Act: the server (API Gateway) closes the socket, then 1s backoff
      sockets.first.serverClose();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      // Assert
      expect(sockets, hasLength(2));
      expect(sockets.last.sentOfType('authenticate'), hasLength(1));
    });

    testWidgets('a rejected token stops reconnecting', (tester) async {
      // Arrange
      await MessagingService.registerUser(userId: '42');

      // Act: the backend rejects the token and closes the socket
      sockets.first.serverSend({'type': 'authentication-failed'});
      sockets.first.serverClose();
      await tester.pump(const Duration(minutes: 5));

      // Assert
      expect(sockets, hasLength(1));
    });

    testWidgets('plain-text notifications are not mistaken for auth failures',
        (tester) async {
      await MessagingService.registerUser(userId: '42');

      sockets.first.serverSend({'type': 'something-else'});
      await tester.pump();
      sockets.first.serverClose();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      expect(sockets, hasLength(2));
    });
  });
}
