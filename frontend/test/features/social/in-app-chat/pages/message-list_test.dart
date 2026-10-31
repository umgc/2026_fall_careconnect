// Tests for MessagesListPage
// (lib/features/social/in-app-chat/pages/message-list.dart).
import 'dart:convert';

import 'package:care_connect_app/features/social/in-app-chat/pages/message-list.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../helpers/titled_route_probe.dart';

void main() {
  late TitledRouteProbe probe;

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'local_messages': jsonEncode({
        '1_2': [
          {
            'senderName': 'Romilda Smith',
            'message': 'See you at 3',
            'messageType': 'Patient',
            'timestamp': '2026-10-26T15:00:00',
            'read': false,
          }
        ],
      }),
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => null,
    );
  });

  Future<void> pumpList(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    probe = TitledRouteProbe();
    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [probe],
      home: const MessagesListPage(),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('lists saved conversations with the last message',
      (tester) async {
    await pumpList(tester);
    expect(find.text('Romilda Smith'), findsOneWidget);
    expect(find.text('See you at 3'), findsOneWidget);
  });

  testWidgets('opening a conversation pushes a page titled "Conversation"',
      (tester) async {
    await pumpList(tester);
    expect(await probe.tapAndReadTitle(tester, find.text('Romilda Smith')),
        'Conversation');
  });
}
