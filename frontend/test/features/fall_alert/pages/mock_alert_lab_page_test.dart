// Tests for MockAlertLabPage
// (lib/features/fall_alert/pages/mock_alert_lab_page.dart).
//
// Coverage strategy:
//   MockAlertLabPage is a StatefulWidget that listens to a
//   MockFallDetectionService stream and lets the user start/stop periodic
//   alerts or trigger one manually.  All button-state and status-text branches
//   are testable without a live server.
//
//   Branches tested (initial state):
//     Scaffold renders          — widget builds without crashing.
//     Start button enabled      — _running == false → Start is enabled.
//     Stop button disabled      — _running == false → Stop is disabled.
//     Trigger button enabled    — always enabled initially.
//     Status shows "stopped"    — status text reflects _running == false.
//     Empty hint shown          — no alerts yet → _EmptyHint renders.
//
//   Branches tested (after tapping Start):
//     Start button disabled     — _running == true → Start is disabled.
//     Stop button enabled       — _running == true → Stop is enabled.
//     Status shows "running"    — status text reflects _running == true.
//
//   Branches tested (after tapping Stop):
//     Start re-enabled          — _running flips back to false.
//     Status shows "stopped"    — status text returns to stopped.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:care_connect_app/features/fall_alert/pages/mock_alert_lab_page.dart';

// ── notification channel stub ─────────────────────────────────────────────────
// MockFallDetectionService calls NotificationService.showFallAlert() which
// uses the flutter_local_notifications platform channel.  Without a stub the
// call silently succeeds in tests (channels return null by default), but
// bool-returning methods cast null to bool and throw.  The stub below returns
// true for those methods and null for everything else, matching the pattern
// used in notification_service_test.dart.

const _kNotifChannel =
    MethodChannel('dexterous.com/flutter/local_notifications');

void _stubNotifChannel() {
  const boolMethods = {
    'initialize',
    'requestNotificationsPermission',
    'requestExactAlarmsPermission',
    'requestFullScreenIntentPermission',
    'areNotificationsEnabled',
    'canScheduleExactNotifications',
    'requestPermissions',
  };
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_kNotifChannel, (call) async {
    if (boolMethods.contains(call.method)) return true;
    return null;
  });
}

