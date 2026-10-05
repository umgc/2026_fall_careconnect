import 'package:calendar_view/calendar_view.dart';
import 'package:care_connect_app/features/tasks/models/task_model.dart';
import 'package:care_connect_app/features/tasks/presentation/widgets/task_list_week.dart';
import 'package:care_connect_app/features/tasks/utils/task_type_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrapWithProviders(Widget child) {
  return ChangeNotifierProvider<TaskTypeManager>(
    create: (_) => TaskTypeManager()
      ..addTaskType("general", Colors.blue)
      ..addTaskType("exercise", Colors.green),
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

CalendarEventData<Task> _eventForTask(Task t) =>
    CalendarEventData<Task>(date: t.date, event: t, title: t.name);

void main() {
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

      final tiles = tester.widgetList<ListTile>(find.byType(ListTile)).toList();
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
}
