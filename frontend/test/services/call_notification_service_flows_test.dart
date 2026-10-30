// Flow tests for CallNotificationService
// (lib/services/call_notification_service.dart): incoming-call popup
// accept/decline/cancel, answered/ended/declined feedback, outgoing
// invitations (sent/failed/timeout), channel-state and end-call signals.
// The socket is an in-memory FakeWebSocketChannel via the connectChannel
// seam; the JWT comes from mocked secure storage.

import 'package:care_connect_app/services/call_notification_service.dart';
import 'package:care_connect_app/widgets/incoming_call_popup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
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
    sockets = [];
    CallNotificationService.connectChannel = (_) {
      final socket = FakeWebSocketChannel();
      sockets.add(socket);
      return socket;
    };
  });

  tearDown(() {
    CallNotificationService.dispose();
    CallNotificationService.connectChannel = WebSocketChannel.connect;
    CallNotificationService.resetTestState();
  });

  Future<FakeWebSocketChannel> connect(WidgetTester tester,
      {String role = 'PATIENT', String? name = 'pat@example.test'}) async {
    // The incoming-call popup overflows by a pixel or two with the test
    // font; drop only those layout reports.
    final original = FlutterError.onError;
    FlutterError.onError = (d) {
      if (d.toString().contains('overflowed')) return;
      original?.call(d);
    };
    addTearDown(() => FlutterError.onError = original);
    late BuildContext hostContext;
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => Scaffold(
          body: Builder(builder: (context) {
            hostContext = context;
            return const Text('home');
          }),
        ),
      ),
      GoRoute(
        path: '/video-call-chime',
        builder: (_, s) => Scaffold(body: Text('call:${s.uri.query}')),
      ),
    ]);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    expect(
      await CallNotificationService.initialize(
        userId: '7',
        userRole: role,
        context: hostContext,
        userDisplayName: name,
      ),
      isTrue,
    );
    return sockets.single;
  }

  Future<void> send(WidgetTester tester, FakeWebSocketChannel socket,
      Map<String, dynamic> message) async {
    socket.serverSend(message);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 700));
  }

  testWidgets('incoming call can be declined', (tester) async {
    final socket = await connect(tester);
    await send(tester, socket, {
      'type': 'incoming-video-call',
      'callId': 'call-1',
      'senderId': '2',
      'senderName': 'cg@example.test',
      'senderRole': 'CAREGIVER',
      'callKind': 'care-team',
      'contextPatientUserIds': [7, '7', 'x'],
    });
    expect(find.byType(IncomingCallPopup), findsOneWidget);
    expect(CallNotificationService.isIncomingDialogVisibleForTest, isTrue);

    // A different call while one is visible is ignored; same call too.
    await send(tester, socket, {
      'type': 'incoming-video-call',
      'callId': 'call-2',
      'senderId': '3',
    });
    await send(tester, socket, {
      'type': 'incoming-video-call',
      'callId': 'call-1',
      'senderId': '2',
    });
    expect(find.byType(IncomingCallPopup), findsOneWidget);

    await tester.tap(find.byIcon(Icons.call_end));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(socket.sentOfType('decline-call').single['callId'], 'call-1');
    expect(find.byType(IncomingCallPopup), findsNothing);

    // Declined call ids are suppressed.
    await send(tester, socket, {
      'type': 'incoming-video-call',
      'callId': 'call-1',
      'senderId': '2',
    });
    expect(find.byType(IncomingCallPopup), findsNothing);
  });

  testWidgets('incoming call accept navigates to the call screen',
      (tester) async {
    final socket = await connect(tester, role: 'CAREGIVER', name: 'Cara');
    await send(tester, socket, {
      'type': 'incoming-video-call',
      'callId': 'call-9',
      'callerId': '2',
      'callerName': 'Pat',
      'callerRole': 'PATIENT',
      'isVideoCall': false,
      'isConferenceInvite': true,
      'contextPatientUserId': 7,
      'scheduledVisitId': 'v-1',
    });
    await tester.tap(find.byIcon(Icons.phone).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(socket.sentOfType('accept-call').single['callId'], 'call-9');
    expect(find.textContaining('call:'), findsOneWidget);
    expect(find.textContaining('scheduledVisitId=v-1'), findsOneWidget);
  });

  testWidgets('cancelled invitation and remote end dismiss the popup',
      (tester) async {
    final socket = await connect(tester);
    await send(tester, socket, {
      'type': 'incoming-video-call',
      'callId': 'call-3',
      'senderId': '2',
    });
    expect(find.byType(IncomingCallPopup), findsOneWidget);
    await send(tester, socket,
        {'type': 'call-invitation-cancelled', 'callId': 'call-3'});
    expect(find.byType(IncomingCallPopup), findsNothing);

    await send(tester, socket, {
      'type': 'incoming-video-call',
      'callId': 'call-4',
      'senderId': '2',
    });
    // An end for a different call leaves the popup alone.
    await send(tester, socket, {'type': 'call-ended', 'callId': 'other'});
    expect(find.byType(IncomingCallPopup), findsOneWidget);
    await send(tester, socket, {
      'type': 'call-ended',
      'callId': 'call-4',
      'endedByName': 'Pat',
    });
    expect(find.byType(IncomingCallPopup), findsNothing);
    expect(find.text('Call ended by Pat.'), findsOneWidget);
  });

  testWidgets('answered, declined and malformed messages', (tester) async {
    final socket = await connect(tester);
    await send(tester, socket, {
      'type': 'call-answered',
      'callId': 'call-5',
      'answeredByName': 'Cara',
    });
    expect(find.text('Cara answered. Connecting now…'), findsOneWidget);
    await send(tester, socket, {
      'type': 'call-declined',
      'callId': 'call-5',
      'declinedByName': '',
      'reason': ' ',
    });
    expect(find.text('The recipient declined the call (declined).'),
        findsOneWidget);
    await send(tester, socket, {'type': 'call-ending', 'callId': 'call-5'});
    await send(tester, socket, {'no': 'type'});
  });

  testWidgets('outgoing invitation: sent, failed and timed out',
      (tester) async {
    final socket = await connect(tester, role: 'CAREGIVER', name: '');

    final sent = CallNotificationService.sendCallInvitation(
      recipientId: '9',
      recipientRole: 'PATIENT',
      callId: 'out-1',
      isVideoCall: true,
      callKind: 'CARE_TEAM',
      contextPatientUserIds: [9],
    );
    await tester.pump();
    expect(socket.sentOfType('send-video-call-invitation'), hasLength(1));
    await send(tester, socket,
        {'type': 'call-invitation-sent', 'callId': 'out-1'});
    expect(await sent, isTrue);

    final failed = CallNotificationService.sendCallInvitation(
      recipientId: '9',
      recipientRole: 'CAREGIVER',
      callId: 'out-2',
      isVideoCall: false,
      callType: 'general',
    );
    await tester.pump();
    await send(tester, socket, {
      'type': 'call-invitation-failed',
      'callId': 'out-2',
      'reason': 'offline',
      'recipientRole': 'CAREGIVER',
    });
    expect(await failed, isFalse);
    // Earlier "Calling..." snackbars are queued ahead of this one.
    var shown = false;
    for (var i = 0; i < 16 && !shown; i++) {
      await tester.pump(const Duration(milliseconds: 500));
      shown = find.text('Caregiver is unavailable: offline.')
          .evaluate()
          .isNotEmpty;
    }
    expect(shown, isTrue);

    final timedOut = CallNotificationService.sendCallInvitation(
      recipientId: '9',
      recipientRole: 'PATIENT',
      callId: 'out-3',
      isVideoCall: true,
    );
    await tester.pump(const Duration(seconds: 9));
    expect(await timedOut, isFalse);
  });

  testWidgets('channel-state and end-call signals validate input',
      (tester) async {
    final socket = await connect(tester);
    expect(
      await CallNotificationService.sendSentimentChannelState(
        callId: 'c',
        otherPartyId: '2',
        channel: 'smell',
        muted: true,
      ),
      isFalse,
    );
    expect(
      await CallNotificationService.sendSentimentChannelState(
        callId: 'c',
        otherPartyId: '2',
        channel: ' Voice ',
        muted: true,
        captureMode: 'LIVE',
      ),
      isTrue,
    );
    expect(
      await CallNotificationService.sendEndCallSignal(
          callId: ' ', otherPartyId: '2'),
      isFalse,
    );
    expect(
      await CallNotificationService.sendEndCallSignal(
          callId: 'c', otherPartyId: '2'),
      isTrue,
    );
    expect(socket.sentOfType('end-call'), hasLength(1));
    CallNotificationService.clearActiveCall('c');
    CallNotificationService.clearActiveCall();
  });

  testWidgets('signals and invitations fail when not connected',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    expect(
      await CallNotificationService.sendSentimentChannelState(
          callId: 'c', otherPartyId: '2', channel: 'voice', muted: false),
      isFalse,
    );
    expect(
      await CallNotificationService.sendEndCallSignal(
          callId: 'c', otherPartyId: '2'),
      isFalse,
    );
    expect(
      await CallNotificationService.sendCallInvitation(
          recipientId: '2',
          recipientRole: 'PATIENT',
          callId: 'c',
          isVideoCall: true),
      isFalse,
    );
  });
}
