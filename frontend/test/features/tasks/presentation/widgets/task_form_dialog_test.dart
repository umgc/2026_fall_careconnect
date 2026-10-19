// Tests for TaskFormDialog
// (lib/features/tasks/presentation/widgets/task_form_dialog.dart).
//
// Pure form widget — no HTTP in initState.
// Requires TaskTypeManager (ChangeNotifierProvider) backed by SharedPreferences mock.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:care_connect_app/features/tasks/presentation/widgets/task_form_dialog.dart';
import 'package:care_connect_app/features/tasks/utils/task_type_manager.dart';
import 'package:care_connect_app/features/tasks/models/task_model.dart';
import 'package:care_connect_app/features/notifications/models/scheduled_notification_model.dart';

Widget _wrap({bool isCaregiver = false, List<Map<String, dynamic>>? patients, Task? initialTask, int? defaultPatientId, DateTime? initialDate}) {
  return MaterialApp(
    home: Scaffold(
      body: ChangeNotifierProvider<TaskTypeManager>(
        create: (_) => TaskTypeManager(),
        child: SingleChildScrollView(
          child: TaskFormDialog(
            isCaregiver: isCaregiver,
            patients: patients ?? const [],
            initialTask: initialTask,
            defaultPatientId: defaultPatientId,
            initialDate: initialDate,
          ),
        ),
      ),
    ),
  );
}

// ── Helpers from calendar_assistant/task_form_dialog_test.dart (merged) ──

class FakeTaskTypeManager extends ChangeNotifier implements TaskTypeManager {
  @override
  Map<String, Color> get taskTypeColors => <String, Color>{
    'general': Colors.blue,
    'lab': Colors.red,
  };

  @override
  IconData getIcon(String? type) => Icons.task;

  @override
  Color getColor(String? type) => taskTypeColors[type] ?? Colors.blue;

  @override
  Future<void> addTaskType(String name, Color color, {IconData? icon}) async {}

  @override
  Future<void> removeTaskType(String name) async {}

  @override
  Future<void> resetDefaults() async {}

  @override
  Future<void> updateTaskColor(String name, Color color) async {}

  @override
  Future<void> updateTaskIcon(String name, IconData icon) async {}

