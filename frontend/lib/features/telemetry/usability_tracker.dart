import 'package:flutter/widgets.dart';

import 'telemetry.dart';

/// Difficulty rating for a completed task, derived from tap efficiency and
/// success (see the Team B usability rubric).
enum TaskDifficulty { easy, medium, hard, unknown }

/// The result of a measured usability task: how many taps it took, how long it
/// took, whether it succeeded, and the derived [difficulty].
class UsabilityTaskResult {
  const UsabilityTaskResult({
    required this.task,
    required this.taps,
    required this.durationMs,
    required this.success,
    this.optimalTaps,
  });

  final String task;
  final int taps;
  final int durationMs;
  final bool success;

  /// The designed minimum number of taps for this task, if known. When null the
  /// difficulty cannot be computed from efficiency and is reported as unknown.
  final int? optimalTaps;

  /// Maps tap-efficiency and success onto the Team B Easy / Medium / Hard rubric:
  ///  - Hard    : task failed, or taps > optimal + 4
  ///  - Medium  : optimal + 2 <= taps <= optimal + 4
  ///  - Easy    : taps <= optimal + 1
  ///  - Unknown : optimalTaps not provided
  TaskDifficulty get difficulty {
    if (!success) return TaskDifficulty.hard;
    final optimal = optimalTaps;
    if (optimal == null) return TaskDifficulty.unknown;
    final over = taps - optimal;
    if (over <= 1) return TaskDifficulty.easy;
    if (over <= 4) return TaskDifficulty.medium;
    return TaskDifficulty.hard;
  }

  Map<String, Object?> toEventProps() => {
        'task': task,
        'taps': taps,
        'duration_ms': durationMs,
        'success': success,
        if (optimalTaps != null) 'optimal_taps': optimalTaps,
        'difficulty': difficulty.name,
      };
}

/// Lightweight, app-wide usability instrument for measuring **taps per task**
/// (efficiency), the core input to the Milestone 4 usability report.
///
/// Usage:
///   1. Wrap the app once in a [UsabilityTapCounter] so every pointer-down is
///      counted globally (no per-screen changes needed).
///   2. Bracket a task: `UsabilityTracker.startTask('evv_checkin', optimalTaps: 4)`
///      then `UsabilityTracker.endTask()` (or `endTask(success: false)`).
///
/// [endTask] returns the computed [UsabilityTaskResult] (for report generation)
/// and emits a sanitized `usability_task_complete` telemetry event.
class UsabilityTracker {
  UsabilityTracker._();

  static int _globalTaps = 0;

  static String? _currentTask;
  static int _startTaps = 0;
  static int? _optimalTaps;
  static DateTime? _startTime;

  /// Current global tap count since app start. Exposed for tests/diagnostics.
  static int get globalTaps => _globalTaps;

  /// True while a task is being measured.
  static bool get isTracking => _currentTask != null;

  /// Called by [UsabilityTapCounter] on every pointer-down.
  static void registerTap() => _globalTaps++;

  /// Begin measuring a task. A second call replaces any in-progress task.
  static void startTask(String task, {int? optimalTaps}) {
    _currentTask = task;
    _startTaps = _globalTaps;
    _optimalTaps = optimalTaps;
    _startTime = DateTime.now();
  }

  /// Abandon the in-progress task without emitting anything.
  static void cancelTask() {
    _currentTask = null;
    _startTime = null;
    _optimalTaps = null;
  }

  /// Finish the in-progress task. Returns null if no task was started.
  /// Emits a `usability_task_complete` telemetry event and returns the result.
  static UsabilityTaskResult? endTask({bool success = true}) {
    final task = _currentTask;
    final start = _startTime;
    if (task == null || start == null) return null;

    final result = UsabilityTaskResult(
      task: task,
      taps: _globalTaps - _startTaps,
      durationMs: DateTime.now().difference(start).inMilliseconds,
      success: success,
      optimalTaps: _optimalTaps,
    );

    _currentTask = null;
    _startTime = null;
    _optimalTaps = null;

    // Fire-and-forget; guardrails whitelist + sanitize the event.
    Telemetry.event('usability_task_complete', result.toEventProps());
    return result;
  }

  /// Test-only reset of all counters and in-progress state.
  @visibleForTesting
  static void debugReset() {
    _globalTaps = 0;
    _currentTask = null;
    _startTaps = 0;
    _optimalTaps = null;
    _startTime = null;
  }
}

/// Wraps a subtree (typically the whole app) and counts every pointer-down as
/// one "tap" for [UsabilityTracker]. Translucent so it never intercepts input.
class UsabilityTapCounter extends StatelessWidget {
  const UsabilityTapCounter({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => UsabilityTracker.registerTap(),
      child: child,
    );
  }
}
