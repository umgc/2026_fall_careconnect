// Tests for CallNotificationService incoming-popup dismiss behavior (L2d).
// Uses @visibleForTesting hooks — no live WebSocket required.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/services/call_notification_service.dart';
import 'package:care_connect_app/widgets/incoming_call_popup.dart';

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
  CallNotificationService.processNotificationMessageForTest(_incomingCallPayload);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  tearDown(() {
    CallNotificationService.dispose();
  });

  group('CallNotificationService incoming popup dismiss (L2d)', () {
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

    testWidgets('callEnded_dismissesWhenIncomingCallIdClearedButDialogVisible',
        (tester) async {
      await _pumpHost(tester);

      CallNotificationService.processNotificationMessageForTest(_incomingCallPayload);
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
}
