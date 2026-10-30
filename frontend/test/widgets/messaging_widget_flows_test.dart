// MessagingWidget with a conversation served by a MockClient: message
// bubbles with today / yesterday / older timestamps, the long-message
// counter, and a send while the messaging socket is not connected.

import 'dart:convert';

import 'package:care_connect_app/widgets/messaging_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _secureStorage =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorage, (call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorage, null);
  });

  testWidgets('shows the conversation and reports a failed send',
      (tester) async {
    final now = DateTime.now();
    final messages = [
      {
        'id': 'm1',
        'senderId': '1',
        'message': 'Hello from me',
        'timestamp': now.subtract(const Duration(days: 5)).toIso8601String(),
      },
      {
        'id': 'm2',
        'senderId': '2',
        'message': 'Reply yesterday',
        'timestamp': now.subtract(const Duration(days: 1)).toIso8601String(),
      },
      {
        'id': 'm3',
        'senderId': '2',
        'message': 'Reply today',
        'timestamp': now.toIso8601String(),
      },
    ];
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
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Hello from me'), findsOneWidget);
      expect(find.textContaining('Yesterday'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'x' * 1850);
      await tester.pump();
      expect(find.textContaining('/ '), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'New message');
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Failed to send message'), findsOneWidget);
    }, () => MockClient((_) async => http.Response(jsonEncode(messages), 200)));
  });
}
