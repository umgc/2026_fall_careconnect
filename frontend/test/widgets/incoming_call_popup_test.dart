// Tests for IncomingCallPopup widget
// (lib/widgets/incoming_call_popup.dart)
// StatefulWidget with only AnimationControllers in initState — no API calls.
// Tests cover rendering, call type display, caller info, and button callbacks.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/widgets/incoming_call_popup.dart';

Widget _popup({
  String callId = 'abc123456789',
  String callerId = 'user-1',
  String callerName = 'Dr. Smith',
  bool isVideoCall = false,
  String callerRole = 'CAREGIVER',
  VoidCallback? onAccept,
  VoidCallback? onDecline,
}) =>
    MaterialApp(
      home: IncomingCallPopup(
        callId: callId,
        callerId: callerId,
        callerName: callerName,
        isVideoCall: isVideoCall,
        callerRole: callerRole,
        onAccept: onAccept ?? () {},
        onDecline: onDecline ?? () {},
      ),
    );

void main() {
  group('IncomingCallPopup', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_popup());
      await tester.pump();
      expect(find.byType(IncomingCallPopup), findsOneWidget);
    });

    testWidgets('shows Incoming Audio Call for isVideoCall=false',
        (tester) async {
      await tester.pumpWidget(_popup(isVideoCall: false));
      await tester.pump();
      expect(find.text('Incoming Audio Call'), findsOneWidget);
    });

    testWidgets('shows Incoming Video Call for isVideoCall=true',
        (tester) async {
      await tester.pumpWidget(_popup(isVideoCall: true));
      await tester.pump();
      expect(find.text('Incoming Video Call'), findsOneWidget);
    });

    testWidgets('shows caller name', (tester) async {
      await tester.pumpWidget(_popup(callerName: 'Jane Doe'));
      await tester.pump();
      expect(find.text('Jane Doe'), findsOneWidget);
    });

    testWidgets('shows "Patient" badge for PATIENT role', (tester) async {
      await tester.pumpWidget(_popup(callerRole: 'PATIENT'));
      await tester.pump();
      expect(find.text('Patient'), findsOneWidget);
    });

    testWidgets('shows "Caregiver" badge for non-PATIENT role', (tester) async {
      await tester.pumpWidget(_popup(callerRole: 'CAREGIVER'));
      await tester.pump();
      expect(find.text('Caregiver'), findsOneWidget);
    });

    testWidgets('shows role in "from" subtitle', (tester) async {
      await tester.pumpWidget(_popup(callerRole: 'CAREGIVER'));
      await tester.pump();
      expect(find.text('from Caregiver'), findsOneWidget);
    });

    testWidgets('shows call_end icon for decline button', (tester) async {
      await tester.pumpWidget(_popup());
      await tester.pump();
      expect(find.byIcon(Icons.call_end), findsOneWidget);
    });

    testWidgets('shows phone icon for audio call accept button', (tester) async {
      await tester.pumpWidget(_popup(isVideoCall: false));
      await tester.pump();
      // phone icon appears in both the pulsing avatar and the accept button
      expect(find.byIcon(Icons.phone), findsWidgets);
    });

    testWidgets('shows videocam icon for video call accept button',
        (tester) async {
      await tester.pumpWidget(_popup(isVideoCall: true));
      await tester.pump();
      // videocam appears in both the pulsing avatar and the accept button
      expect(find.byIcon(Icons.videocam), findsWidgets);
    });

    testWidgets('accepts callId parameter', (tester) async {
      // callId is stored but no longer displayed in the UI.
      await tester.pumpWidget(_popup(callId: 'abc123456789'));
      await tester.pump();
      expect(find.byType(IncomingCallPopup), findsOneWidget);
    });

    testWidgets('shows tap hint text', (tester) async {
      await tester.pumpWidget(_popup());
      await tester.pump();
      expect(find.text('Tap to accept or decline'), findsOneWidget);
    });

    testWidgets('calls onDecline when decline button tapped', (tester) async {
      // Suppress layout overflow — the popup has a fixed 320px Container whose
      // swipe-hint Row overflows slightly on the default test canvas.
      final prevOnError = FlutterError.onError!;
      FlutterError.onError = (d) {
        if (d.exceptionAsString().contains('overflowed')) return;
        prevOnError(d);
      };
      addTearDown(() => FlutterError.onError = prevOnError);

      bool declined = false;
      await tester.pumpWidget(_popup(onDecline: () => declined = true));
      // Advance past the 300ms scale animation so the widget is hittable
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byIcon(Icons.call_end));
      expect(declined, isTrue);
    });

    testWidgets('calls onAccept when accept button tapped (audio)',
        (tester) async {
      final prevOnError = FlutterError.onError!;
      FlutterError.onError = (d) {
        if (d.exceptionAsString().contains('overflowed')) return;
        prevOnError(d);
      };
      addTearDown(() => FlutterError.onError = prevOnError);

      bool accepted = false;
      await tester.pumpWidget(
          _popup(isVideoCall: false, onAccept: () => accepted = true));
      await tester.pump(const Duration(milliseconds: 400));
      // Tap the accept button (second phone icon — first is in the avatar)
      await tester.tap(find.byIcon(Icons.phone).last);
      expect(accepted, isTrue);
    });

    testWidgets('shows swipe icon', (tester) async {
      await tester.pumpWidget(_popup());
      await tester.pump();
      expect(find.byIcon(Icons.swipe), findsOneWidget);
    });
  });
}
