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

  group('UsabilityTracker - switchTask / currentTask', () {
    test('currentTask is null when idle and set while tracking', () {
      expect(UsabilityTracker.currentTask, isNull);
      UsabilityTracker.startTask('a');
      expect(UsabilityTracker.currentTask, 'a');
      UsabilityTracker.endTask();
      expect(UsabilityTracker.currentTask, isNull);
    });

    test('switchTask starts measuring when idle and returns null', () {
      final prior = UsabilityTracker.switchTask('screen_a', optimalTaps: 3);
      expect(prior, isNull);
      expect(UsabilityTracker.isTracking, isTrue);
      expect(UsabilityTracker.currentTask, 'screen_a');
    });

    test('switchTask ends the prior task and starts the next with a fresh count',
        () {
      UsabilityTracker.switchTask('screen_a', optimalTaps: 2);
      UsabilityTracker.registerTap();
      UsabilityTracker.registerTap(); // 2 taps on screen_a
      final prior = UsabilityTracker.switchTask('screen_b', optimalTaps: 5);
      expect(prior, isNotNull);
      expect(prior!.task, 'screen_a');
      expect(prior.taps, 2);
      expect(prior.difficulty, TaskDifficulty.easy); // 2 <= optimal(2)+1
      expect(UsabilityTracker.currentTask, 'screen_b');
      // Taps now accrue to screen_b only.
      UsabilityTracker.registerTap();
      final b = UsabilityTracker.endTask();
      expect(b!.task, 'screen_b');
      expect(b.taps, 1);
    });

    test('switchTask to the same task is a no-op and keeps measuring', () {
      UsabilityTracker.switchTask('screen_a');
      UsabilityTracker.registerTap();
      final noop = UsabilityTracker.switchTask('screen_a'); // same route again
      expect(noop, isNull);
      UsabilityTracker.registerTap();
      final res = UsabilityTracker.endTask();
      expect(res!.task, 'screen_a');
      expect(res.taps, 2); // both taps counted; the no-op didn't reset the start
    });
  });

  group('UsabilityTracker - flow mode', () {
    test('startFlow suppresses per-route switchTask so taps span screens', () {
      UsabilityTracker.startFlow('flow_x', optimalTaps: 6);
      expect(UsabilityTracker.isInFlow, isTrue);
      UsabilityTracker.registerTap(); // screen 1
      UsabilityTracker.switchTask('/step2'); // navigation within flow -> no-op
      expect(UsabilityTracker.currentTask, 'flow_x');
      UsabilityTracker.registerTap(); // screen 2
      UsabilityTracker.switchTask('/step3'); // no-op
      UsabilityTracker.registerTap(); // screen 3
      final res = UsabilityTracker.endFlow();
      expect(UsabilityTracker.isInFlow, isFalse);
      expect(res!.task, 'flow_x');
      expect(res.taps, 3); // taps across all three screens
      expect(res.success, isTrue);
      expect(res.difficulty, TaskDifficulty.easy); // 3 <= optimal(6)+1
    });

    test('endFlow(success:false) marks the flow failed', () {
      UsabilityTracker.startFlow('flow_y', optimalTaps: 2);
      UsabilityTracker.registerTap();
      final res = UsabilityTracker.endFlow(success: false);
      expect(res!.success, isFalse);
      expect(res.difficulty, TaskDifficulty.hard); // failure -> hard
    });

    test('cancelFlow discards without a result and resumes auto tracking', () {
      UsabilityTracker.startFlow('flow_z');
      UsabilityTracker.registerTap();
      UsabilityTracker.cancelFlow();
      expect(UsabilityTracker.isInFlow, isFalse);
      // Auto per-route tracking works again once the flow is cancelled.
      final prior = UsabilityTracker.switchTask('/after', optimalTaps: 1);
      expect(prior, isNull);
      expect(UsabilityTracker.currentTask, '/after');
    });

    test('endFlow returns null when no flow is active', () {
      expect(UsabilityTracker.endFlow(), isNull);
      expect(UsabilityTracker.isInFlow, isFalse);
    });
  });
}
