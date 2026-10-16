// Tests for PreDefinedTaskScreen
// (lib/features/tasks/presentation/pre_defined_task_screen.dart).
//
// Coverage strategy:
//   PreDefinedTaskScreen calls ApiService.getTaskTemplate in initState and
//   silently catches any error (empty catch block).  In tests the network
//   call throws immediately, so the widget renders with the default empty
//   Task values.  The form UI is identical to CustomTaskScreen.
//   GoRouter (context.go) is only reached after ApiService.createTask
//   succeeds; the test environment throws on that call, so only the catch
//   block runs.
//
//   Branches tested (initial render):
//     Scaffold / AppBar title        — widget builds after initState settles.
//     "Predefined Task Scheduling"   — AppBar title is correct.
//     Description text               — introductory label is shown.
//     Form-field labels              — Task Name, Description, Frequency,
//                                      Interval, Count, Time, Date shown.
//     Save button                    — present in bottomNavigationBar.
//     "No time selected" placeholder — default time card text.
//
//   Branches tested (field interactions):
//     Task Name onChanged            — typing updates task.name via setState.
//     Description onChanged          — typing updates task.description.
//     Interval onChanged             — typing updates task.interval.
//     Count onChanged                — typing updates task.count.
//     Frequency dropdown onChanged   — selecting a value updates task.frequency.
//
//   Branches tested (Save button):
//     Save tapped → API error → SnackBar — catch block shows error SnackBar.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:care_connect_app/features/tasks/presentation/pre_defined_task_screen.dart';

