// Tests for CustomTaskScreen
// (lib/features/tasks/presentation/custom_task_screen.dart).
//
// Coverage strategy:
//   CustomTaskScreen is a StatefulWidget that renders a pure form UI.
//   No API calls happen in build(); ApiService.createTask is only called
//   when the Save button is tapped.  In the test environment the network
//   call throws immediately (connection refused), so the catch block runs
//   and a SnackBar is shown — GoRouter is never reached.
//
//   Branches tested (initial render):
//     Scaffold / AppBar title         — widget builds without crashing.
//     Form-field labels               — Task Name, Description, Frequency,
//                                       Interval, Count, Time, Date shown.
//     Save button                     — present in bottomNavigationBar.
//
//   Branches tested (field interactions):
//     Task Name onChanged             — typing updates task.name via setState.
//     Description onChanged           — typing updates task.description.
//     Interval onChanged (numeric)    — typing updates task.interval.
//     Count onChanged (numeric)       — typing updates task.count.
//     Frequency dropdown onChanged    — selecting a value updates task.frequency.
//
//   Branches not tested:
//     Save tapped → API fails → SnackBar — HTTP async I/O does not resolve
//     inside pumpAndSettle in the test environment; left as-is per project rule.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:care_connect_app/features/tasks/presentation/custom_task_screen.dart';

