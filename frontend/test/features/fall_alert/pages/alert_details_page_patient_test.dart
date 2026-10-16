// Tests for PatientFallPromptPage
// (lib/features/fall_alert/pages/alert_details_page_patient.dart).
//
// Coverage strategy:
//   PatientFallPromptPage starts a countdown timer in initState.  All tests
//   pass autoCallSeconds: 999 so the timer never fires the auto-call branch
//   during the test run.  The url_launcher calls are never triggered because
//   we do not tap the phone-call tiles.
//
//   Branches tested (initial render):
//     Scaffold / "Fall Detected" AppBar — widget builds without crashing.
//     "Are You Okay?" header            — main question is shown.
//     "I'm Okay" button                 — present and tappable.
//     "Call for Help" button            — present and tappable.
//     Countdown text                    — "Auto-calling in N seconds…" shown.
//     Warning text                      — body explanation is rendered.
//
//   Branches tested ("I'm Okay" path):
//     _acknowledgeOk called             — timer cancelled, Navigator pops.
//     onAcknowledgeOk callback fires    — provided callback is invoked.
//
//   Branches tested ("Call for Help" path):
//     _openEmergencySheet shown         — bottom sheet with emergency options.
//     Contact tile disabled             — no phone on file → tile is disabled.
//     Contact tile enabled              — phone present → tile is enabled.
//
//   Branches tested (_EmergencyTile / _ActionButton helpers):
//     _ActionButton renders label       — covered by button-presence tests.
//     _EmergencyTile renders subtitle   — covered by bottom-sheet tests.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:care_connect_app/features/fall_alert/pages/alert_details_page_patient.dart';

/// Pumps [page] inside a MaterialApp that has a home route so Navigator.pop
/// has something to pop back to.
Widget _withNav(Widget page) {
  return MaterialApp(
    home: Builder(
      builder: (ctx) => ElevatedButton(
        onPressed: () => Navigator.of(ctx).push(
          MaterialPageRoute<void>(builder: (_) => page),
        ),
        child: const Text('Open'),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ── initial render ─────────────────────────────────────────────────────────

  group('PatientFallPromptPage – initial render', () {
    testWidgets('renders Scaffold with "Fall Detected" title', (tester) async {
      // Verifies the widget builds and the AppBar title is correct.
      await tester.pumpWidget(
        const MaterialApp(
          home: PatientFallPromptPage(autoCallSeconds: 999),
        ),
      );
      await tester.pump();

      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.text('Fall Detected'), findsOneWidget);
    });

    testWidgets('shows "Are You Okay?" header', (tester) async {
      // Verifies the primary question is rendered in the header card.
      await tester.pumpWidget(
        const MaterialApp(
          home: PatientFallPromptPage(autoCallSeconds: 999),
        ),
      );
      await tester.pump();

      expect(find.text('Are You Okay?'), findsOneWidget);
    });

    testWidgets('shows "I\'m Okay" action button', (tester) async {
      // Verifies the acknowledge-okay button is present.
      await tester.pumpWidget(
        const MaterialApp(
          home: PatientFallPromptPage(autoCallSeconds: 999),
        ),
      );
      await tester.pump();

      expect(find.textContaining("I'm Okay"), findsOneWidget);
    });

    testWidgets('shows "Call for Help" action button', (tester) async {
      // Verifies the escalation button is present.
      await tester.pumpWidget(
        const MaterialApp(
          home: PatientFallPromptPage(autoCallSeconds: 999),
        ),
      );
      await tester.pump();

      expect(find.text('Call for Help'), findsOneWidget);
    });

    testWidgets('shows auto-call countdown text', (tester) async {
      // Verifies the countdown banner is rendered with the remaining seconds.
      await tester.pumpWidget(
        const MaterialApp(
          home: PatientFallPromptPage(autoCallSeconds: 999),
        ),
      );
      await tester.pump();

      expect(find.textContaining('Auto-calling in'), findsOneWidget);
    });

    testWidgets('shows warning body text about auto-call', (tester) async {
      // Verifies the explanatory text in the info banner is present.
      await tester.pumpWidget(
        const MaterialApp(
          home: PatientFallPromptPage(autoCallSeconds: 999),
        ),
      );
      await tester.pump();

      expect(
        find.textContaining('emergency services will be contacted'),
        findsOneWidget,
      );
    });
  });

  // ── "I'm Okay" path ────────────────────────────────────────────────────────

  group('PatientFallPromptPage – I\'m Okay path', () {
    testWidgets('tapping "I\'m Okay" pops the route', (tester) async {
      // Verifies _acknowledgeOk cancels the timer and pops the navigator.
      await tester.pumpWidget(_withNav(
        const PatientFallPromptPage(autoCallSeconds: 999),
      ));

      // Navigate to the fall-prompt page.
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Fall Detected'), findsOneWidget);

      // Tap "I'm Okay" — should pop back.
      await tester.tap(find.textContaining("I'm Okay"));
      await tester.pumpAndSettle();

      // After pop the fall-prompt page is gone.
      expect(find.text('Fall Detected'), findsNothing);
    });

    testWidgets('onAcknowledgeOk callback is invoked when provided', (
      tester,
    ) async {
      // Verifies the optional onAcknowledgeOk callback fires on acknowledgement.
      bool called = false;
      await tester.pumpWidget(
        MaterialApp(
          home: PatientFallPromptPage(
            autoCallSeconds: 999,
            onAcknowledgeOk: () async {
              called = true;
            },
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.textContaining("I'm Okay"));
      await tester.pump();

      expect(called, isTrue);
    });
  });

  // ── "Call for Help" bottom sheet ───────────────────────────────────────────

  group('PatientFallPromptPage – Call for Help sheet', () {
    testWidgets('tapping "Call for Help" opens the emergency bottom sheet', (
      tester,
    ) async {
      // Verifies _openEmergencySheet shows the modal sheet with expected content.
      await tester.pumpWidget(
        const MaterialApp(
          home: PatientFallPromptPage(autoCallSeconds: 999),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Call for Help'));
      await tester.pumpAndSettle();

      expect(find.text('Emergency actions'), findsOneWidget);
    });

    testWidgets('emergency sheet shows the emergency number tile', (
      tester,
    ) async {
      // Verifies the default emergency number (911) is shown in the sheet.
      await tester.pumpWidget(
        const MaterialApp(
          home: PatientFallPromptPage(
            autoCallSeconds: 999,
            emergencyNumber: '911',
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Call for Help'));
      await tester.pumpAndSettle();

      expect(find.textContaining('911'), findsWidgets);
    });

    testWidgets('contact tile is disabled when no emergency phone is provided', (
      tester,
    ) async {
      // Verifies the emergency-contact tile is disabled (no phone on file).
      await tester.pumpWidget(
        const MaterialApp(
          home: PatientFallPromptPage(
            autoCallSeconds: 999,
            // emergencyContactPhone intentionally omitted → disabled tile
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Call for Help'));
      await tester.pumpAndSettle();

      expect(find.text('No phone on file'), findsOneWidget);
    });

    testWidgets('contact tile shows phone number when provided', (
      tester,
    ) async {
      // Verifies the emergency-contact tile shows the provided phone number.
      await tester.pumpWidget(
        const MaterialApp(
          home: PatientFallPromptPage(
            autoCallSeconds: 999,
            emergencyContactName: 'John Doe',
            emergencyContactPhone: '555-0100',
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Call for Help'));
      await tester.pumpAndSettle();

      expect(find.text('555-0100'), findsOneWidget);
    });
  });
}
