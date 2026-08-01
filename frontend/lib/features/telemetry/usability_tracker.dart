import 'package:flutter/widgets.dart';

import 'telemetry.dart';

/// Route-keyed catalog of **designed / optimal** tap counts for the app-wide
/// usability instrument. The router observer (see [TelemetryGoRouterObserver])
/// looks each route up here when it auto-brackets a screen as a task.
///
/// Keys are go_router route patterns matched against `GoRouterState.fullPath`
/// (e.g. `/evv/checkin-location`, `/patient/:id`) so dynamic ids do not
/// fragment the data. Only routes listed here are scored Easy/Medium/Hard;
/// every other route is still measured (taps + duration + a
/// `usability_task_complete` event) but reported as [TaskDifficulty.unknown]
/// until a designed value is added here. Populate these from Team B's
/// designed-path analysis (the same source as the Milestone 4 taps-per-task
/// figures).
const Map<String, int> kUsabilityOptimalTaps = <String, int>{
  // TODO(team-b): set the designed optimal taps per measured flow, e.g.:
  // '/evv/checkin-location': 4,   // EVV check-in (GPS)
  // '/evv/visit-complete':   6,   // Complete visit & submit EVV
  // '/voice':                2,   // Voice command navigation
  // Left empty on purpose: every route is measured regardless; adding an entry
  // here only switches that route from "unknown" to a scored difficulty.
};

/// A multi-screen *flow*: a user goal that spans several routes (e.g. scheduling
/// a visit or filing an incident report). Declared in [kUsabilityFlows] and
/// driven automatically by the router observer — no per-screen wiring. The flow
/// starts when [start] is entered, ends successfully when [end] is reached, and
/// is treated as abandoned (success:false) if navigation leaves the [screens]
/// set before reaching [end].
class UsabilityFlow {
  const UsabilityFlow({
    required this.name,
    required this.start,
    required this.end,
    this.screens = const <String>{},
    this.optimalTaps,
  });

  /// Task key emitted for the whole flow, e.g. `flow_schedule_visit`.
  final String name;

  /// Route pattern that begins the flow.
  final String start;

  /// Route pattern whose arrival marks success.
  final String end;

  /// Route patterns that count as "still inside" the flow. Navigating to a route
  /// outside this set (and not [end]) marks the flow abandoned. Include [start]
  /// and every intermediate screen; [end] is treated as in-flow implicitly.
  final Set<String> screens;

  /// Designed taps for the entire flow, for the Easy/Medium/Hard rubric.
  final int? optimalTaps;
}

/// Multi-screen flows measured end-to-end (see [UsabilityFlow]). Empty by
/// default — the app-wide per-route instrument runs unchanged until a flow is
/// declared here. Populate from Team B's designed-path analysis, e.g.:
///
/// ```dart
/// UsabilityFlow(
///   name: 'flow_schedule_visit',
///   start: '/evv/select-patient',
///   end: '/evv/visit-completed-success',
///   screens: {'/evv/select-patient', '/evv/start-visit',
///             '/evv/visit-progress', '/evv/visit-complete'},
///   optimalTaps: 8,
/// ),
/// ```
const List<UsabilityFlow> kUsabilityFlows = <UsabilityFlow>[];

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
  static bool _flowActive = false;

  /// Current global tap count since app start. Exposed for tests/diagnostics.
  static int get globalTaps => _globalTaps;

  /// True while a task is being measured.
  static bool get isTracking => _currentTask != null;

  /// The task currently being measured, or null when idle.
  static String? get currentTask => _currentTask;

  /// True while a multi-screen [startFlow] is being measured. While a flow is
  /// active the per-route auto-instrument ([switchTask]) is suppressed, so taps
  /// keep accruing to the flow across screen changes.
  static bool get isInFlow => _flowActive;

  /// Called by [UsabilityTapCounter] on every pointer-down.
  static void registerTap() => _globalTaps++;

  /// Begin measuring a task. A second call replaces any in-progress task.
  static void startTask(String task, {int? optimalTaps}) {
    _currentTask = task;
    _startTaps = _globalTaps;
    _optimalTaps = optimalTaps;
    _startTime = DateTime.now();
  }

  /// Convenience for app-wide auto-instrumentation: hand off from the current
  /// task to [task]. Ends the in-progress task first (emitting its
  /// `usability_task_complete` event and returning its result), then starts
  /// measuring [task]. A no-op that returns null when [task] is already the one
  /// being measured, so repeated navigation callbacks for the same route don't
  /// fragment the measurement. Used by the router observer to bracket every
  /// route change as a measured task with no per-screen wiring.
  static UsabilityTaskResult? switchTask(String task, {int? optimalTaps}) {
    if (_flowActive) return null; // a multi-screen flow owns the measurement
    if (_currentTask == task) return null;
    final prior = _currentTask != null ? endTask() : null;
    startTask(task, optimalTaps: optimalTaps);
    return prior;
  }

  /// Begin measuring a multi-screen *flow* — a goal that spans several routes
  /// (e.g. scheduling a visit). Ends any in-progress per-route task first, then
  /// starts measuring [flow] and suppresses per-route auto-switching until
  /// [endFlow] or [cancelFlow], so taps keep accruing to the flow across screen
  /// changes. Call at the flow's entry point, or declare the flow in
  /// [kUsabilityFlows] to have the router drive it automatically.
  static void startFlow(String flow, {int? optimalTaps}) {
    if (_currentTask != null) endTask();
    startTask(flow, optimalTaps: optimalTaps);
    _flowActive = true;
  }

  /// Finish the in-progress flow, emitting its `usability_task_complete` event
  /// with the total taps across every screen in the flow. Returns null if no
  /// flow is active. Pass success:false if the goal was not completed.
  static UsabilityTaskResult? endFlow({bool success = true}) {
    if (!_flowActive) return null;
    _flowActive = false;
    return endTask(success: success);
  }

  /// Abandon the in-progress flow without emitting anything, resuming per-route
  /// auto-tracking on the next navigation.
  static void cancelFlow() {
    if (!_flowActive) return;
    _flowActive = false;
    cancelTask();
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
    _flowActive = false;
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
