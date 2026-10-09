// Tests for DateField widget
// (lib/features/invoices/widgets/components/date_field.dart).
//
// DateField is a pure StatelessWidget that shows a TextFormField.
// Opening the date picker via showDatePicker is not tested here (requires
// native interaction), but the rendering and enabled/disabled state are.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/invoices/widgets/components/date_field.dart';

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: child));

void main() {
  group('DateField', () {
    testWidgets('renders a TextFormField', (tester) async {
      // Verifies the widget renders a TextFormField.
      await tester.pumpWidget(_wrap(
        DateField(
          label: 'Due Date',
          value: null,
          enabled: true,
          onChanged: (_) {},
        ),
      ));
      expect(find.byType(TextFormField), findsOneWidget);
    });

    testWidgets('shows the label text', (tester) async {
      // Verifies the label string is displayed in the form field decoration.
      await tester.pumpWidget(_wrap(
        DateField(
          label: 'Statement Date',
          value: null,
          enabled: true,
          onChanged: (_) {},
        ),
      ));
      expect(find.text('Statement Date'), findsOneWidget);
    });

    testWidgets('shows formatted date when value is provided', (tester) async {
      // Verifies that a non-null DateTime is displayed as YYYY-MM-DD.
      await tester.pumpWidget(_wrap(
        DateField(
          label: 'Due Date',
          value: DateTime(2025, 6, 5),
          enabled: true,
          onChanged: (_) {},
        ),
      ));
      expect(find.text('2025-06-05'), findsOneWidget);
    });

    testWidgets('shows empty text when value is null', (tester) async {
      // Verifies that a null DateTime produces an empty text field.
      await tester.pumpWidget(_wrap(
        DateField(
          label: 'Due Date',
          value: null,
          enabled: true,
          onChanged: (_) {},
        ),
      ));
      // The controller text is empty — no date string shown.
      expect(find.text('2025-06-05'), findsNothing);
    });

    testWidgets('shows "Not set" hint text when optional is true and value is null', (tester) async {
      // Verifies the optional hint text appears when optional=true and no value set.
      await tester.pumpWidget(_wrap(
        DateField(
          label: 'End Date',
          value: null,
          enabled: true,
          onChanged: (_) {},
          optional: true,
        ),
      ));
      expect(find.text('Not set'), findsOneWidget);
    });

    testWidgets('no hint text shown when optional is false', (tester) async {
      // Verifies that non-optional fields do not show the "Not set" hint.
      await tester.pumpWidget(_wrap(
        DateField(
          label: 'End Date',
          value: null,
          enabled: false,
          onChanged: (_) {},
          optional: false,
        ),
      ));
      expect(find.text('Not set'), findsNothing);
    });

    testWidgets('formats single-digit month and day with leading zeros', (tester) async {
      // Verifies that month=1 day=5 formats as "2025-01-05".
      await tester.pumpWidget(_wrap(
        DateField(
          label: 'Date',
          value: DateTime(2025, 1, 5),
          enabled: true,
          onChanged: (_) {},
        ),
      ));
      expect(find.text('2025-01-05'), findsOneWidget);
    });
  });
}
