import 'package:care_connect_app/features/social/presentation/pages/chat_room_screen.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ChatRoomScreen pending messaging', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    tearDown(() {
      ApiService.debugResetHttpClient();
    });

    testWidgets('keeps pending across refresh and sends after reconnect', (
      tester,
    ) async {
      final userProvider = UserProvider()
        ..setUser(UserSession(
          id: 7,
          email: 'patient@test.careconnect.dev',
          role: 'PATIENT',
          token: 't',
        ));

      bool online = false;
      final delivered = <String>[];
      var chatBuildCount = 0;

      Future<List<dynamic>> loadConversation({
        required int user1,
        required int user2,
      }) async {
        return <dynamic>[];
      }

      Future<void> sendMessage({
        required int senderId,
        required int receiverId,
        required String content,
      }) async {
        if (!online) {
          throw Exception('offline');
        }
        delivered.add(content);
      }

      Future<void> pumpChat() async {
        await tester.pumpWidget(
          ChangeNotifierProvider<UserProvider>.value(
            value: userProvider,
            child: MaterialApp(
              home: ChatRoomScreen(
                key: ValueKey('chat-${chatBuildCount++}'),
                peerUserId: 21,
                peerName: 'Peer User',
                enableAutoSync: false,
                conversationLoader: loadConversation,
                messageSender: sendMessage,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await pumpChat();
      await tester.enterText(find.byType(TextField), 'hello offline');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      expect(find.text('hello offline'), findsOneWidget);
      expect(delivered, isEmpty);

      await pumpChat();
      expect(find.text('hello offline'), findsOneWidget);
      expect(delivered, isEmpty);

      online = true;
      await pumpChat();
      await tester.pumpAndSettle();

      expect(delivered, ['hello offline']);
      expect(find.text('hello offline'), findsNothing);
    });

    testWidgets('resends multiple pending messages in original order', (
      tester,
    ) async {
      final userProvider = UserProvider()
        ..setUser(UserSession(
          id: 7,
          email: 'patient@test.careconnect.dev',
          role: 'PATIENT',
          token: 't',
        ));

      bool online = false;
      final delivered = <String>[];
      var chatBuildCount = 0;

      Future<List<dynamic>> loadConversation({
        required int user1,
        required int user2,
      }) async {
        return <dynamic>[];
      }

      Future<void> sendMessage({
        required int senderId,
        required int receiverId,
        required String content,
      }) async {
        if (!online) {
          throw Exception('offline');
        }
        delivered.add(content);
      }

      Future<void> pumpChat() async {
        await tester.pumpWidget(
          ChangeNotifierProvider<UserProvider>.value(
            value: userProvider,
            child: MaterialApp(
              home: ChatRoomScreen(
                key: ValueKey('chat-multi-${chatBuildCount++}'),
                peerUserId: 21,
                peerName: 'Peer User',
                enableAutoSync: false,
                conversationLoader: loadConversation,
                messageSender: sendMessage,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await pumpChat();

      await tester.enterText(find.byType(TextField), 'first offline');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'second offline');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      expect(find.text('first offline'), findsOneWidget);
      expect(find.text('second offline'), findsOneWidget);
      expect(delivered, isEmpty);

      online = true;
      await pumpChat();
      await tester.pumpAndSettle();

      expect(delivered, ['first offline', 'second offline']);
      expect(find.text('first offline'), findsNothing);
      expect(find.text('second offline'), findsNothing);
    });

    testWidgets('does not resend queued-offline message after reconnect', (
      tester,
    ) async {
      final userProvider = UserProvider()
        ..setUser(UserSession(
          id: 7,
          email: 'patient@test.careconnect.dev',
          role: 'PATIENT',
          token: 't',
        ));

      final mockClient = _QueueThenOnlineClient();
      ApiService.debugSetHttpClient(mockClient);

      const MethodChannel secureStorageChannel =
          MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        secureStorageChannel,
        (MethodCall methodCall) async => null,
      );

      List<dynamic> serverConversation = <dynamic>[];
      var chatBuildCount = 0;

      Future<List<dynamic>> loadConversation({
        required int user1,
        required int user2,
      }) async {
        return serverConversation;
      }

      Future<void> pumpChat({required bool autoSync}) async {
        await tester.pumpWidget(
          ChangeNotifierProvider<UserProvider>.value(
            value: userProvider,
            child: MaterialApp(
              home: ChatRoomScreen(
                key: ValueKey('chat-queue-${chatBuildCount++}'),
                peerUserId: 21,
                peerName: 'Peer User',
                enableAutoSync: autoSync,
                conversationLoader: loadConversation,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await pumpChat(autoSync: false);
      await tester.enterText(find.byType(TextField), 'queued once');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      expect(mockClient.sendMessageCalls, 1);
      expect(find.text('queued once'), findsOneWidget);

      mockClient.queueOffline = false;
      serverConversation = <dynamic>[
        {
          'id': 1001,
          'senderId': 7,
          'receiverId': 21,
          'content': 'queued once',
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        },
      ];

      await pumpChat(autoSync: true);
      await tester.pumpAndSettle();

      expect(mockClient.sendMessageCalls, 1);
      expect(find.text('queued once'), findsOneWidget);
    });

    testWidgets(
        'drops a message the server refuses with 403 and does not retry it', (
      tester,
    ) async {
      final userProvider = UserProvider()
        ..setUser(UserSession(
          id: 7,
          email: 'patient@test.careconnect.dev',
          role: 'PATIENT',
          token: 't',
        ));

      final mockClient = _QueueThenOnlineClient()
        ..queueOffline = false
        ..refuse = true;
      ApiService.debugSetHttpClient(mockClient);

      const MethodChannel secureStorageChannel =
          MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        secureStorageChannel,
        (MethodCall methodCall) async => null,
      );

      Future<List<dynamic>> loadConversation({
        required int user1,
        required int user2,
      }) async {
        return <dynamic>[];
      }

      Future<void> pumpChat(String key) async {
        await tester.pumpWidget(
          ChangeNotifierProvider<UserProvider>.value(
            value: userProvider,
            child: MaterialApp(
              home: ChatRoomScreen(
                key: ValueKey(key),
                peerUserId: 21,
                peerName: 'Peer User',
                enableAutoSync: false,
                conversationLoader: loadConversation,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await pumpChat('chat-refused-0');
      await tester.enterText(find.byType(TextField), 'not allowed');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      expect(mockClient.sendMessageCalls, 1);
      expect(find.text('not allowed'), findsNothing);
      expect(
          find.text("You can't send messages to this user."), findsOneWidget);

      // Reopening the chat does not resend it: it is no longer pending
      await pumpChat('chat-refused-1');
      expect(mockClient.sendMessageCalls, 1);
      expect(find.text('not allowed'), findsNothing);
    });
  });
}

class _QueueThenOnlineClient extends http.BaseClient {
  bool queueOffline = true;
  bool refuse = false;
  int sendMessageCalls = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;

    if (request.method.toUpperCase() == 'POST' &&
        path.contains('messages/send')) {
      sendMessageCalls++;

      if (refuse) {
        return _jsonResponse(
          403,
          body: "You can't send messages to this user.",
          headers: const {'content-type': 'text/plain'},
        );
      }

      if (queueOffline) {
        return _jsonResponse(
          200,
          body: '{"queued":true,"requestId":"q-1"}',
          headers: const {
            'content-type': 'application/json',
            'x-offline-queued': 'true',
            'x-offline-request-id': 'q-1',
          },
        );
      }

      return _jsonResponse(
        200,
        body: '{"id":1001}',
        headers: const {'content-type': 'application/json'},
      );
    }

    if (request.method.toUpperCase() == 'GET') {
      return _jsonResponse(
        200,
        body: '[]',
        headers: const {'content-type': 'application/json'},
      );
    }

    return _jsonResponse(
      200,
      body: '{}',
      headers: const {'content-type': 'application/json'},
    );
  }

  http.StreamedResponse _jsonResponse(
    int statusCode, {
    required String body,
    required Map<String, String> headers,
  }) {
    return http.StreamedResponse(
      Stream<List<int>>.value(body.codeUnits),
      statusCode,
      headers: headers,
      request: http.Request('GET', Uri.parse('http://localhost/mock')),
    );
  }
}
