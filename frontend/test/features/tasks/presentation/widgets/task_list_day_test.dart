import 'package:calendar_view/calendar_view.dart';
import 'package:care_connect_app/features/tasks/models/task_model.dart';
import 'package:care_connect_app/features/tasks/presentation/widgets/task_list_day.dart';
import 'package:care_connect_app/features/tasks/utils/task_type_manager.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrapWithProviders(Widget child) {
  return ChangeNotifierProvider<TaskTypeManager>(
    create: (_) => TaskTypeManager()
      ..addTaskType("general", Colors.blue)
      ..addTaskType("exercise", Colors.green),
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

/// Helper: creates a CalendarEventData for a given Task
CalendarEventData<Task> _eventForTask(Task task) {
  return CalendarEventData<Task>(
    date: task.date,
    event: task,
    title: task.name,
  );
}

// ── Helpers from features/tasks/widgets/task_list_day_test.dart (merged) ──

final _date = DateTime(2025, 6, 15);

Task _makeTask({
  String name = 'Test Task',
  bool isComplete = false,
  int? patientId,
  TimeOfDay? time,
}) =>
    Task(
      id: 1,
      name: name,
      description: '',
      date: _date,
      isComplete: isComplete,
      taskType: 'medication',
      assignedPatientId: patientId,
      timeOfDay: time,
    );

CalendarEventData<Task> _toEvent(Task task) => CalendarEventData<Task>(
      title: task.name,
      date: _date,
      event: task,
    );

Widget _wrap(Widget child) {
  final manager = TaskTypeManager();
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: ChangeNotifierProvider<TaskTypeManager>.value(
      value: manager,
      child: Scaffold(body: child),
    ),
  );
}

Future<void> _noOp(int id, bool complete) async {}

