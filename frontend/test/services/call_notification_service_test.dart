// Tests for CallNotificationService incoming-popup dismiss behavior (L2d) and
// connection lifecycle (authenticate, reconnect after a dropped socket).
// Uses @visibleForTesting hooks and an in-memory socket — no live WebSocket.

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/services/call_notification_service.dart';
import 'package:care_connect_app/widgets/incoming_call_popup.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../test_support/fake_web_socket_channel.dart';

const _incomingCallPayload = {
  'type': 'incoming-video-call',
  'callId': 'call-dismiss-test',
  'senderId': '2',
  'senderName': 'Dr Smith',
  'senderRole': 'CAREGIVER',
  'isVideoCall': true,
  'isConferenceInvite': true,
};

void _suppressLayoutOverflowErrors() {
  final prevOnError = FlutterError.onError!;
  FlutterError.onError = (details) {
    if (details.exceptionAsString().contains('overflowed')) return;
    prevOnError(details);
  };
  addTearDown(() => FlutterError.onError = prevOnError);
}

Future<void> _pumpHost(WidgetTester tester) async {
  _suppressLayoutOverflowErrors();
  await tester.binding.setSurfaceSize(const Size(800, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          CallNotificationService.configureForTest(context: context);
          return const Scaffold(body: Text('host'));
        },
      ),
    ),
  );
}

