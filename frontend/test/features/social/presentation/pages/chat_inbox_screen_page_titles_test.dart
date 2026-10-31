// Page-title tests for ChatInboxScreen
// (lib/features/social/presentation/pages/chat_inbox_screen.dart): Contacts
// and a conversation open in titled pages (WCAG 2.4.2).
import 'dart:convert';

import 'package:care_connect_app/features/social/presentation/pages/chat_inbox_screen.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../helpers/titled_route_probe.dart';
import '../../../../mock_user_provider.dart';

void main() {
  late TitledRouteProbe probe;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => null,
    );
    ApiService.debugSetHttpClient(MockClient((request) async {
      if (request.url.path.contains('messages/inbox/7')) {
        return http.Response(
            jsonEncode([
              {
                'peerId': 12,
                'peerName': 'Romilda Smith',
                'peerRole': 'PATIENT',
                'content': 'See you at 3',
                'timestamp': '2026-10-26T15:00:00',
                'hasUnread': true,
              }
            ]),
            200);
      }
      return http.Response(jsonEncode([]), 200);
    }));
  });

  tearDown(ApiService.debugResetHttpClient);

  Future<void> pumpInbox(WidgetTester tester) async {
    probe = TitledRouteProbe();
    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [probe],
      home: ChangeNotifierProvider<UserProvider>.value(
        value: MockUserProvider(mockUser: MockUser(id: 7, role: 'PATIENT')),
        child: const ChatInboxScreen(),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('Contacts opens a page titled "My Friends"', (tester) async {
    await pumpInbox(tester);
    expect(await probe.tapAndReadTitle(tester, find.byTooltip('Contacts')),
        'My Friends');
  });

  testWidgets('opening a conversation pushes a page titled "Conversation"',
      (tester) async {
    await pumpInbox(tester);
    expect(await probe.tapAndReadTitle(tester, find.text('Romilda Smith')),
        'Conversation');
  });
}