void main() {
  group('TaskListDay Widget Tests', () {
    testWidgets('renders "No tasks for this day" when empty', (tester) async {
      await tester.pumpWidget(
        _wrapWithProviders(
          TaskListDay(
            events: const [],
            patientNames: const {},
            onEdit: (_) {},
            onDelete: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No tasks for this day'), findsOneWidget);
    });

    testWidgets('renders task details correctly', (tester) async {
      final today = DateTime.now();

      final task = Task(
        id: 1,
        name: 'Morning Exercise',
        description: 'Stretch routine',
        date: today,
        timeOfDay: const TimeOfDay(hour: 8, minute: 0),
        assignedPatientId: 1,
        isComplete: false,
        taskType: 'exercise',
      );

      await tester.pumpWidget(
        _wrapWithProviders(
          TaskListDay(
            events: [_eventForTask(task)],
            patientNames: const {1: 'Alice'},
            onEdit: (_) {},
            onDelete: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Morning Exercise'), findsOneWidget);
      expect(find.textContaining('Alice'), findsOneWidget);
      expect(find.text('Mark as Complete'), findsOneWidget);
    });

    testWidgets('edit and delete buttons trigger callbacks', (tester) async {
      bool editCalled = false;
      bool deleteCalled = false;

      final task = Task(
        id: 2,
        name: 'Check BP',
        description: '',
        date: DateTime.now(),
        timeOfDay: const TimeOfDay(hour: 9, minute: 0),
        assignedPatientId: 3,
        isComplete: false,
        taskType: 'general',
      );

      await tester.pumpWidget(
        _wrapWithProviders(
          TaskListDay(
            events: [_eventForTask(task)],
            patientNames: const {3: 'Bob'},
            onEdit: (_) => editCalled = true,
            onDelete: (_) => deleteCalled = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.edit));
      await tester.pumpAndSettle();
      expect(editCalled, isTrue);

      await tester.tap(find.byIcon(Icons.delete));
      await tester.pumpAndSettle();
      expect(deleteCalled, isTrue);
    });

    testWidgets('Mark as Complete toggles label and calls updateCompletion', (
      tester,
    ) async {
      final today = DateTime.now();

      final task = Task(
        id: 99,
        name: 'Walk',
        description: '',
        date: today,
        timeOfDay: const TimeOfDay(hour: 7, minute: 0),
        assignedPatientId: 5,
        isComplete: false,
        taskType: 'exercise',
      );

      final calls = <Map<String, dynamic>>[];

      await tester.pumpWidget(
        _wrapWithProviders(
          TaskListDay(
            events: [_eventForTask(task)],
            patientNames: const {5: 'Pat'},
            onEdit: (_) {},
            onDelete: (_) {},
            updateCompletion: (id, complete) async {
              calls.add({'id': id, 'complete': complete});
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap the "Mark as Complete" button
      final labelFinder = find.text('Mark as Complete');
      final buttonFinder = find.ancestor(
        of: labelFinder,
        matching: find.byWidgetPredicate(
          (w) =>
              w is OutlinedButton ||
              w.runtimeType.toString().contains('OutlinedButton'),
        ),
      );

      // Relaxed matcher: allow at least one button
      expect(buttonFinder, findsAtLeastNWidgets(1));

      final targetButton = buttonFinder.first;
      await tester.ensureVisible(targetButton);
      await tester.tap(targetButton, warnIfMissed: false);
      await tester.pumpAndSettle(const Duration(milliseconds: 400));

      // Expect UI updated
      expect(find.text('Completed'), findsWidgets);

      // Expect injected callback was called
      expect(
        calls.isNotEmpty,
        isTrue,
        reason: 'Expected updateCompletion to be called at least once',
      );
      expect(calls.first['id'], equals(99));
      expect(calls.first['complete'], isTrue);
    });

    testWidgets(
      'Failed API call rolls back completion status and shows SnackBar',
      (tester) async {
        final today = DateTime.now();

        final task = Task(
          id: 42,
          name: 'Take meds',
          description: '',
          date: today,
          timeOfDay: const TimeOfDay(hour: 10, minute: 30),
          assignedPatientId: 10,
          isComplete: false,
          taskType: 'general',
        );

        bool threw = false;

        await tester.pumpWidget(
          _wrapWithProviders(
            TaskListDay(
              events: [_eventForTask(task)],
              patientNames: const {10: 'Maria'},
              onEdit: (_) {},
              onDelete: (_) {},
              updateCompletion: (id, complete) async {
                // Simulate API failure
                threw = true;
                throw Exception("Simulated failure");
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        final labelFinder = find.text('Mark as Complete');
        final buttonFinder = find.ancestor(
          of: labelFinder,
          matching: find.byWidgetPredicate(
            (w) =>
                w is OutlinedButton ||
                w.runtimeType.toString().contains('OutlinedButton'),
          ),
        );

        expect(buttonFinder, findsAtLeastNWidgets(1));
        await tester.tap(buttonFinder.first, warnIfMissed: false);
        await tester.pumpAndSettle(const Duration(milliseconds: 400));

        // Should have attempted update and caught error
        expect(threw, isTrue);

        // Check that SnackBar appears
        expect(find.textContaining('Failed to update task'), findsOneWidget);

        // UI should have reverted back
        expect(find.text('Mark as Complete'), findsWidgets);
      },
    );
  });

  // Cases merged from features/tasks/widgets/task_list_day_test.dart.
  group('merged from features/tasks/widgets/task_list_day_test.dart', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    group('TaskListDay – empty events', () {
      testWidgets('shows "No tasks for this day" when events is empty',
          (tester) async {
        // Empty list must render the placeholder text.
        await tester.pumpWidget(_wrap(TaskListDay(
          events: [],
          patientNames: {},
          onEdit: (_) {},
          onDelete: (_) {},
          updateCompletion: _noOp,
        )));
        await tester.pump();
        expect(find.text('No tasks for this day'), findsOneWidget);
      });

      testWidgets('does NOT show ListView when events is empty',
          (tester) async {
        // No ListView should be built for empty events.
        await tester.pumpWidget(_wrap(TaskListDay(
          events: [],
          patientNames: {},
          onEdit: (_) {},
          onDelete: (_) {},
          updateCompletion: _noOp,
        )));
        await tester.pump();
        expect(find.byType(ListView), findsNothing);
      });
    });

    group('TaskListDay – with events', () {
      testWidgets('renders without crashing', (tester) async {
        final task = _makeTask();
        await tester.pumpWidget(_wrap(TaskListDay(
          events: [_toEvent(task)],
          patientNames: {},
          onEdit: (_) {},
          onDelete: (_) {},
          updateCompletion: _noOp,
        )));
        await tester.pump();
        expect(find.byType(TaskListDay), findsOneWidget);
      });

      testWidgets('shows task name in the list', (tester) async {
        final task = _makeTask(name: 'Morning Medication');
        await tester.pumpWidget(_wrap(TaskListDay(
          events: [_toEvent(task)],
          patientNames: {},
          onEdit: (_) {},
          onDelete: (_) {},
          updateCompletion: _noOp,
        )));
        await tester.pump();
        expect(find.text('Morning Medication'), findsOneWidget);
      });

      testWidgets('shows "All day" when task has no time', (tester) async {
        final task = _makeTask();
        await tester.pumpWidget(_wrap(TaskListDay(
          events: [_toEvent(task)],
          patientNames: {},
          onEdit: (_) {},
          onDelete: (_) {},
          updateCompletion: _noOp,
        )));
        await tester.pump();
        expect(find.text('All day'), findsOneWidget);
      });

      testWidgets('shows edit and delete IconButtons', (tester) async {
        final task = _makeTask();
        await tester.pumpWidget(_wrap(TaskListDay(
          events: [_toEvent(task)],
          patientNames: {},
          onEdit: (_) {},
          onDelete: (_) {},
          updateCompletion: _noOp,
        )));
        await tester.pump();
        expect(find.byIcon(Icons.edit), findsOneWidget);
        expect(find.byIcon(Icons.delete), findsOneWidget);
      });

      testWidgets('shows "Mark as Complete" button for incomplete task',
          (tester) async {
        final task = _makeTask(isComplete: false);
        await tester.pumpWidget(_wrap(TaskListDay(
          events: [_toEvent(task)],
          patientNames: {},
          onEdit: (_) {},
          onDelete: (_) {},
          updateCompletion: _noOp,
        )));
        await tester.pump();
        expect(find.text('Mark as Complete'), findsOneWidget);
      });

      testWidgets('shows "Completed" button for complete task', (tester) async {
        final task = _makeTask(isComplete: true);
        await tester.pumpWidget(_wrap(TaskListDay(
          events: [_toEvent(task)],
          patientNames: {},
          onEdit: (_) {},
          onDelete: (_) {},
          updateCompletion: _noOp,
        )));
        await tester.pump();
        expect(find.text('Completed'), findsOneWidget);
      });

      testWidgets('invokes onEdit callback when edit button tapped',
          (tester) async {
        Task? editedTask;
        final task = _makeTask(name: 'Edit Me');
        await tester.pumpWidget(_wrap(TaskListDay(
          events: [_toEvent(task)],
          patientNames: {},
          onEdit: (t) => editedTask = t,
          onDelete: (_) {},
          updateCompletion: _noOp,
        )));
        await tester.pump();
        await tester.tap(find.byIcon(Icons.edit));
        expect(editedTask?.name, 'Edit Me');
      });

      testWidgets('invokes onDelete callback when delete button tapped',
          (tester) async {
        Task? deletedTask;
        final task = _makeTask(name: 'Delete Me');
        await tester.pumpWidget(_wrap(TaskListDay(
          events: [_toEvent(task)],
          patientNames: {},
          onEdit: (_) {},
          onDelete: (t) => deletedTask = t,
          updateCompletion: _noOp,
        )));
        await tester.pump();
        await tester.tap(find.byIcon(Icons.delete));
        expect(deletedTask?.name, 'Delete Me');
      });

      testWidgets('renders multiple tasks', (tester) async {
        final t1 = _makeTask(name: 'Alpha Task');
        final t2 = _makeTask(name: 'Beta Task');
        await tester.pumpWidget(_wrap(TaskListDay(
          events: [_toEvent(t1), _toEvent(t2)],
          patientNames: {},
          onEdit: (_) {},
          onDelete: (_) {},
          updateCompletion: _noOp,
        )));
        await tester.pump();
        expect(find.text('Alpha Task'), findsOneWidget);
        expect(find.text('Beta Task'), findsOneWidget);
      });

      testWidgets('shows assigned patient name when patientId matches',
          (tester) async {
        final task = _makeTask(patientId: 42);
        await tester.pumpWidget(_wrap(TaskListDay(
          events: [_toEvent(task)],
          patientNames: {42: 'Alice'},
          onEdit: (_) {},
          onDelete: (_) {},
          updateCompletion: _noOp,
        )));
        await tester.pump();
        expect(find.textContaining('Alice'), findsOneWidget);
      });
    });
  });
}