void _clearNotifChannel() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_kNotifChannel, null);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MockAlertLabPage – initial state', () {
    testWidgets('renders Scaffold without crashing', (tester) async {
      // Verifies the widget builds successfully.
      await tester.pumpWidget(
        const MaterialApp(home: MockAlertLabPage()),
      );
      await tester.pump();

      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('Start button is enabled and Stop button is disabled', (
      tester,
    ) async {
      // Verifies the initial button states: Start enabled, Stop disabled.
      await tester.pumpWidget(
        const MaterialApp(home: MockAlertLabPage()),
      );
      await tester.pump();

      // FilledButton for "Start" — enabled when _running == false.
      final startBtn = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Start'),
      );
      expect(startBtn.onPressed, isNotNull);

      // OutlinedButton for "Stop" — disabled when _running == false.
      final stopBtn = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Stop'),
      );
      expect(stopBtn.onPressed, isNull);
    });

    testWidgets('Trigger button is always enabled', (tester) async {
      // Verifies the tonal Trigger button is always available.
      await tester.pumpWidget(
        const MaterialApp(home: MockAlertLabPage()),
      );
      await tester.pump();

      final triggerBtn = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Trigger'),
      );
      expect(triggerBtn.onPressed, isNotNull);
    });

    testWidgets('status text shows "stopped" initially', (tester) async {
      // Verifies the status line reflects _running == false.
      await tester.pumpWidget(
        const MaterialApp(home: MockAlertLabPage()),
      );
      await tester.pump();

      expect(find.textContaining('stopped'), findsOneWidget);
    });

    testWidgets('empty hint is shown when no alerts exist', (tester) async {
      // Verifies the _EmptyHint widget renders before any alert fires.
      await tester.pumpWidget(
        const MaterialApp(home: MockAlertLabPage()),
      );
      await tester.pump();

      expect(find.textContaining('No alerts yet'), findsOneWidget);
    });
  });

  group('MockAlertLabPage – Start/Stop interaction', () {
    testWidgets('tapping Start disables Start and enables Stop', (
      tester,
    ) async {
      // Verifies _startPeriodic sets _running = true and updates button states.
      await tester.pumpWidget(
        const MaterialApp(home: MockAlertLabPage()),
      );
      await tester.pump();

      await tester.tap(find.widgetWithText(FilledButton, 'Start'));
      await tester.pump();

      final startBtn = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Start'),
      );
      expect(startBtn.onPressed, isNull); // disabled

      final stopBtn = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Stop'),
      );
      expect(stopBtn.onPressed, isNotNull); // enabled
    });

    testWidgets('tapping Start changes status text to "running"', (
      tester,
    ) async {
      // Verifies the status line updates when _running flips to true.
      await tester.pumpWidget(
        const MaterialApp(home: MockAlertLabPage()),
      );
      await tester.pump();

      await tester.tap(find.widgetWithText(FilledButton, 'Start'));
      await tester.pump();

      expect(find.textContaining('running'), findsOneWidget);
    });

    testWidgets('tapping Stop re-enables Start and disables Stop', (
      tester,
    ) async {
      // Verifies _stopPeriodic sets _running = false and restores button states.
      await tester.pumpWidget(
        const MaterialApp(home: MockAlertLabPage()),
      );
      await tester.pump();

      // Start first, then stop.
      await tester.tap(find.widgetWithText(FilledButton, 'Start'));
      await tester.pump();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Stop'));
      await tester.pump();

      final startBtn = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Start'),
      );
      expect(startBtn.onPressed, isNotNull); // re-enabled

      final stopBtn = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Stop'),
      );
      expect(stopBtn.onPressed, isNull); // disabled again
    });

    testWidgets('tapping Stop restores status text to "stopped"', (
      tester,
    ) async {
      // Verifies the status line returns to "stopped" after Stop is tapped.
      await tester.pumpWidget(
        const MaterialApp(home: MockAlertLabPage()),
      );
      await tester.pump();

      await tester.tap(find.widgetWithText(FilledButton, 'Start'));
      await tester.pump();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Stop'));
      await tester.pump();

      expect(find.textContaining('stopped'), findsOneWidget);
    });
  });

  // ── Trigger button ────────────────────────────────────────────────────────
  // The Trigger button calls _triggerOnce() which calls
  // MockFallDetectionService.emitNow() → NotificationService.showFallAlert().
  // The notification platform channel is stubbed to avoid cast errors while
  // still exercising _triggerOnce, _AlertTile.build, and the stream listener.

  group('MockAlertLabPage – Trigger interaction', () {
    setUp(_stubNotifChannel);
    tearDown(_clearNotifChannel);

    testWidgets('tapping Trigger shows "Mock fall alert emitted" snack bar', (
      tester,
    ) async {
      // Verifies _triggerOnce fires emitNow and shows the SnackBar on success.
      await tester.pumpWidget(
        const MaterialApp(home: MockAlertLabPage()),
      );
      await tester.pump();

      await tester.tap(find.widgetWithText(FilledButton, 'Trigger'));
      await tester.pump(); // allow microtasks (emitNow future) to complete
      await tester.pump(); // allow setState from stream listener

      expect(find.text('Mock fall alert emitted'), findsOneWidget);
    });

    testWidgets('tapping Trigger adds an alert tile to the list', (
      tester,
    ) async {
      // Verifies the stream listener inserts the emitted alert into _recent
      // and _AlertTile renders (replacing the _EmptyHint).
      await tester.pumpWidget(
        const MaterialApp(home: MockAlertLabPage()),
      );
      await tester.pump();

      // Before trigger: empty hint is shown.
      expect(find.textContaining('No alerts yet'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Trigger'));
      await tester.pump();
      await tester.pump();

      // After trigger: empty hint gone, at least one ListTile is shown.
      expect(find.textContaining('No alerts yet'), findsNothing);
      expect(find.byType(ListTile), findsOneWidget);
    });
  });
}
