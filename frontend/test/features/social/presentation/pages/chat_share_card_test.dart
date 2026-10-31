import 'dart:convert';

import 'package:care_connect_app/features/social/presentation/pages/chat_room_screen.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../mock_user_provider.dart';

const _shareResponse = {
  'message': {
    'id': 55,
    'senderId': 1,
    'receiverId': 2,
    'content': 'Shared my Medicare records',
    'timestamp': '2026-10-24T14:02:11',
    'read': false,
    'shareKind': 'MEDICARE',
    'sharePatientId': 10,
    'attachmentId': null,
  },
  'receiverCanView': false,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var linked = true;
  var messagingAllowed = true;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
      const EventChannel('dev.fluttercommunity.plus/connectivity_status'),
      MockStreamHandler.inline(onListen: (_, __) {}),
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async {
        if (call.method == 'check') return ['wifi'];
        return null;
      },
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        if (call.method == 'readAll') return <String, String>{};
        if (call.method == 'read') return null;
        if (call.method == 'containsKey') return false;
        return null;
      },
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.llfbandit.record/messages'),
      (call) async => null,
    );
    ApiService.debugSetHttpClient(
      MockClient((request) async {
        if (request.url.path.endsWith(
          '/caregiver-patient-links/patients/1/caregivers',
        )) {
          return http.Response(
            jsonEncode(
              linked
                  ? [
                      {
                        'caregiverUserId': 2,
                        'patientMessagingEnabled': messagingAllowed,
                      },
                    ]
                  : [],
            ),
            200,
          );
        }
        return http.Response('{}', 200);
      }),
    );
    linked = true;
    messagingAllowed = true;
  });

  tearDown(() {
    ApiService.debugResetHttpClient();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
      const EventChannel('dev.fluttercommunity.plus/connectivity_status'),
      null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.llfbandit.record/messages'),
      null,
    );
  });

  Future<void> pumpChat(
    WidgetTester tester, {
    String role = 'PATIENT',
    required Future<http.Response> Function({
      required int receiverId,
      required String kind,
    }) shareCardSender,
  }) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<UserProvider>.value(
        value: MockUserProvider(
          mockUser: MockUser(id: 1, role: role, patientId: 10),
        ),
        child: MaterialApp.router(
          routerConfig: GoRouter(
            initialLocation: '/chat',
            routes: [
              GoRoute(
                path: '/chat',
                builder: (context, state) => ChatRoomScreen(
                  peerUserId: 2,
                  peerName: 'Alex',
                  conversationLoader:
                      ({required user1, required user2}) async => [],
                  shareCardSender: shareCardSender,
                  enableWebSocket: false,
                ),
              ),
              GoRoute(
                path: '/medicare-sharing',
                builder: (context, state) =>
                    const Scaffold(body: Text('Medicare sharing')),
              ),
            ],
          ),
        ),
      ),
    );
    for (var attempt = 0; attempt < 10; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump();
    }
  }

  Future<void> openShareMenu(WidgetTester tester, String item) async {
    await tester.tap(find.byTooltip('Share health information'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(item));
    await tester.pumpAndSettle();
  }

  testWidgets('patient with linked, enabled caregiver can send Medicare card', (
    tester,
  ) async {
    int? capturedReceiverId;
    String? capturedKind;
    await pumpChat(
      tester,
      shareCardSender: ({required int receiverId, required String kind}) async {
        capturedReceiverId = receiverId;
        capturedKind = kind;
        return http.Response(jsonEncode(_shareResponse), 200);
      },
    );

    expect(find.byTooltip('Share health information'), findsOneWidget);
    await openShareMenu(tester, 'Share Medicare records');

    expect(capturedReceiverId, 2);
    expect(capturedKind, 'MEDICARE');
    expect(
      find.text('Alex can\'t see your Medicare records yet. Share now?'),
      findsOneWidget,
    );
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(
      find.text('Test User shared their Medicare records · Open'),
      findsOneWidget,
    );
  });

  testWidgets('Medicare consent Share now opens the sharing route', (
    tester,
  ) async {
    await pumpChat(
      tester,
      shareCardSender: ({required receiverId, required kind}) async =>
          http.Response(jsonEncode(_shareResponse), 200),
    );

    await openShareMenu(tester, 'Share Medicare records');
    await tester.tap(find.text('Share now'));
    await tester.pumpAndSettle();

    expect(find.text('Medicare sharing'), findsOneWidget);
  });

  testWidgets('health share renders a card and never shows Medicare consent', (
    tester,
  ) async {
    await pumpChat(
      tester,
      shareCardSender: ({required receiverId, required kind}) async =>
          http.Response(
        jsonEncode({
          ..._shareResponse,
          'message': {
            ...(_shareResponse['message'] as Map<String, dynamic>),
            'content': 'Shared my health information',
            'shareKind': 'HEALTH',
          },
        }),
        200,
      ),
    );

    await openShareMenu(tester, 'Share health information');

    expect(
      find.text('Test User shared their health information · Open'),
      findsOneWidget,
    );
    expect(find.textContaining('can\'t see your Medicare'), findsNothing);
  });

  testWidgets('Medicare 409 explains the connection requirement', (
    tester,
  ) async {
    await pumpChat(
      tester,
      shareCardSender: ({required receiverId, required kind}) async =>
          http.Response('{"error":"conflict"}', 409),
    );

    await openShareMenu(tester, 'Share Medicare records');
    expect(find.text('Connect Medicare before sharing it.'), findsOneWidget);
  });

  testWidgets('403 and 400 share failures explain the backend contract', (
    tester,
  ) async {
    var response = http.Response('{"error":"forbidden"}', 403);
    await pumpChat(
      tester,
      shareCardSender: ({required receiverId, required kind}) async => response,
    );

    await openShareMenu(tester, 'Share Medicare records');
    expect(
      find.text('You can\'t send messages to this user.'),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 5));

    response = http.Response('{"error":"Unknown share kind"}', 400);
    await tester.tap(find.byTooltip('Share health information'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Share health information'));
    await tester.pumpAndSettle();
    expect(find.text('Unknown share kind.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));

    response = http.Response('{"error":"receiverId is required"}', 400);
    await tester.tap(find.byTooltip('Share health information'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Share Medicare records'));
    await tester.pumpAndSettle();
    expect(find.text('receiverId is required.'), findsOneWidget);
  });

  testWidgets('share action is hidden for caregivers', (tester) async {
    await pumpChat(
      tester,
      role: 'CAREGIVER',
      shareCardSender: ({required receiverId, required kind}) async =>
          http.Response('{}', 200),
    );

    expect(find.byTooltip('Share health information'), findsNothing);
  });

  testWidgets('share action is hidden when messaging is disabled', (
    tester,
  ) async {
    messagingAllowed = false;
    await pumpChat(
      tester,
      shareCardSender: ({required receiverId, required kind}) async =>
          http.Response('{}', 200),
    );

    expect(find.byTooltip('Share health information'), findsNothing);
  });

  testWidgets('share action is hidden when caregiver is not linked', (
    tester,
  ) async {
    linked = false;
    await pumpChat(
      tester,
      shareCardSender: ({required receiverId, required kind}) async =>
          http.Response('{}', 200),
    );

    expect(find.byTooltip('Share health information'), findsNothing);
  });
}