/// Wraps [child] in a plain MaterialApp (no GoRouter needed — Save tap
/// exercises the catch branch which does not call context.go).
Widget _wrap(Widget child) => MaterialApp(home: child);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CustomTaskScreen – initial render', () {
    testWidgets('renders Scaffold without crashing', (tester) async {
      // Verifies the widget builds and shows a Scaffold.
      await tester.pumpWidget(
        _wrap(const CustomTaskScreen(patientId: 1, patientName: 'Alice')),
      );
      await tester.pump();

      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows "Custom Task Scheduling" in AppBar', (tester) async {
      // Verifies the AppBar title is correct.
      await tester.pumpWidget(
        _wrap(const CustomTaskScreen(patientId: 1, patientName: 'Alice')),
      );
      await tester.pump();

      expect(find.text('Custom Task Scheduling'), findsOneWidget);
    });

    testWidgets('shows introductory description text', (tester) async {
      // Verifies the hint text at the top of the form is rendered.
      await tester.pumpWidget(
        _wrap(const CustomTaskScreen(patientId: 1, patientName: 'Alice')),
      );
      await tester.pump();

      expect(find.textContaining('Create a custom task'), findsOneWidget);
    });

    testWidgets('shows Task Name, Description, Frequency labels', (
      tester,
    ) async {
      // Verifies the section-header labels are rendered.
      await tester.pumpWidget(
        _wrap(const CustomTaskScreen(patientId: 1, patientName: 'Alice')),
      );
      await tester.pump();

      // Labels may also match TextField hintText; check at least one match.
      expect(find.text('Task Name'), findsAtLeastNWidgets(1));
      expect(find.text('Description'), findsAtLeastNWidgets(1));
      expect(find.text('Frequency'), findsOneWidget);
    });

    testWidgets('shows Interval, Count, Time, Date labels', (tester) async {
      // Verifies additional section-header labels are rendered.
      await tester.pumpWidget(
        _wrap(const CustomTaskScreen(patientId: 1, patientName: 'Alice')),
      );
      await tester.pump();

      expect(find.text('Interval'), findsOneWidget);
      expect(find.text('Count'), findsOneWidget);
      expect(find.text('Time'), findsOneWidget);
      expect(find.text('Date'), findsOneWidget);
    });

    testWidgets('shows Save button', (tester) async {
      // Verifies the Save ElevatedButton is present in the bottomNavigationBar.
      await tester.pumpWidget(
        _wrap(const CustomTaskScreen(patientId: 1, patientName: 'Alice')),
      );
      await tester.pump();

      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('shows "No time selected" placeholder in Time card', (
      tester,
    ) async {
      // Verifies the time-picker ListTile placeholder text is shown initially.
      await tester.pumpWidget(
        _wrap(const CustomTaskScreen(patientId: 1, patientName: 'Alice')),
      );
      await tester.pump();

      expect(find.text('No time selected'), findsOneWidget);
    });

    testWidgets('frequency DropdownButtonFormField is present', (tester) async {
      // Verifies the DropdownButtonFormField renders.
      await tester.pumpWidget(
        _wrap(const CustomTaskScreen(patientId: 1, patientName: 'Alice')),
      );
      await tester.pump();

      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    });
  });

  group('CustomTaskScreen – form field interactions', () {
    testWidgets('typing in Task Name field updates state', (tester) async {
      // Verifies the onChanged callback triggers setState for task.name.
      await tester.pumpWidget(
        _wrap(const CustomTaskScreen(patientId: 1, patientName: 'Alice')),
      );
      await tester.pump();

      // The first TextField is the Task Name field.
      await tester.enterText(find.byType(TextField).first, 'Take medication');
      await tester.pump();

      expect(find.text('Take medication'), findsOneWidget);
    });

    testWidgets('typing in Description field updates state', (tester) async {
      // Verifies the onChanged callback triggers setState for task.description.
      await tester.pumpWidget(
        _wrap(const CustomTaskScreen(patientId: 1, patientName: 'Alice')),
      );
      await tester.pump();

      // Second TextField (index 1) is the Description field.
      await tester.enterText(find.byType(TextField).at(1), 'Morning pills');
      await tester.pump();

      expect(find.text('Morning pills'), findsOneWidget);
    });

    testWidgets('typing in Interval field updates state', (tester) async {
      // Verifies the numeric onChanged callback for task.interval.
      await tester.pumpWidget(
        _wrap(const CustomTaskScreen(patientId: 1, patientName: 'Alice')),
      );
      await tester.pump();

      // Third TextField (index 2) is Interval.
      await tester.enterText(find.byType(TextField).at(2), '2');
      await tester.pump();

      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('typing in Count field updates state', (tester) async {
      // Verifies the numeric onChanged callback for task.count.
      await tester.pumpWidget(
        _wrap(const CustomTaskScreen(patientId: 1, patientName: 'Alice')),
      );
      await tester.pump();

      // Fourth TextField (index 3) is Count.
      await tester.enterText(find.byType(TextField).at(3), '5');
      await tester.pump();

      expect(find.text('5'), findsOneWidget);
    });

    testWidgets('selecting a frequency option updates the dropdown', (
      tester,
    ) async {
      // Verifies the DropdownButtonFormField onChanged callback.
      await tester.pumpWidget(
        _wrap(const CustomTaskScreen(patientId: 1, patientName: 'Alice')),
      );
      await tester.pump();

      // Open the dropdown.
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();

      // Select 'Weekly'.
      await tester.tap(find.text('Weekly').last);
      await tester.pumpAndSettle();

      expect(find.text('Weekly'), findsOneWidget);
    });
  });

  group('CustomTaskScreen – time and date picker interactions', () {
    testWidgets('tapping Time card opens time picker, Cancel dismisses it', (
      tester,
    ) async {
      // Exercises the onTap callback of the Time ListTile: opens showTimePicker
      // and handles the null (cancelled) return.
      await tester.pumpWidget(
        _wrap(const CustomTaskScreen(patientId: 1, patientName: 'Alice')),
      );
      await tester.pump();

      // Scroll until the Time card is visible.
      await tester.ensureVisible(find.text('No time selected'));

      await tester.tap(find.text('No time selected'));
      await tester.pumpAndSettle();

      // Time picker dialog is open — dismiss with Cancel.
      expect(find.text('Cancel'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Time remains unset after Cancel.
      expect(find.text('No time selected'), findsOneWidget);
    });

    testWidgets('tapping Time card and confirming sets a time', (
      tester,
    ) async {
      // Exercises the onTap callback: opens showTimePicker and handles non-null
      // return via the setState branch.
      await tester.pumpWidget(
        _wrap(const CustomTaskScreen(patientId: 1, patientName: 'Alice')),
      );
      await tester.pump();

      await tester.ensureVisible(find.text('No time selected'));
      await tester.tap(find.text('No time selected'));
      await tester.pumpAndSettle();

      // Confirm the time picker — tap OK button.
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      // After confirmation the placeholder text is gone.
      expect(find.text('No time selected'), findsNothing);
    });

    testWidgets('tapping Date card opens date picker, Cancel dismisses it', (
      tester,
    ) async {
      // Exercises the onTap callback of the Date ListTile: opens showDatePicker
      // and handles the null (cancelled) return.
      await tester.pumpWidget(
        _wrap(const CustomTaskScreen(patientId: 1, patientName: 'Alice')),
      );
      await tester.pump();

      // The Date card shows the initial date (today's date).
      final dateText = find.byWidgetPredicate((w) =>
          w is Text &&
          w.data != null &&
          RegExp(r'\d{4}-\d{2}-\d{2}').hasMatch(w.data!));
      await tester.ensureVisible(dateText);

      await tester.tap(dateText);
      await tester.pumpAndSettle();

      // Date picker dialog is open — dismiss with Cancel.
      expect(find.text('Cancel'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  });
}
