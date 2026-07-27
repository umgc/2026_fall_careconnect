// Tests for UsabilityTracker + UsabilityTapCounter
// (lib/features/telemetry/usability_tracker.dart)
//
// Verifies the global tap counter, task bracketing / tap-delta math, the
// Easy/Medium/Hard difficulty rubric, and that the wrapper widget counts
// pointer-downs. Telemetry is opted out so endTask's fire-and-forget
// usability_task_complete event short-circuits before any network call.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/features/telemetry/usability_tracker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Opt out so Telemetry.event() returns early (no backend call).
    SharedPreferences.setMockInitialValues({'telemetry_opted_out': true});
    UsabilityTracker.debugReset();
  });

  group('UsabilityTracker - counting', () {
    test('registerTap increments the global tap count', () {
      expect(UsabilityTracker.globalTaps, 0);
      UsabilityTracker.registerTap();
      UsabilityTracker.registerTap();
      expect(UsabilityTracker.globalTaps, 2);
    });

    test('endTask returns null when no task was started', () {
      expect(UsabilityTracker.endTask(), isNull);
      expect(UsabilityTracker.isTracking, isFalse);
    });

    test('measures taps taken between startTask and endTask', () {
      UsabilityTracker.registerTap(); // noise before the task
      UsabilityTracker.startTask('evv_checkin', optimalTaps: 4);
      expect(UsabilityTracker.isTracking, isTrue);

      for (var i = 0; i < 5; i++) {
        UsabilityTracker.registerTap();
      }
      final result = UsabilityTracker.endTask();

      expect(result, isNotNull);
      expect(result!.task, 'evv_checkin');
      expect(result.taps, 5); // only taps during the task, not the earlier one
      expect(result.optimalTaps, 4);
      expect(result.success, isTrue);
      expect(UsabilityTracker.isTracking, isFalse);
    });

    test('cancelTask discards the in-progress task without a result', () {
      UsabilityTracker.startTask('schedule_visit');
      UsabilityTracker.registerTap();
      UsabilityTracker.cancelTask();
      expect(UsabilityTracker.isTracking, isFalse);
      expect(UsabilityTracker.endTask(), isNull);
    });

    test('a second startTask replaces the in-progress task', () {
      UsabilityTracker.startTask('task_a');
      UsabilityTracker.registerTap();
      UsabilityTracker.startTask('task_b', optimalTaps: 2); // replaces task_a
      UsabilityTracker.registerTap();
      UsabilityTracker.registerTap();
      final result = UsabilityTracker.endTask();
      expect(result!.task, 'task_b');
      expect(result.taps, 2);
    });
  });

  group('UsabilityTaskResult - difficulty rubric', () {
    UsabilityTaskResult r(int taps, {int? optimal, bool success = true}) =>
        UsabilityTaskResult(
            task: 't',
            taps: taps,
            durationMs: 1000,
            success: success,
            optimalTaps: optimal);

    test('Easy when taps are within optimal + 1', () {
      expect(r(4, optimal: 4).difficulty, TaskDifficulty.easy);
      expect(r(5, optimal: 4).difficulty, TaskDifficulty.easy);
    });

    test('Medium when taps are optimal + 2 to + 4', () {
      expect(r(6, optimal: 4).difficulty, TaskDifficulty.medium);
      expect(r(8, optimal: 4).difficulty, TaskDifficulty.medium);
    });

    test('Hard when taps exceed optimal + 4', () {
      expect(r(9, optimal: 4).difficulty, TaskDifficulty.hard);
    });

    test('Hard when the task failed, regardless of taps', () {
      expect(r(4, optimal: 4, success: false).difficulty, TaskDifficulty.hard);
    });

    test('Unknown when no optimal tap count is provided', () {
      expect(r(7).difficulty, TaskDifficulty.unknown);
    });

    test('toEventProps carries the primitive metrics and difficulty name', () {
      final props = r(6, optimal: 4).toEventProps();
      expect(props['task'], 't');
      expect(props['taps'], 6);
      expect(props['optimal_taps'], 4);
      expect(props['success'], true);
      expect(props['difficulty'], 'medium');
    });
  });

  group('UsabilityTapCounter widget', () {
    testWidgets('counts each pointer-down as a tap', (tester) async {
      await tester.pumpWidget(
        UsabilityTapCounter(
          child: const MaterialApp(
            home: Scaffold(body: Center(child: Text('tap target'))),
          ),
        ),
      );

      expect(UsabilityTracker.globalTaps, 0);
      await tester.tap(find.text('tap target'));
      await tester.tap(find.text('tap target'));
      expect(UsabilityTracker.globalTaps, 2);
    });
  });
}
