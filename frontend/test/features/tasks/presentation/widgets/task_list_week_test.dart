// Tests for TaskListWeek widget
// (lib/features/tasks/presentation/widgets/task_list_week.dart).
//
// TaskListWeek is structurally identical to TaskListDay but groups tasks
// across a week and adds date info to each subtitle.
// updateCompletion is injectable — tests pass a no-op to avoid API calls.

import 'package:calendar_view/calendar_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:care_connect_app/features/tasks/presentation/widgets/task_list_week.dart';
import 'package:care_connect_app/features/tasks/models/task_model.dart';
import 'package:care_connect_app/features/tasks/utils/task_type_manager.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';

final _date = DateTime(2025, 6, 15);

Task _makeTask({
  String name = 'Test Task',
  bool isComplete = false,
  int? patientId,
  DateTime? date,
}) =>
    Task(
      id: 1,
      name: name,
      description: '',
      date: date ?? _date,
      isComplete: isComplete,
      taskType: 'appointment',
      assignedPatientId: patientId,
    );

CalendarEventData<Task> _toEvent(Task task) => CalendarEventData<Task>(
      title: task.name,
      date: task.date,
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

// ── Helpers from calendar_assistant/task_list_week_test.dart (merged) ──

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

CalendarEventData<Task> _eventForTask(Task t) =>
    CalendarEventData<Task>(date: t.date, event: t, title: t.name);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('TaskListWeek – empty events', () {
    testWidgets('shows "No tasks this week" when events is empty',
        (tester) async {
      await tester.pumpWidget(_wrap(TaskListWeek(
        events: [],
        patientNames: {},
        onEdit: (_) {},
        onDelete: (_) {},
        updateCompletion: _noOp,
      )));
      await tester.pump();
      expect(find.text('No tasks this week'), findsOneWidget);
    });

    testWidgets('does NOT render ListView for empty events', (tester) async {
      await tester.pumpWidget(_wrap(TaskListWeek(
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

  group('TaskListWeek – with events', () {
    testWidgets('renders without crashing', (tester) async {
      final task = _makeTask();
      await tester.pumpWidget(_wrap(TaskListWeek(
        events: [_toEvent(task)],
        patientNames: {},
        onEdit: (_) {},
        onDelete: (_) {},
        updateCompletion: _noOp,
      )));
      await tester.pump();
      expect(find.byType(TaskListWeek), findsOneWidget);
    });

    testWidgets('shows task name', (tester) async {
      final task = _makeTask(name: 'Doctor Appointment');
      await tester.pumpWidget(_wrap(TaskListWeek(
        events: [_toEvent(task)],
        patientNames: {},
        onEdit: (_) {},
        onDelete: (_) {},
        updateCompletion: _noOp,
      )));
      await tester.pump();
      expect(find.text('Doctor Appointment'), findsOneWidget);
    });

    testWidgets('shows "All day" for task with no time', (tester) async {
      final task = _makeTask();
      await tester.pumpWidget(_wrap(TaskListWeek(
        events: [_toEvent(task)],
        patientNames: {},
        onEdit: (_) {},
        onDelete: (_) {},
        updateCompletion: _noOp,
      )));
      await tester.pump();
      expect(find.textContaining('All day'), findsOneWidget);
    });

    testWidgets('shows edit and delete buttons', (tester) async {
      final task = _makeTask();
      await tester.pumpWidget(_wrap(TaskListWeek(
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

    testWidgets('shows "Mark as Complete" for incomplete task', (tester) async {
      final task = _makeTask(isComplete: false);
      await tester.pumpWidget(_wrap(TaskListWeek(
        events: [_toEvent(task)],
        patientNames: {},
        onEdit: (_) {},
        onDelete: (_) {},
        updateCompletion: _noOp,
      )));
      await tester.pump();
      expect(find.text('Mark as Complete'), findsOneWidget);
    });

    testWidgets('shows "Completed" for complete task', (tester) async {
      final task = _makeTask(isComplete: true);
      await tester.pumpWidget(_wrap(TaskListWeek(
        events: [_toEvent(task)],
        patientNames: {},
        onEdit: (_) {},
        onDelete: (_) {},
        updateCompletion: _noOp,
      )));
      await tester.pump();
      expect(find.text('Completed'), findsOneWidget);
    });

    testWidgets('invokes onEdit callback', (tester) async {
      Task? edited;
      final task = _makeTask(name: 'Edit Target');
      await tester.pumpWidget(_wrap(TaskListWeek(
        events: [_toEvent(task)],
        patientNames: {},
        onEdit: (t) => edited = t,
        onDelete: (_) {},
        updateCompletion: _noOp,
      )));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.edit));
      expect(edited?.name, 'Edit Target');
    });

    testWidgets('invokes onDelete callback', (tester) async {
      Task? deleted;
      final task = _makeTask(name: 'Delete Target');
      await tester.pumpWidget(_wrap(TaskListWeek(
        events: [_toEvent(task)],
        patientNames: {},
        onEdit: (_) {},
        onDelete: (t) => deleted = t,
        updateCompletion: _noOp,
      )));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.delete));
      expect(deleted?.name, 'Delete Target');
    });

    testWidgets('renders two tasks from different days', (tester) async {
      final t1 = _makeTask(name: 'Monday Task', date: DateTime(2025, 6, 16));
      final t2 = _makeTask(name: 'Friday Task', date: DateTime(2025, 6, 20));
      await tester.pumpWidget(_wrap(TaskListWeek(
        events: [_toEvent(t1), _toEvent(t2)],
        patientNames: {},
        onEdit: (_) {},
        onDelete: (_) {},
        updateCompletion: _noOp,
      )));
      await tester.pump();
      expect(find.text('Monday Task'), findsOneWidget);
      expect(find.text('Friday Task'), findsOneWidget);
    });

    testWidgets('shows patient name when patientId matches', (tester) async {
      final task = _makeTask(patientId: 7);
      await tester.pumpWidget(_wrap(TaskListWeek(
        events: [_toEvent(task)],
        patientNames: {7: 'Bob'},
        onEdit: (_) {},
        onDelete: (_) {},
        updateCompletion: _noOp,
      )));
      await tester.pump();
      expect(find.textContaining('Bob'), findsOneWidget);
    });
  });

  // Cases merged from calendar_assistant/task_list_week_test.dart.
  group('merged from calendar_assistant/task_list_week_test.dart', () {
    // TaskTypeManager loads saved types from SharedPreferences. Without a mock
    // this throws MissingPluginException on Linux CI.
    setUp(() => SharedPreferences.setMockInitialValues({}));

    group('TaskListWeek Widget Tests', () {
      testWidgets('shows "No tasks this week" when empty', (tester) async {
        await tester.pumpWidget(
          _wrapWithProviders(
            TaskListWeek(
              events: const [],
              patientNames: const {},
              onEdit: (_) {},
              onDelete: (_) {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('No tasks this week'), findsOneWidget);
      });

      testWidgets('renders and sorts tasks by date/time', (tester) async {
        final now = DateTime.now();
        final t1 = Task(
          id: 1,
          name: 'Morning Yoga',
          date: now,
          timeOfDay: const TimeOfDay(hour: 7, minute: 30),
          taskType: 'exercise',
        );
        final t2 = Task(
          id: 2,
          name: 'Doctor Visit',
          date: now.add(const Duration(days: 1)),
          timeOfDay: const TimeOfDay(hour: 9, minute: 0),
          taskType: 'general',
        );

        await tester.pumpWidget(
          _wrapWithProviders(
            TaskListWeek(
              events: [_eventForTask(t2), _eventForTask(t1)],
              patientNames: const {},
              onEdit: (_) {},
              onDelete: (_) {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        final tiles =
            tester.widgetList<ListTile>(find.byType(ListTile)).toList();
        final firstTitle = (tiles.first.title as Text).data!;
        expect(firstTitle, contains('Morning Yoga'));
      });

      testWidgets('edit/delete buttons trigger callbacks', (tester) async {
        bool edit = false, del = false;
        final t = Task(
          id: 3,
          name: 'Medication Review',
          date: DateTime.now(),
          taskType: 'general',
        );

        await tester.pumpWidget(
          _wrapWithProviders(
            TaskListWeek(
              events: [_eventForTask(t)],
              patientNames: const {},
              onEdit: (_) => edit = true,
              onDelete: (_) => del = true,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.edit));
        await tester.pumpAndSettle();
        expect(edit, isTrue);

        await tester.tap(find.byIcon(Icons.delete));
        await tester.pumpAndSettle();
        expect(del, isTrue);
      });

      testWidgets('Mark as Complete toggles label and calls updateCompletion', (
        tester,
      ) async {
        final task = Task(
          id: 4,
          name: 'Evening Walk',
          date: DateTime.now(),
          timeOfDay: const TimeOfDay(hour: 18, minute: 0),
          taskType: 'exercise',
          isComplete: false,
        );

        final calls = <Map<String, dynamic>>[];

        await tester.pumpWidget(
          _wrapWithProviders(
            TaskListWeek(
              events: [_eventForTask(task)],
              patientNames: const {},
              onEdit: (_) {},
              onDelete: (_) {},
              updateCompletion: (id, comp) async {
                calls.add({'id': id, 'complete': comp});
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        final markFinder = find.text('Mark as Complete');
        final buttonFinder = find.ancestor(
          of: markFinder,
          matching: find.byWidgetPredicate(
            (w) =>
                w is OutlinedButton ||
                w.runtimeType.toString().contains('OutlinedButton'),
          ),
        );

        expect(buttonFinder, findsAtLeastNWidgets(1));
        await tester.tap(buttonFinder.first, warnIfMissed: false);

        // Allow UI + async callback to complete
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pumpAndSettle(const Duration(seconds: 1));

        // Check UI updated and callback fired
        expect(find.text('Completed'), findsWidgets);
        await tester.runAsync(() async {
          await Future.delayed(const Duration(milliseconds: 200));
        });
        expect(
          calls,
          isNotEmpty,
          reason: 'Expected updateCompletion to be called at least once',
        );
        expect(calls.first['complete'], isTrue);
      });

      testWidgets('API failure rolls back and shows SnackBar', (tester) async {
        final task = Task(
          id: 5,
          name: 'Take Meds',
          date: DateTime.now(),
          timeOfDay: const TimeOfDay(hour: 9, minute: 0),
          taskType: 'general',
          isComplete: false,
        );

        bool threw = false;

        await tester.pumpWidget(
          _wrapWithProviders(
            TaskListWeek(
              events: [_eventForTask(task)],
              patientNames: const {},
              onEdit: (_) {},
              onDelete: (_) {},
              updateCompletion: (id, comp) async {
                threw = true;
                throw Exception("Simulated error");
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        final markFinder = find.text('Mark as Complete');
        final buttonFinder = find.ancestor(
          of: markFinder,
          matching: find.byWidgetPredicate(
            (w) =>
                w is OutlinedButton ||
                w.runtimeType.toString().contains('OutlinedButton'),
          ),
        );

        await tester.tap(buttonFinder.first, warnIfMissed: false);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pumpAndSettle(const Duration(seconds: 1));

        await tester.runAsync(() async {
          await Future.delayed(const Duration(milliseconds: 200));
        });

        expect(threw, isTrue, reason: 'Expected updateCompletion to throw');
        expect(find.textContaining('Failed to update task'), findsWidgets);
        expect(find.text('Mark as Complete'), findsWidgets);
      });
    });
  });
}