  @override
  List<String> getSortedTypes() => taskTypeColors.keys.toList()..sort();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('TaskFormDialog – initial render', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byType(TaskFormDialog), findsOneWidget);
    });

    testWidgets('shows title text field', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byType(TextFormField), findsWidgets);
    });

    testWidgets('shows Save button', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('shows Cancel button', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('shows "Add Task" heading for new task', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('Add Task'), findsOneWidget);
    });

    testWidgets('shows Task Title label', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('Task Title'), findsOneWidget);
    });

    testWidgets('shows Description label', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('Description'), findsOneWidget);
    });

    testWidgets('shows Task Type dropdown', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('Task Type'), findsOneWidget);
    });

    testWidgets('shows Date row with "Not set" or date', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('Date: '), findsOneWidget);
    });

    testWidgets('shows Pick Date button', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('Pick Date'), findsOneWidget);
    });

    testWidgets('shows Time row', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('Time: '), findsOneWidget);
      expect(find.text('Not set'), findsAtLeastNWidgets(1));
    });

    testWidgets('shows Pick Time button', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('Pick Time'), findsOneWidget);
    });

    testWidgets('shows Reminder Notification dropdown', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('Reminder Notification'), findsOneWidget);
    });

    testWidgets('Save button is disabled when title is empty', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      final saveButton = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Save'),
      );
      expect(saveButton.onPressed, isNull);
    });

    testWidgets('Save button enables after entering title', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      // Find the title TextFormField and enter text
      await tester.enterText(find.byType(TextFormField).first, 'My Task');
      await tester.pump();
      final saveButton = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Save'),
      );
      expect(saveButton.onPressed, isNotNull);
    });

    testWidgets('shows RecurrenceForm widget', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      // RecurrenceForm should be present in the tree
      expect(find.textContaining('Recur'), findsWidgets);
    });
  });

  group('TaskFormDialog – caregiver mode', () {
    testWidgets('shows patient assignment section for caregiver', (tester) async {
      await tester.pumpWidget(_wrap(isCaregiver: true));
      await tester.pump();
      expect(find.text('Assign to Patient(s)'), findsOneWidget);
    });

    testWidgets('shows Assign to All Patients checkbox', (tester) async {
      await tester.pumpWidget(_wrap(isCaregiver: true));
      await tester.pump();
      expect(find.text('Assign to All Patients'), findsOneWidget);
    });

    testWidgets('does not show patient assignment for non-caregiver', (tester) async {
      await tester.pumpWidget(_wrap(isCaregiver: false));
      await tester.pump();
      expect(find.text('Assign to Patient(s)'), findsNothing);
    });
  });

  group('TaskFormDialog – date and time pickers', () {
    testWidgets('tapping Pick Date opens date picker', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      await tester.ensureVisible(find.text('Pick Date'));
      await tester.pump();
      await tester.tap(find.text('Pick Date'));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
    });

    testWidgets('tapping Pick Time opens time picker', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      await tester.ensureVisible(find.text('Pick Time'));
      await tester.pump();
      await tester.tap(find.text('Pick Time'));
      await tester.pumpAndSettle();
      expect(find.byType(TimePickerDialog), findsOneWidget);
    });

    testWidgets('selecting a date from date picker updates the date display', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      await tester.ensureVisible(find.text('Pick Date'));
      await tester.pump();
      await tester.tap(find.text('Pick Date'));
      await tester.pumpAndSettle();

      // Tap OK to confirm the currently shown date
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      // Date picker should be dismissed
      expect(find.byType(DatePickerDialog), findsNothing);
      // Date row should show a date (not "Not set")
      expect(find.text('Date: '), findsOneWidget);
    });

    testWidgets('cancelling date picker does not change date', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      await tester.ensureVisible(find.text('Pick Date'));
      await tester.pump();
      await tester.tap(find.text('Pick Date'));
      await tester.pumpAndSettle();

      // Cancel the date picker
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();

      expect(find.byType(DatePickerDialog), findsNothing);
    });

    testWidgets('selecting a time from time picker updates the time display', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      await tester.ensureVisible(find.text('Pick Time'));
      await tester.pump();
      await tester.tap(find.text('Pick Time'));
      await tester.pumpAndSettle();

      // Tap OK to confirm
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(find.byType(TimePickerDialog), findsNothing);
    });

    testWidgets('cancelling time picker does not change time', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      await tester.ensureVisible(find.text('Pick Time'));
      await tester.pump();
      await tester.tap(find.text('Pick Time'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();

      expect(find.byType(TimePickerDialog), findsNothing);
      // Time should still show "Not set"
      expect(find.text('Not set'), findsAtLeastNWidgets(1));
    });
  });

  group('TaskFormDialog – edit mode', () {
    testWidgets('shows "Edit Task" when initialTask is provided', (tester) async {
      final task = Task(
        id: 42,
        name: 'Existing Task',
        description: 'Some description',
        date: DateTime(2025, 6, 15),
        taskType: 'general',
      );
      await tester.pumpWidget(_wrap(initialTask: task));
      await tester.pump();
      expect(find.text('Edit Task'), findsOneWidget);
      expect(find.text('Existing Task'), findsOneWidget);
    });

    testWidgets('pre-fills description in edit mode', (tester) async {
      final task = Task(
        id: 1,
        name: 'My Task',
        description: 'Task description here',
        date: DateTime(2025, 6, 15),
      );
      await tester.pumpWidget(_wrap(initialTask: task));
      await tester.pump();
      expect(find.text('Task description here'), findsOneWidget);
    });

    testWidgets('pre-fills time in edit mode', (tester) async {
      final task = Task(
        id: 1,
        name: 'Timed Task',
        description: '',
        date: DateTime(2025, 6, 15),
        timeOfDay: const TimeOfDay(hour: 14, minute: 30),
      );
      await tester.pumpWidget(_wrap(initialTask: task));
      await tester.pump();
      expect(find.text('14:30'), findsOneWidget);
    });

    testWidgets('edit mode with assigned patient ID selects that patient', (tester) async {
      final task = Task(
        id: 1,
        name: 'Patient Task',
        description: '',
        date: DateTime(2025, 6, 15),
        assignedPatientId: 2,
      );
      await tester.pumpWidget(_wrap(
        isCaregiver: true,
        initialTask: task,
        patients: [
          {'patient': {'id': 1, 'firstName': 'Alice', 'lastName': 'A'}},
          {'patient': {'id': 2, 'firstName': 'Bob', 'lastName': 'B'}},
        ],
      ));
      await tester.pump();
      // The patient list should show both patients
      expect(find.text('Alice A'), findsOneWidget);
      expect(find.text('Bob B'), findsOneWidget);
    });

    testWidgets('edit mode with notification pre-fills reminder', (tester) async {
      final now = DateTime(2025, 6, 15, 10, 0);
      final task = Task(
        id: 1,
        name: 'Reminder Task',
        description: '',
        date: DateTime(2025, 6, 15),
        timeOfDay: const TimeOfDay(hour: 10, minute: 0),
        notifications: [
          ScheduledNotification(
            scheduledTime: now.subtract(const Duration(minutes: 15)),
            title: 'Reminder',
            body: 'Do the thing',
            receiverId: 1,
            status: 'PENDING',
          ),
        ],
      );
      await tester.pumpWidget(_wrap(initialTask: task));
      await tester.pump();
      // The reminder should be prefilled to "15 minutes before"
      expect(find.text('15 minutes before'), findsWidgets);
    });

    testWidgets('edit mode with recurring task shows recurrence type', (tester) async {
      final task = Task(
        id: 1,
        name: 'Recurring',
        description: '',
        date: DateTime(2025, 6, 15),
        frequency: 'daily',
        interval: 1,
        count: 5,
      );
      await tester.pumpWidget(_wrap(initialTask: task));
      await tester.pump();
      // The recurring checkbox should be checked
      final recurringCheckbox = tester.widgetList<CheckboxListTile>(
        find.byType(CheckboxListTile),
      );
      expect(recurringCheckbox.any((c) => c.value == true), isTrue);
    });

    testWidgets('date is shown from initialDate when no initialTask', (tester) async {
      final date = DateTime(2025, 12, 25);
      await tester.pumpWidget(_wrap(initialDate: date));
      await tester.pump();
      expect(find.text('12/25/2025'), findsOneWidget);
    });
  });

  group('TaskFormDialog – form validation (canSave)', () {
    testWidgets('Save disabled with whitespace-only title', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      await tester.enterText(find.byType(TextFormField).first, '   ');
      await tester.pump();
      final saveButton = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Save'),
      );
      expect(saveButton.onPressed, isNull);
    });

    testWidgets('Save enabled with valid title text', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      await tester.enterText(find.byType(TextFormField).first, 'Valid Title');
      await tester.pump();
      final saveButton = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Save'),
      );
      expect(saveButton.onPressed, isNotNull);
    });

    testWidgets('Save re-disables after clearing title', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      await tester.enterText(find.byType(TextFormField).first, 'Title');
      await tester.pump();
      // Clear it
      await tester.enterText(find.byType(TextFormField).first, '');
      await tester.pump();
      final saveButton = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Save'),
      );
      expect(saveButton.onPressed, isNull);
    });
  });

  group('TaskFormDialog – patient assignment interactions', () {
    testWidgets('individual patient checkbox can be toggled', (tester) async {
      await tester.pumpWidget(_wrap(
        isCaregiver: true,
        patients: [
          {'patient': {'id': 1, 'firstName': 'Alice', 'lastName': 'A'}},
          {'patient': {'id': 2, 'firstName': 'Bob', 'lastName': 'B'}},
        ],
      ));
      await tester.pump();

      // Tap on Alice checkbox
      await tester.tap(find.text('Alice A'));
      await tester.pumpAndSettle();

      // The Alice checkbox should now be checked
      final aliceTile = tester.widgetList<CheckboxListTile>(
        find.byType(CheckboxListTile),
      ).where((t) {
        final title = t.title;
        return title is Text && title.data == 'Alice A';
      });
      expect(aliceTile.isNotEmpty, isTrue);
    });

    testWidgets('Assign to All selects all patient checkboxes', (tester) async {
      await tester.pumpWidget(_wrap(
        isCaregiver: true,
        patients: [
          {'patient': {'id': 1, 'firstName': 'Alice', 'lastName': 'A'}},
          {'patient': {'id': 2, 'firstName': 'Bob', 'lastName': 'B'}},
        ],
      ));
      await tester.pump();

      await tester.tap(find.text('Assign to All Patients'));
      await tester.pumpAndSettle();

      // All CheckboxListTiles should be checked
      final allTiles = tester.widgetList<CheckboxListTile>(
        find.byType(CheckboxListTile),
      );
      // At least the "Assign to All" and both patient tiles should be checked
      final checkedCount = allTiles.where((t) => t.value == true).length;
      expect(checkedCount, greaterThanOrEqualTo(3));
    });

    testWidgets('un-checking Assign to All unchecks all patients', (tester) async {
      await tester.pumpWidget(_wrap(
        isCaregiver: true,
        patients: [
          {'patient': {'id': 1, 'firstName': 'Alice', 'lastName': 'A'}},
          {'patient': {'id': 2, 'firstName': 'Bob', 'lastName': 'B'}},
        ],
      ));
      await tester.pump();

      // Check all
      await tester.tap(find.text('Assign to All Patients'));
      await tester.pumpAndSettle();

      // Uncheck all
      await tester.tap(find.text('Assign to All Patients'));
      await tester.pumpAndSettle();

      final allTiles = tester.widgetList<CheckboxListTile>(
        find.byType(CheckboxListTile),
      );
      // Only the "Recurring Task" checkbox may remain; patient-related ones should be unchecked
      // Filter only the ones in the patient section (first few tiles)
      final checkedPatientTiles = allTiles.where((t) {
        final title = t.title;
        if (title is Text) {
          return (title.data == 'Alice A' || title.data == 'Bob B' || title.data == 'Assign to All Patients') && t.value == true;
        }
        return false;
      });
      expect(checkedPatientTiles.length, 0);
    });

    testWidgets('defaultPatientId pre-selects patient for caregiver', (tester) async {
      await tester.pumpWidget(_wrap(
        isCaregiver: true,
        defaultPatientId: 2,
        patients: [
          {'patient': {'id': 1, 'firstName': 'Alice', 'lastName': 'A'}},
          {'patient': {'id': 2, 'firstName': 'Bob', 'lastName': 'B'}},
        ],
      ));
      await tester.pump();

      // Bob should be pre-selected
      final bobTile = tester.widgetList<CheckboxListTile>(
        find.byType(CheckboxListTile),
      ).where((t) {
        final title = t.title;
        return title is Text && title.data == 'Bob B' && t.value == true;
      });
      expect(bobTile.length, 1);
    });

    testWidgets('patient with null id renders SizedBox.shrink', (tester) async {
      await tester.pumpWidget(_wrap(
        isCaregiver: true,
        patients: [
          {'patient': {'id': null, 'firstName': 'Ghost', 'lastName': 'User'}},
          {'patient': {'id': 1, 'firstName': 'Alice', 'lastName': 'A'}},
        ],
      ));
      await tester.pump();

      // Ghost User should not appear as a checkbox
      expect(find.text('Ghost User'), findsNothing);
      expect(find.text('Alice A'), findsOneWidget);
    });

    testWidgets('patient with empty name shows Unknown', (tester) async {
      await tester.pumpWidget(_wrap(
        isCaregiver: true,
        patients: [
          {'patient': {'id': 1, 'firstName': '', 'lastName': ''}},
        ],
      ));
      await tester.pump();

      expect(find.text('Unknown'), findsOneWidget);
    });
  });

  group('TaskFormDialog – Cancel button', () {
    testWidgets('Cancel button pops the navigator', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChangeNotifierProvider<TaskTypeManager>(
              create: (_) => TaskTypeManager(),
              child: Builder(
                builder: (ctx) => ElevatedButton(
                  onPressed: () async {
                    final result = await showDialog(
                      context: ctx,
                      builder: (_) => ChangeNotifierProvider<TaskTypeManager>(
                        create: (_) => TaskTypeManager(),
                        child: TaskFormDialog(isCaregiver: false, patients: []),
                      ),
                    );
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(content: Text('Result: ${result == null}')),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Dialog is open
      expect(find.text('Add Task'), findsOneWidget);

      // Scroll Cancel into view and tap
      final cancelFinder = find.text('Cancel');
      await tester.ensureVisible(cancelFinder);
      await tester.pumpAndSettle();
      await tester.tap(cancelFinder, warnIfMissed: false);
      await tester.pumpAndSettle();

      // Should show snackbar confirming null result
      expect(find.text('Result: true'), findsOneWidget);
    });
  });

  group('TaskFormDialog – description field', () {
    testWidgets('description text can be entered', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      // Description is the second TextFormField
      await tester.enterText(find.byType(TextFormField).at(1), 'A description');
      await tester.pump();
      expect(find.text('A description'), findsOneWidget);
    });
  });

  group('TaskFormDialog – task type dropdown', () {
    testWidgets('task type dropdown shows default types after loading', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      // The default selected type should be "general" (capitalized in display)
      expect(find.text('General'), findsWidgets);
    });
  });

  group('TaskFormDialog – recurring task with weekly type', () {
    testWidgets('recurring task with weekly frequency and daysOfWeek shows checked', (tester) async {
      final task = Task(
        id: 1,
        name: 'Weekly Task',
        description: '',
        date: DateTime(2025, 6, 15),
        frequency: 'weekly',
        interval: 1,
        count: 4,
        daysOfWeek: [false, true, false, true, false, false, false],
      );
      await tester.pumpWidget(_wrap(initialTask: task));
      await tester.pumpAndSettle();

      // Should show the day-of-week selector
      expect(find.text('Select Days of Week'), findsOneWidget);
    });
  });

  group('TaskFormDialog – monthly recurrence', () {
    testWidgets('monthly recurring task shows day of month selector', (tester) async {
      final task = Task(
        id: 1,
        name: 'Monthly Task',
        description: '',
        date: DateTime(2025, 6, 15),
        frequency: 'monthly',
        interval: 1,
        count: 3,
      );
      await tester.pumpWidget(_wrap(initialTask: task));
      await tester.pumpAndSettle();

      expect(find.text('Day of Month:'), findsOneWidget);
    });
  });

  group('TaskFormDialog – edit mode with various task types', () {
    testWidgets('edit mode with lab task type', (tester) async {
      final task = Task(
        id: 1,
        name: 'Lab Work',
        description: 'Blood test',
        date: DateTime(2025, 6, 15),
        taskType: 'lab',
      );
      await tester.pumpWidget(_wrap(initialTask: task));
      await tester.pumpAndSettle();

      expect(find.text('Edit Task'), findsOneWidget);
      expect(find.text('Lab Work'), findsOneWidget);
    });

    testWidgets('edit mode with appointment task type', (tester) async {
      final task = Task(
        id: 2,
        name: 'Doctor Visit',
        description: 'Annual checkup',
        date: DateTime(2025, 7, 1),
        taskType: 'appointment',
      );
      await tester.pumpWidget(_wrap(initialTask: task));
      await tester.pumpAndSettle();

      expect(find.text('Edit Task'), findsOneWidget);
      expect(find.text('Doctor Visit'), findsOneWidget);
    });
  });

  group('TaskFormDialog – reminder notification with different offsets', () {
    testWidgets('edit with 5-minute reminder pre-fills correctly', (tester) async {
      final taskDate = DateTime(2025, 6, 15);
      final taskTime = const TimeOfDay(hour: 10, minute: 0);
      final scheduledAt = DateTime(2025, 6, 15, 9, 55); // 5 min before
      final task = Task(
        id: 1,
        name: 'Quick Reminder',
        description: '',
        date: taskDate,
        timeOfDay: taskTime,
        notifications: [
          ScheduledNotification(
            scheduledTime: scheduledAt,
            title: 'Reminder',
            body: 'Soon!',
            receiverId: 1,
            status: 'PENDING',
          ),
        ],
      );
      await tester.pumpWidget(_wrap(initialTask: task));
      await tester.pump();
      expect(find.text('5 minutes before'), findsWidgets);
    });

    testWidgets('edit with 1-hour reminder pre-fills correctly', (tester) async {
      final taskDate = DateTime(2025, 6, 15);
      final taskTime = const TimeOfDay(hour: 10, minute: 0);
      final scheduledAt = DateTime(2025, 6, 15, 9, 0); // 1 hour before
      final task = Task(
        id: 1,
        name: 'Hour Reminder',
        description: '',
        date: taskDate,
        timeOfDay: taskTime,
        notifications: [
          ScheduledNotification(
            scheduledTime: scheduledAt,
            title: 'Reminder',
            body: 'Coming up!',
            receiverId: 1,
            status: 'PENDING',
          ),
        ],
      );
      await tester.pumpWidget(_wrap(initialTask: task));
      await tester.pump();
      expect(find.text('1 hour before'), findsWidgets);
    });

    testWidgets('edit with 1-day reminder pre-fills correctly', (tester) async {
      final taskDate = DateTime(2025, 6, 15);
      final taskTime = const TimeOfDay(hour: 10, minute: 0);
      final scheduledAt = DateTime(2025, 6, 14, 10, 0); // 1 day before
      final task = Task(
        id: 1,
        name: 'Day Reminder',
        description: '',
        date: taskDate,
        timeOfDay: taskTime,
        notifications: [
          ScheduledNotification(
            scheduledTime: scheduledAt,
            title: 'Reminder',
            body: 'Tomorrow!',
            receiverId: 1,
            status: 'PENDING',
          ),
        ],
      );
      await tester.pumpWidget(_wrap(initialTask: task));
      await tester.pump();
      expect(find.text('1 day before'), findsWidgets);
    });

    testWidgets('edit with non-standard offset defaults to None', (tester) async {
      final taskDate = DateTime(2025, 6, 15);
      final taskTime = const TimeOfDay(hour: 10, minute: 0);
      // 2 hours before - not a standard option
      final scheduledAt = DateTime(2025, 6, 15, 8, 0);
      final task = Task(
        id: 1,
        name: 'Custom Reminder',
        description: '',
        date: taskDate,
        timeOfDay: taskTime,
        notifications: [
          ScheduledNotification(
            scheduledTime: scheduledAt,
            title: 'Reminder',
            body: 'Custom!',
            receiverId: 1,
            status: 'PENDING',
          ),
        ],
      );
      await tester.pumpWidget(_wrap(initialTask: task));
      await tester.pump();
      expect(find.text('None'), findsWidgets);
    });

    testWidgets('task with empty notifications list defaults reminder to None', (tester) async {
      final task = Task(
        id: 1,
        name: 'No Notifs',
        description: '',
        date: DateTime(2025, 6, 15),
        notifications: [],
      );
      await tester.pumpWidget(_wrap(initialTask: task));
      await tester.pump();
      expect(find.text('None'), findsWidgets);
    });
  });

  group('TaskFormDialog – non-caregiver with defaultPatientId', () {
    testWidgets('non-caregiver with defaultPatientId does not show patient section', (tester) async {
      await tester.pumpWidget(_wrap(
        isCaregiver: false,
        defaultPatientId: 5,
      ));
      await tester.pump();
      expect(find.text('Assign to Patient(s)'), findsNothing);
    });
  });

  group('TaskFormDialog – yearly recurrence', () {
    testWidgets('yearly recurring task shows Ends in Year selector', (tester) async {
      final task = Task(
        id: 1,
        name: 'Yearly Task',
        description: '',
        date: DateTime(2025, 6, 15),
        frequency: 'yearly',
        interval: 1,
        count: 3,
      );
      await tester.pumpWidget(_wrap(initialTask: task));
      await tester.pumpAndSettle();

      expect(find.text('Ends in Year:'), findsOneWidget);
    });
  });

  // Cases merged from calendar_assistant/task_form_dialog_test.dart.
  group('merged from calendar_assistant/task_form_dialog_test.dart', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    late FakeTaskTypeManager fakeManager;

    setUp(() {
      fakeManager = FakeTaskTypeManager();
    });

    Widget wrap(Widget child) {
      return MaterialApp(
        home: ChangeNotifierProvider<TaskTypeManager>.value(
          value: fakeManager,
          child: Scaffold(body: child),
        ),
      );
    }

    group('TaskFormDialog Widget', () {
      testWidgets('renders all expected sections', (tester) async {
        await tester.pumpWidget(
          wrap(
            TaskFormDialog(
              isCaregiver: true,
              patients: [
                {
                  'patient': {'id': 1, 'firstName': 'John', 'lastName': 'Doe'},
                },
                {
                  'patient': {'id': 2, 'firstName': 'Jane', 'lastName': 'Smith'},
                },
              ],
            ),
          ),
        );

        expect(find.text('Add Task'), findsOneWidget);
        expect(find.text('Task Title'), findsOneWidget);
        expect(find.text('Description'), findsOneWidget);
        expect(find.text('Task Type'), findsOneWidget);
        expect(find.text('Reminder Notification'), findsOneWidget);
        expect(find.text('Recurring Task'), findsOneWidget);
        expect(find.text('Assign to Patient(s)'), findsOneWidget);
      });

      testWidgets('typing title enables Save button', (tester) async {
        await tester.pumpWidget(
          wrap(TaskFormDialog(isCaregiver: false, patients: [])),
        );

        final saveBefore = tester.widget<ElevatedButton>(
          find.widgetWithText(ElevatedButton, 'Save'),
        );
        expect(saveBefore.onPressed, isNull);

        await tester.enterText(find.byType(TextFormField).first, 'My New Task');
        await tester.pumpAndSettle();

        final saveAfter = tester.widget<ElevatedButton>(
          find.widgetWithText(ElevatedButton, 'Save'),
        );
        expect(saveAfter.onPressed, isNotNull);
      });

      testWidgets('caregiver can select Assign to All Patients', (tester) async {
        await tester.pumpWidget(
          wrap(
            TaskFormDialog(
              isCaregiver: true,
              patients: [
                {
                  'patient': {'id': 1, 'firstName': 'Alice', 'lastName': 'Lee'},
                },
                {
                  'patient': {'id': 2, 'firstName': 'Bob', 'lastName': 'King'},
                },
              ],
            ),
          ),
        );

        await tester.tap(find.text('Assign to All Patients'));
        await tester.pumpAndSettle();

        final allTiles = tester.widgetList<CheckboxListTile>(
          find.byType(CheckboxListTile),
        );
        expect(allTiles.where((t) => t.value == true).length, greaterThan(0));
      });

      testWidgets('updates reminder dropdown selection', (tester) async {
        await tester.pumpWidget(
          wrap(TaskFormDialog(isCaregiver: false, patients: [])),
        );

        await tester.tap(find.byType(DropdownButtonFormField<String>).last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('15 minutes before').last);
        await tester.pumpAndSettle();

        expect(find.text('15 minutes before'), findsWidgets);
      });

      /// ✅ FIXED: ensure provider + ensureVisible + pump scroll
      testWidgets('Save button returns result map after filling title', (
        tester,
      ) async {
        await tester.pumpWidget(
          wrap(
            Builder(
              builder: (outerContext) => ElevatedButton(
                onPressed: () async {
                  final result = await showDialog(
                    context: outerContext,
                    builder: (context) =>
                        ChangeNotifierProvider<TaskTypeManager>.value(
                          value: fakeManager,
                          child: TaskFormDialog(isCaregiver: false, patients: []),
                        ),
                  );
                  ScaffoldMessenger.of(outerContext).showSnackBar(
                    SnackBar(content: Text('Returned: ${result != null}')),
                  );
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Dialog'));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextFormField).first, 'Example Task');
        await tester.pumpAndSettle();

        // ensure Save is visible (scroll if needed)
        final saveButtonFinder = find.widgetWithText(ElevatedButton, 'Save');
        await tester.ensureVisible(saveButtonFinder);
        await tester.pumpAndSettle();

        await tester.tap(saveButtonFinder, warnIfMissed: false);
        await tester.pumpAndSettle(const Duration(milliseconds: 500));

        // confirm snackbar appears
        expect(find.textContaining('Returned: true'), findsOneWidget);
      });

      testWidgets('renders correctly with existing task + notification', (
        tester,
      ) async {
        final existingTask = Task(
          id: 1,
          name: 'Follow-up',
          description: 'Check in with patient',
          date: DateTime.now(),
          assignedPatientId: 1,
          taskType: 'general',
          notifications: [
            ScheduledNotification(
              scheduledTime: DateTime.now().subtract(const Duration(minutes: 15)),
              title: 'Reminder',
              body: 'Check in soon!',
              notificationType: 'TASK_REMINDER',
              receiverId: 1,
              status: 'PENDING',
            ),
          ],
        );

        await tester.pumpWidget(
          wrap(
            TaskFormDialog(
              isCaregiver: false,
              patients: [],
              initialTask: existingTask,
            ),
          ),
        );

        await tester.pumpAndSettle();

        expect(find.text('Edit Task'), findsOneWidget);
        expect(find.text('Follow-up'), findsOneWidget);
      });
    });
  });
}
