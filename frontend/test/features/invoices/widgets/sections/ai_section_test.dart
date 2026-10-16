// Tests for AiSection widget
// (lib/features/invoices/widgets/sections/ai_section.dart).
//
// AiSection is a pure StatelessWidget — no platform channels or network I/O.
// Uses InvoiceFactories.empty() to create test Invoice instances.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/invoices/models/invoice_models.dart';
import 'package:care_connect_app/features/invoices/widgets/sections/ai_section.dart';

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: child));

void main() {
  group('AiSection', () {
    testWidgets('shows "No AI summary available." when aiSummary is null', (tester) async {
      // Verifies the default message when the Invoice has no AI summary.
      final invoice = InvoiceFactories.empty();
      await tester.pumpWidget(_wrap(AiSection(value: invoice)));
      expect(find.text('No AI summary available.'), findsOneWidget);
    });

    testWidgets('shows the aiSummary text when present', (tester) async {
      // Verifies the actual AI summary string is displayed.
      final invoice = InvoiceFactories.empty().copyWith(
        aiSummary: 'Patient owes \$150 after insurance adjustments.',
      );
      await tester.pumpWidget(_wrap(AiSection(value: invoice)));
      expect(
        find.text('Patient owes \$150 after insurance adjustments.'),
        findsOneWidget,
      );
    });

    testWidgets('shows "AI Summary" tile title', (tester) async {
      // Verifies the card tile always has the "AI Summary" label.
      final invoice = InvoiceFactories.empty();
      await tester.pumpWidget(_wrap(AiSection(value: invoice)));
      expect(find.text('AI Summary'), findsOneWidget);
    });

    testWidgets('shows lightbulb icon', (tester) async {
      // Verifies the leading icon for the AI Summary tile.
      final invoice = InvoiceFactories.empty();
      await tester.pumpWidget(_wrap(AiSection(value: invoice)));
      expect(find.byIcon(Icons.lightbulb_outline), findsOneWidget);
    });

    testWidgets('shows Recommended Actions section when actions are present', (tester) async {
      // Verifies that recommended actions appear when the list is non-empty.
      final invoice = InvoiceFactories.empty().copyWith(
        recommendedActions: ['Schedule follow-up', 'Verify insurance'],
      );
      await tester.pumpWidget(_wrap(AiSection(value: invoice)));
      expect(find.text('Recommended Actions'), findsOneWidget);
      expect(find.text('Schedule follow-up'), findsOneWidget);
      expect(find.text('Verify insurance'), findsOneWidget);
    });

    testWidgets('does not show Recommended Actions when list is empty', (tester) async {
      // Verifies that the actions card is hidden when recommendedActions is empty.
      final invoice = InvoiceFactories.empty();
      await tester.pumpWidget(_wrap(AiSection(value: invoice)));
      expect(find.text('Recommended Actions'), findsNothing);
    });
  });
}
