// Additional coverage for TaskFormDialog
// (lib/features/tasks/presentation/widgets/task_form_dialog.dart):
// toggling the recurrence form and saving with a "1 day before" reminder.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/features/tasks/models/task_model.dart';
import 'package:care_connect_app/features/tasks/presentation/widgets/task_form_dialog.dart';
import 'package:care_connect_app/features/tasks/utils/task_type_manager.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('recurrence toggle and a 1 day reminder save a single task',
      (tester) async {
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
                builder: (_) => TaskFormDialog(
                  isCaregiver: false,
                  patients: const [],
                  defaultPatientId: 1,
                  initialDate: DateTime(2026, 5, 4),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Task Title'), 'Checkup');
    await tester.pump();

    // Turn recurrence on, then back off; the dialog tracks both changes.
    final recurring = find.text('Recurring Task');
    await tester.ensureVisible(recurring);
    await tester.tap(recurring);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<CheckboxListTile>(find.ancestor(
                of: recurring, matching: find.byType(CheckboxListTile)))
            .value,
        isTrue);
    await tester.tap(recurring);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('1 day before').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final tasks = result!['task'] as List<Task>;
    expect(tasks.single.name, 'Checkup');
    expect(tasks.single.notifications, hasLength(1));
  });
}
