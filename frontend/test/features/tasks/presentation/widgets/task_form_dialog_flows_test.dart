// Save flows for TaskFormDialog
// (lib/features/tasks/presentation/widgets/task_form_dialog.dart) shown via
// showDialog: caregiver assigning to all / some patients with a reminder,
// editing a monthly task that has an existing reminder, and the patient path.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/features/notifications/models/scheduled_notification_model.dart';
import 'package:care_connect_app/features/tasks/models/task_model.dart';
import 'package:care_connect_app/features/tasks/presentation/widgets/task_form_dialog.dart';
import 'package:care_connect_app/features/tasks/utils/task_type_manager.dart';

const _patients = [
  {
    'patient': {'id': 1, 'firstName': 'Pat', 'lastName': 'One'},
  },
  {
    'patient': {'id': 2, 'firstName': '', 'lastName': ''},
  },
];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<Map<String, dynamic>?> open(
    WidgetTester tester,
    TaskFormDialog dialog,
    Future<void> Function() interact,
  ) async {
    tester.view.physicalSize = const Size(1000, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    Map<String, dynamic>? result;
    await tester.pumpWidget(ChangeNotifierProvider<TaskTypeManager>(
      create: (_) => TaskTypeManager(),
      child: MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showDialog<Map<String, dynamic>>(
                context: context,
                builder: (_) => dialog,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await interact();
    return result;
  }

  Future<void> pickReminder(WidgetTester tester, String label) async {
    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  testWidgets('caregiver assigns to all patients with a reminder',
      (tester) async {
    final result = await open(
      tester,
      const TaskFormDialog(isCaregiver: true, patients: _patients),
      () async {
        expect(find.text('Unknown'), findsOneWidget);
        await tester.enterText(
            find.widgetWithText(TextFormField, 'Task Title'), 'Stretch');
        await tester.tap(find.text('Assign to All Patients'));
        await tester.pump();
        // Untick one patient, then tick it again.
        await tester.tap(find.text('Pat One'));
        await tester.pump();
        await tester.tap(find.text('Pat One'));
        await tester.pump();
        await pickReminder(tester, '1 hour before');
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
      },
    );
    final tasks = result!['tasks'] as List<Task>;
    expect(tasks.map((t) => t.assignedPatientId), containsAll([1, 2]));
    expect(tasks.first.notifications, hasLength(1));
  });

  testWidgets('untick all, pick one patient and save a single task',
      (tester) async {
    final result = await open(
      tester,
      const TaskFormDialog(isCaregiver: true, patients: _patients),
      () async {
        await tester.enterText(
            find.widgetWithText(TextFormField, 'Task Title'), 'Walk');
        await tester.tap(find.text('Assign to All Patients'));
        await tester.pump();
        await tester.tap(find.text('Assign to All Patients'));
        await tester.pump();
        await tester.tap(find.text('Unknown'));
        await tester.pump();
        await pickReminder(tester, '5 minutes before');
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
      },
    );
    final tasks = result!['task'] as List<Task>;
    expect(tasks.single.assignedPatientId, 2);
  });

  testWidgets('editing a monthly task keeps its matching reminder',
      (tester) async {
    final date = DateTime(2026, 3, 15);
    final task = Task(
      id: 7,
      name: 'Refill',
      description: 'Pharmacy',
      date: date,
      timeOfDay: const TimeOfDay(hour: 10, minute: 0),
      assignedPatientId: 1,
      frequency: 'monthly',
      interval: 1,
      count: 3,
      taskType: 'medication',
      notifications: [
        ScheduledNotification(
          receiverId: 1,
          title: 'Reminder',
          body: 'b',
          scheduledTime: DateTime(2026, 3, 15, 9, 45),
        ),
        ScheduledNotification(
          receiverId: 1,
          title: 'Later',
          body: 'b',
          scheduledTime: DateTime(2026, 3, 15, 9, 59),
        ),
      ],
    );
    final result = await open(
      tester,
      TaskFormDialog(
        isCaregiver: true,
        patients: _patients,
        initialTask: task,
        seriesAnchorDate: date,
      ),
      () async {
        expect(find.text('Edit Task'), findsOneWidget);
        expect(find.text('15 minutes before'), findsOneWidget);
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
      },
    );
    final saved = (result!['task'] as List<Task>).single;
    expect(saved.frequency, 'monthly');
    expect(saved.notifications, hasLength(1));
  });

  testWidgets('patient edit with an unmatched reminder falls back to None',
      (tester) async {
    final task = Task(
      id: 8,
      name: 'Daily walk',
      description: '',
      date: DateTime(2026, 3, 15),
      frequency: 'daily',
      count: 2,
      notifications: [
        ScheduledNotification(
          receiverId: 1,
          title: 'Odd',
          body: 'b',
          scheduledTime: DateTime(2026, 3, 14, 7, 13),
        ),
      ],
    );
    final result = await open(
      tester,
      TaskFormDialog(
        isCaregiver: false,
        patients: const [],
        initialTask: task,
        defaultPatientId: 1,
      ),
      () async {
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
      },
    );
    expect((result!['task'] as List<Task>).single.notifications, isEmpty);
  });
}
