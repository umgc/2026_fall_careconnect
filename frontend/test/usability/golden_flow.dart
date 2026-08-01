// Golden-path usability harness.
//
// Drives a feature flow along its intended *shortest* ("golden") path with the
// real [UsabilityTapCounter] mounted, and returns what the instrument recorded.
// Because [drive] performs only the designed minimal steps, the returned
// `taps` is the **minimum taps required** for that flow — the number to feed
// back in as `optimalTaps` (kUsabilityOptimalTaps / UsabilityFlow.optimalTaps).
//
// This runs headless under `flutter test` (deterministic, CI-friendly). Mock a
// flow's services so its happy path completes offline; each `tester.tap` on a
// control is counted by the root Listener exactly as a real tap would be.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/telemetry/usability_tracker.dart';

/// Measures the golden (minimum) path of a flow.
///
/// - [name]: the flow's task key (e.g. `flow_request_password_reset`).
/// - [app]: the widget tree to pump (a real screen, usually wrapped in a
///   MaterialApp / router / providers, with its services mocked to succeed).
/// - [drive]: performs ONLY the designed minimal taps to complete the flow.
/// - [optimalTaps]: optional expected designed value; when provided the returned
///   result also carries the Easy/Medium/Hard difficulty (here it will normally
///   be Easy, since the golden path is by definition the optimum).
///
/// Returns the [UsabilityTaskResult]; `result.taps` is the minimum tap count.
Future<UsabilityTaskResult> measureGoldenFlow(
  WidgetTester tester, {
  required String name,
  required Widget app,
  required Future<void> Function(WidgetTester tester) drive,
  int? optimalTaps,
}) async {
  UsabilityTracker.debugReset();
  await tester.pumpWidget(UsabilityTapCounter(child: app));
  await tester.pump(const Duration(milliseconds: 300));

  UsabilityTracker.startFlow(name, optimalTaps: optimalTaps);
  await drive(tester);
  final result = UsabilityTracker.endFlow();

  UsabilityTracker.debugReset();
  if (result == null) {
    throw StateError('Flow "$name" produced no result — did drive() end it early?');
  }
  return result;
}
