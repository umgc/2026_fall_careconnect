// MessagingWidget app bar call actions, the over-limit composer state and a
// successful send over an in-memory messaging socket.

import 'package:care_connect_app/services/messaging_service.dart';
import 'package:care_connect_app/widgets/messaging_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../test_support/fake_web_socket_channel.dart';

const _secureStorage =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

Future<Object?> _openAndTap(WidgetTester tester, IconData icon) async {
  Object? popped = 'none';
  await http.runWithClient(() async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                popped = await Navigator.of(context).push<Object?>(
                  MaterialPageRoute(
                    builder: (_) => const MessagingWidget(
                      currentUserId: '1',
                      currentUserName: 'Me',
                      recipientId: '2',
                      recipientName: 'Pat',
                    ),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Pat'), findsWidgets);
    await tester.tap(find.byIcon(icon));
    await tester.pumpAndSettle();
  }, () => MockClient((_) async => http.Response('[]', 200)));
  return popped;
}

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorage, (call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorage, null);
  });

  testWidgets('video call action pops with video_call', (tester) async {
    expect(await _openAndTap(tester, Icons.videocam), 'video_call');
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('audio call action pops with audio_call', (tester) async {
    expect(await _openAndTap(tester, Icons.call), 'audio_call');
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('over-limit draft shows the counter and disables send',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await http.runWithClient(() async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MessagingWidget(
              currentUserId: '1',
              currentUserName: 'Me',
              recipientId: '2',
              recipientName: 'Pat',
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      // Text set programmatically (e.g. pasted draft) bypasses maxLength.
      tester.widget<TextField>(find.byType(TextField)).controller!.text =
          'y' * 2005;
      await tester.pump();
    }, () => MockClient((_) async => http.Response('[]', 200)));
    expect(find.text('2005 / 2000'), findsOneWidget);
    final fab =
        tester.widget<FloatingActionButton>(find.byType(FloatingActionButton));
    expect(fab.onPressed, isNull);
  });

  testWidgets('a send over a connected socket appears in the thread',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final expiry =
        (DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600).toString();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorage, (call) async {
      final key = (call.arguments as Map?)?['key'];
      if (call.method != 'read') return null;
      if (key == 'jwt_token') return 'msg-jwt';
      if (key == 'token_expiry') return expiry;
      return null;
    });
    final socket = FakeWebSocketChannel(authReply: null);
    MessagingService.connectChannel = (_) => socket;
    addTearDown(() {
      MessagingService.resetForTest();
      MessagingService.connectChannel = WebSocketChannel.connect;
    });
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await http.runWithClient(() async {
      await MessagingService.registerUser(userId: '1');
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MessagingWidget(
              currentUserId: '1',
              currentUserName: 'Me',
              recipientId: '2',
              recipientName: 'Pat',
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(find.byType(TextField), 'See you soon');
      await tester.pump();
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }, () => MockClient((_) async => http.Response('[]', 200)));
    expect(find.text('See you soon'), findsOneWidget);
    expect(
        socket.sent.whereType<Map<String, dynamic>>().map((m) => m['message']),
        contains('See you soon'));
  });
}