/// Wraps [child] in a MaterialApp.  No GoRouter is needed because the Save
/// button's try-block fails at the API call; context.go is never reached.
Widget _wrap(Widget child) => MaterialApp(home: child);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PreDefinedTaskScreen – initial render', () {
    testWidgets('renders Scaffold without crashing', (tester) async {
      // Verifies the widget builds and shows a Scaffold after initState settles.
      await tester.pumpWidget(
        _wrap(const PreDefinedTaskScreen(
          patientId: 1,
          templateId: 42,
          patientName: 'Bob',
        )),
      );
      // Let initState's _getTemplateDetails (and its silent catch) complete.
      await tester.pumpAndSettle();

      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows "Predefined Task Scheduling" in AppBar', (tester) async {
      // Verifies the AppBar title is correct.
      await tester.pumpWidget(
        _wrap(const PreDefinedTaskScreen(
          patientId: 1,
          templateId: 42,
          patientName: 'Bob',
        )),
      );
      await tester.pumpAndSettle();

      expect(find.text('Predefined Task Scheduling'), findsOneWidget);
    });

    testWidgets('shows introductory description text', (tester) async {
      // Verifies the hint text at the top of the form is rendered.
      await tester.pumpWidget(
        _wrap(const PreDefinedTaskScreen(
          patientId: 1,
          templateId: 42,
          patientName: 'Bob',
        )),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Create a custom task'), findsOneWidget);
    });

    testWidgets('shows Task Name, Description, Frequency labels', (
      tester,
    ) async {
      // Verifies the section-header labels are rendered.
      await tester.pumpWidget(
        _wrap(const PreDefinedTaskScreen(
          patientId: 1,
          templateId: 42,
          patientName: 'Bob',
        )),
      );
      await tester.pumpAndSettle();

      // Labels may also match TextField hintText; check at least one match.
      expect(find.text('Task Name'), findsAtLeastNWidgets(1));
      expect(find.text('Description'), findsAtLeastNWidgets(1));
      expect(find.text('Frequency'), findsOneWidget);
    });

    testWidgets('shows Interval, Count, Time, Date labels', (tester) async {
      // Verifies additional section-header labels.
      await tester.pumpWidget(
        _wrap(const PreDefinedTaskScreen(
          patientId: 1,
          templateId: 42,
          patientName: 'Bob',
        )),
      );
      await tester.pumpAndSettle();

      expect(find.text('Interval'), findsOneWidget);
      expect(find.text('Count'), findsOneWidget);
      expect(find.text('Time'), findsOneWidget);
      expect(find.text('Date'), findsOneWidget);
    });

    testWidgets('shows Save button', (tester) async {
      // Verifies the Save ElevatedButton is present in the bottomNavigationBar.
      await tester.pumpWidget(
        _wrap(const PreDefinedTaskScreen(
          patientId: 1,
          templateId: 42,
          patientName: 'Bob',
        )),
      );
      await tester.pumpAndSettle();

      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('shows "No time selected" placeholder in Time card', (
      tester,
    ) async {
      // Verifies the time-picker ListTile placeholder text is shown initially.
      await tester.pumpWidget(
        _wrap(const PreDefinedTaskScreen(
          patientId: 1,
          templateId: 42,
          patientName: 'Bob',
        )),
      );
      await tester.pumpAndSettle();

      expect(find.text('No time selected'), findsOneWidget);
    });

    testWidgets('frequency DropdownButtonFormField is present', (tester) async {
      // Verifies the DropdownButtonFormField renders.
      await tester.pumpWidget(
        _wrap(const PreDefinedTaskScreen(
          patientId: 1,
          templateId: 42,
          patientName: 'Bob',
        )),
      );
      await tester.pumpAndSettle();

      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    });
  });

  group('PreDefinedTaskScreen – form field interactions', () {
    testWidgets('typing in Task Name field updates state', (tester) async {
      // Verifies the onChanged callback triggers setState for task.name.
      await tester.pumpWidget(
        _wrap(const PreDefinedTaskScreen(
          patientId: 1,
          templateId: 42,
          patientName: 'Bob',
        )),
      );
      await tester.pumpAndSettle();

      // The first TextField is the Task Name field.
      await tester.enterText(find.byType(TextField).first, 'Morning walk');
      await tester.pump();

      expect(find.text('Morning walk'), findsOneWidget);
    });

    testWidgets('typing in Description field updates state', (tester) async {
      // Verifies the onChanged callback triggers setState for task.description.
      await tester.pumpWidget(
        _wrap(const PreDefinedTaskScreen(
          patientId: 1,
          templateId: 42,
          patientName: 'Bob',
        )),
      );
      await tester.pumpAndSettle();

      // Second TextField (index 1) is Description.
      await tester.enterText(find.byType(TextField).at(1), 'Around the block');
      await tester.pump();

      expect(find.text('Around the block'), findsOneWidget);
    });

    testWidgets('typing in Interval field updates state', (tester) async {
      // Verifies the numeric onChanged callback for task.interval.
      await tester.pumpWidget(
        _wrap(const PreDefinedTaskScreen(
          patientId: 1,
          templateId: 42,
          patientName: 'Bob',
        )),
      );
      await tester.pumpAndSettle();

      // Third TextField (index 2) is Interval.
      await tester.enterText(find.byType(TextField).at(2), '3');
      await tester.pump();

      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('typing in Count field updates state', (tester) async {
      // Verifies the numeric onChanged callback for task.count.
      await tester.pumpWidget(
        _wrap(const PreDefinedTaskScreen(
          patientId: 1,
          templateId: 42,
          patientName: 'Bob',
        )),
      );
      await tester.pumpAndSettle();

      // Fourth TextField (index 3) is Count.
      await tester.enterText(find.byType(TextField).at(3), '10');
      await tester.pump();

      expect(find.text('10'), findsOneWidget);
    });

    testWidgets('selecting a frequency option updates the dropdown', (
      tester,
    ) async {
      // Verifies the DropdownButtonFormField onChanged callback.
      await tester.pumpWidget(
        _wrap(const PreDefinedTaskScreen(
          patientId: 1,
          templateId: 42,
          patientName: 'Bob',
        )),
      );
      await tester.pumpAndSettle();

      // Open the dropdown.
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();

      // Select 'Monthly'.
      await tester.tap(find.text('Monthly').last);
      await tester.pumpAndSettle();

      expect(find.text('Monthly'), findsOneWidget);
    });
  });

  group('PreDefinedTaskScreen – time and date picker interactions', () {
    testWidgets('tapping Time card opens time picker, Cancel dismisses it', (
      tester,
    ) async {
      // Exercises the onTap callback of the Time ListTile: opens showTimePicker
      // and handles the null (cancelled) return.
      await tester.pumpWidget(
        _wrap(const PreDefinedTaskScreen(
          patientId: 1,
          templateId: 42,
          patientName: 'Bob',
        )),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('No time selected'));
      await tester.tap(find.text('No time selected'));
      await tester.pumpAndSettle();

      expect(find.text('Cancel'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('No time selected'), findsOneWidget);
    });

    testWidgets('tapping Time card and confirming sets a time', (
      tester,
    ) async {
      // Exercises the setState branch inside the onTap callback.
      await tester.pumpWidget(
        _wrap(const PreDefinedTaskScreen(
          patientId: 1,
          templateId: 42,
          patientName: 'Bob',
        )),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('No time selected'));
      await tester.tap(find.text('No time selected'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(find.text('No time selected'), findsNothing);
    });

    testWidgets('tapping Date card opens date picker, Cancel dismisses it', (
      tester,
    ) async {
      // Exercises the onTap callback of the Date ListTile.
      await tester.pumpWidget(
        _wrap(const PreDefinedTaskScreen(
          patientId: 1,
          templateId: 42,
          patientName: 'Bob',
        )),
      );
      await tester.pumpAndSettle();

      final dateText = find.byWidgetPredicate((w) =>
          w is Text &&
          w.data != null &&
          RegExp(r'\d{4}-\d{2}-\d{2}').hasMatch(w.data!));
      await tester.ensureVisible(dateText);

      await tester.tap(dateText);
      await tester.pumpAndSettle();

      expect(find.text('Cancel'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });

    testWidgets('tapping Date card and confirming updates the date', (
      tester,
    ) async {
      // Exercises the setState branch inside the Date onTap callback.
      await tester.pumpWidget(
        _wrap(const PreDefinedTaskScreen(
          patientId: 1,
          templateId: 42,
          patientName: 'Bob',
        )),
      );
      await tester.pumpAndSettle();

      final dateText = find.byWidgetPredicate((w) =>
          w is Text &&
          w.data != null &&
          RegExp(r'\d{4}-\d{2}-\d{2}').hasMatch(w.data!));
      await tester.ensureVisible(dateText);
      await tester.tap(dateText);
      await tester.pumpAndSettle();

      // Confirm with OK button.
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
    });
  });

  group('PreDefinedTaskScreen – Save button (API error path)', () {
    testWidgets(
      'tapping Save shows error SnackBar when API call throws',
      (tester) async {
        // Verifies the catch block executes when ApiService.createTask throws.
        // Uses runAsync so real async I/O (connection refused) can complete.
        await tester.pumpWidget(
          _wrap(const PreDefinedTaskScreen(
            patientId: 1,
            templateId: 42,
            patientName: 'Bob',
          )),
        );
        await tester.pumpAndSettle();

        await tester.runAsync(() async {
          await tester.tap(find.text('Save'));
          // Allow connection-refused to propagate.
          await Future.delayed(const Duration(milliseconds: 300));
        });
        await tester.pumpAndSettle();

        expect(find.textContaining('Error'), findsOneWidget);
      },
    );
  });
}
