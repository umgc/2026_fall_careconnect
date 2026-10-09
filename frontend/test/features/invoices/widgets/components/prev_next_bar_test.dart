// Tests for PrevNextBar widget
// (lib/features/invoices/widgets/components/prev_next_bar.dart).
//
// PrevNextBar is a pure StatelessWidget — no platform channels or network I/O.
// Tests cover: Prev/Next buttons present, Save vs Next label, enabled/disabled
// Prev button, and tap callbacks.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/invoices/widgets/components/prev_next_bar.dart';

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: child));

void main() {
  group('PrevNextBar', () {
    testWidgets('shows Prev and Next buttons when not on last step', (tester) async {
      // Verifies that both "Prev" and "Next" are visible.
      await tester.pumpWidget(_wrap(
        PrevNextBar(
          canPrev: true,
          isLast: false,
          onPrev: () {},
          onNextOrSave: () {},
        ),
      ));
      expect(find.text('Prev'), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);
    });

    testWidgets('shows Save instead of Next when isLast is true', (tester) async {
      // Verifies that the label changes to "Save" on the last step.
      await tester.pumpWidget(_wrap(
        PrevNextBar(
          canPrev: true,
          isLast: true,
          onPrev: () {},
          onNextOrSave: () {},
        ),
      ));
      expect(find.text('Save'), findsOneWidget);
      expect(find.text('Next'), findsNothing);
    });

    testWidgets('Prev button is disabled when canPrev is false', (tester) async {
      // Verifies that canPrev=false makes the Prev button non-interactive.
      await tester.pumpWidget(_wrap(
        PrevNextBar(
          canPrev: false,
          isLast: false,
          onPrev: () {},
          onNextOrSave: () {},
        ),
      ));

      // The OutlinedButton renders with onPressed = null when canPrev = false.
      final prevButton = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Prev'),
      );
      expect(prevButton.onPressed, isNull);
    });

    testWidgets('Prev button is enabled when canPrev is true', (tester) async {
      // Verifies that canPrev=true enables the Prev button.
      await tester.pumpWidget(_wrap(
        PrevNextBar(
          canPrev: true,
          isLast: false,
          onPrev: () {},
          onNextOrSave: () {},
        ),
      ));

      final prevButton = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Prev'),
      );
      expect(prevButton.onPressed, isNotNull);
    });

    testWidgets('tapping Next calls onNextOrSave', (tester) async {
      // Verifies the Next button triggers the onNextOrSave callback.
      var called = false;
      await tester.pumpWidget(_wrap(
        PrevNextBar(
          canPrev: true,
          isLast: false,
          onPrev: () {},
          onNextOrSave: () => called = true,
        ),
      ));
      await tester.tap(find.text('Next'));
      await tester.pump();
      expect(called, isTrue);
    });

    testWidgets('tapping Prev calls onPrev when enabled', (tester) async {
      // Verifies the Prev button triggers the onPrev callback.
      var called = false;
      await tester.pumpWidget(_wrap(
        PrevNextBar(
          canPrev: true,
          isLast: false,
          onPrev: () => called = true,
          onNextOrSave: () {},
        ),
      ));
      await tester.tap(find.text('Prev'));
      await tester.pump();
      expect(called, isTrue);
    });

    testWidgets('shows chevron_right icon for Next', (tester) async {
      // Verifies the Next step shows chevron_right icon.
      await tester.pumpWidget(_wrap(
        PrevNextBar(
          canPrev: true,
          isLast: false,
          onPrev: () {},
          onNextOrSave: () {},
        ),
      ));
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });

    testWidgets('shows save icon for Save (last step)', (tester) async {
      // Verifies the last step shows the save icon.
      await tester.pumpWidget(_wrap(
        PrevNextBar(
          canPrev: true,
          isLast: true,
          onPrev: () {},
          onNextOrSave: () {},
        ),
      ));
      expect(find.byIcon(Icons.save), findsOneWidget);
    });
  });
}