Future<void> _showIncomingPopup(WidgetTester tester) async {
  CallNotificationService.processNotificationMessageForTest(
      _incomingCallPayload);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  tearDown(() {
    CallNotificationService.dispose();
  });

  group('CallNotificationService incoming popup dismiss (L2d)', () {
    testWidgets('care-team acceptance preserves typed patient context',
        (tester) async {
      await _pumpHost(tester);

      final location = Uri.parse(
        CallNotificationService.acceptedCallLocationForTest(
          callKind: 'care-team',
          contextPatientUserIds: const [7, 8],
        ),
      );

      expect(location.queryParameters['callKind'], 'CARE_TEAM');
      expect(location.queryParameters['contextPatientUserIds'], '7,8');
    });

    testWidgets('accepted family route preserves owner and scheduled visit',
        (tester) async {
      await _pumpHost(tester);

      final location = Uri.parse(
        CallNotificationService.acceptedCallLocationForTest(
          callKind: 'general',
          contextPatientUserIds: const [7],
          callerRole: 'FAMILY_MEMBER',
          scheduledVisitId: '55',
        ),
      );

      expect(location.queryParameters['recipientRole'], 'FAMILY_MEMBER');
      expect(location.queryParameters['scheduledVisitId'], '55');
    });

    testWidgets('callInvitationCancelled_dismissesIncomingPopup_byCallId',
        (tester) async {
      await _pumpHost(tester);
      await _showIncomingPopup(tester);

      expect(find.byType(IncomingCallPopup), findsOneWidget);
      expect(CallNotificationService.isIncomingDialogVisibleForTest, isTrue);

      CallNotificationService.processNotificationMessageForTest({
        'type': 'call-invitation-cancelled',
        'callId': 'call-dismiss-test',
      });
      await tester.pumpAndSettle();

      expect(find.byType(IncomingCallPopup), findsNothing);
      expect(CallNotificationService.isIncomingDialogVisibleForTest, isFalse);
    });

    testWidgets('callEnded_dismissesIncomingPopup_byCallId', (tester) async {
      await _pumpHost(tester);
      await _showIncomingPopup(tester);

      expect(find.byType(IncomingCallPopup), findsOneWidget);

      CallNotificationService.processNotificationMessageForTest({
        'type': 'call-ended',
        'callId': 'call-dismiss-test',
        'endedBy': '2',
      });
      await tester.pumpAndSettle();

      expect(find.byType(IncomingCallPopup), findsNothing);
      expect(CallNotificationService.isIncomingDialogVisibleForTest, isFalse);
    });

    testWidgets('callEnding_dismissesIncomingPopup_byCallId', (tester) async {
      await _pumpHost(tester);
      await _showIncomingPopup(tester);

      expect(find.byType(IncomingCallPopup), findsOneWidget);

      CallNotificationService.processNotificationMessageForTest({
        'type': 'call-ending',
        'callId': 'call-dismiss-test',
        'endedBy': '2',
        'status': 'processing',
      });
      await tester.pumpAndSettle();

      expect(find.byType(IncomingCallPopup), findsNothing);
      expect(CallNotificationService.isIncomingDialogVisibleForTest, isFalse);
    });

    testWidgets('callEnded_dismissesWhenIncomingCallIdClearedButDialogVisible',
        (tester) async {
      await _pumpHost(tester);

      CallNotificationService.processNotificationMessageForTest(
          _incomingCallPayload);
      await tester.pump();
      CallNotificationService.clearIncomingCallIdForTest();
      expect(find.byType(IncomingCallPopup), findsOneWidget);
      expect(CallNotificationService.isIncomingDialogVisibleForTest, isTrue);

      CallNotificationService.processNotificationMessageForTest({
        'type': 'call-ended',
        'callId': 'call-dismiss-test',
      });
      await tester.pumpAndSettle();

      expect(find.byType(IncomingCallPopup), findsNothing);
    });

    testWidgets('callEnded_doesNotDismissPopupForDifferentCallId',
        (tester) async {
      await _pumpHost(tester);
      await _showIncomingPopup(tester);

      CallNotificationService.processNotificationMessageForTest({
        'type': 'call-ended',
        'callId': 'other-call-id',
      });
      await tester.pump();

      expect(find.byType(IncomingCallPopup), findsOneWidget);
    });
  });

  // ─── Connection lifecycle (API Gateway drops sockets) ────────────────────
  //
  // Sockets come from an in-memory FakeWebSocketChannel through the
  // connectChannel seam, and the JWT from mocked secure storage, so no network
  // or platform channel is used. testWidgets' fake clock drives the reconnect
  // backoff (first retry after 1s).
  group('CallNotificationService reconnect', () {
    late List<FakeWebSocketChannel> sockets;
    late List<String?> authReplies;

    setUp(() {
      final expiry = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
      FlutterSecureStorage.setMockInitialValues({
        'jwt_token': 'test-jwt',
        'token_expiry': '$expiry',
      });
      sockets = [];
      // Reply for the n-th socket opened; later sockets reuse the last reply.
      authReplies = ['authentication-success'];
      CallNotificationService.connectChannel = (_) {
        final reply =
            authReplies[sockets.length.clamp(0, authReplies.length - 1)];
        final socket = FakeWebSocketChannel(authReply: reply);
        sockets.add(socket);
        return socket;
      };
    });

    tearDown(() {
      CallNotificationService.connectChannel = WebSocketChannel.connect;
    });

    Future<bool> connect(WidgetTester tester) async {
      late BuildContext hostContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              hostContext = context;
              return const SizedBox();
            },
          ),
        ),
      );
      return CallNotificationService.initialize(
        userId: '42',
        userRole: 'CAREGIVER',
        context: hostContext,
      );
    }

    testWidgets('authenticates with the stored JWT', (tester) async {
      expect(await connect(tester), isTrue);

      expect(CallNotificationService.isConnected, isTrue);
      expect(sockets.single.sentOfType('authenticate').single['token'],
          'test-jwt');
      expect(sockets.single.sentOfType('join-user-room'), hasLength(1));
    });

    testWidgets('a dropped socket reconnects and re-authenticates',
        (tester) async {
      // Arrange
      await connect(tester);

      // Act: the server (API Gateway) closes the socket
      sockets.first.serverClose();
      await tester.pump();
      final connectedWhileDown = CallNotificationService.isConnected;
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      // Assert: down until the 1s backoff, then a new authenticated socket
      expect(connectedWhileDown, isFalse);
      expect(sockets, hasLength(2));
      expect(sockets.last.sentOfType('authenticate'), hasLength(1));
      expect(CallNotificationService.isConnected, isTrue);
    });

    testWidgets('a reconnect that cannot authenticate retries with backoff',
        (tester) async {
      // Arrange: the second socket gets no auth reply, the third succeeds
      authReplies = ['authentication-success', null, 'authentication-success'];
      await connect(tester);

      // Act: drop, wait out the 8s auth timeout on socket 2, then the 2s backoff
      sockets.first.serverClose();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 8));
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();

      // Assert
      expect(sockets, hasLength(3));
      expect(sockets[1].closedByClient, isTrue);
      expect(CallNotificationService.isConnected, isTrue);
    });

    testWidgets('a rejected token stops reconnecting', (tester) async {
      // Arrange: the backend refuses the token on reconnect
      authReplies = ['authentication-success', 'authentication-failed'];
      await connect(tester);

      // Act
      sockets.first.serverClose();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(minutes: 5));

      // Assert: one failed retry, then the service gives up (user must re-login)
      expect(sockets, hasLength(2));
      expect(CallNotificationService.isConnected, isFalse);
    });

    testWidgets('dispose closes the socket and does not reconnect',
        (tester) async {
      await connect(tester);

      CallNotificationService.dispose();
      sockets.first.serverClose();
      await tester.pump(const Duration(minutes: 5));

      expect(sockets.single.closedByClient, isTrue);
      expect(sockets, hasLength(1));
    });

    testWidgets('a reconnect that throws schedules another attempt',
        (tester) async {
      // Arrange: opening the second socket throws (e.g. network down)
      await connect(tester);
      final working = CallNotificationService.connectChannel;
      var attempts = 0;
      CallNotificationService.connectChannel = (uri) {
        attempts++;
        if (attempts == 1) throw StateError('network down');
        return working(uri);
      };

      // Act: drop, fail at 1s, retry at +2s
      sockets.first.serverClose();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();

      // Assert
      expect(attempts, 2);
      expect(CallNotificationService.isConnected, isTrue);
    });
  });
}
