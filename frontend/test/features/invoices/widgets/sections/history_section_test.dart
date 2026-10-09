// Tests for HistorySection widget
// (lib/features/invoices/widgets/sections/history_section.dart).
//
// HistorySection is a pure StatelessWidget — no platform channels or network I/O.
// Uses InvoiceFactories.empty() and HistoryEntry to create test data.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/invoices/models/invoice_models.dart';
import 'package:care_connect_app/features/invoices/widgets/sections/history_section.dart';

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: child));

HistoryEntry _entry({
  int version = 1,
  String timestamp = '2025-01-01T00:00:00.000',
  String changes = 'Change',
}) =>
    HistoryEntry(
      version: version,
      timestamp: timestamp,
      changes: changes,
      userId: 'user-1',
      action: 'UPDATE',
      details: 'Details',
    );

void main() {
  group('HistorySection', () {
    testWidgets('renders empty list view when no history', (tester) async {
      // Verifies the widget renders without crashing when history is empty.
      final invoice = InvoiceFactories.empty();
      await tester.pumpWidget(_wrap(HistorySection(value: invoice)));
      expect(find.byType(ListView), findsOneWidget);
    });

    testWidgets('shows one card per history entry', (tester) async {
      // Verifies that one card is rendered for each HistoryEntry.
      final invoice = InvoiceFactories.empty().copyWith(
        history: [
          _entry(version: 1, changes: 'Initial creation'),
          _entry(version: 2, changes: 'Updated amount'),
        ],
      );
      await tester.pumpWidget(_wrap(HistorySection(value: invoice)));
      // Each entry renders as a Card with a ListTile.
      expect(find.byType(Card), findsNWidgets(2));
    });

    testWidgets('shows changes text from history entries', (tester) async {
      // Verifies that the changes string for each entry is shown.
      final invoice = InvoiceFactories.empty().copyWith(
        history: [_entry(changes: 'Initial creation')],
      );
      await tester.pumpWidget(_wrap(HistorySection(value: invoice)));
      expect(find.text('Initial creation'), findsOneWidget);
    });

    testWidgets('shows version in tile title', (tester) async {
      // Verifies that "Version 1" appears in the tile title.
      final invoice = InvoiceFactories.empty().copyWith(
        history: [_entry(version: 1, timestamp: '2025-03-10T08:00:00.000', changes: 'Created')],
      );
      await tester.pumpWidget(_wrap(HistorySection(value: invoice)));
      expect(find.textContaining('Version 1'), findsOneWidget);
    });

    testWidgets('shows history icon', (tester) async {
      // Verifies the history icon is present for each entry.
      final invoice = InvoiceFactories.empty().copyWith(
        history: [_entry(changes: 'Init')],
      );
      await tester.pumpWidget(_wrap(HistorySection(value: invoice)));
      expect(find.byIcon(Icons.history), findsOneWidget);
    });

    testWidgets('shows ListTile for each entry', (tester) async {
      final invoice = InvoiceFactories.empty().copyWith(
        history: [_entry(version: 1), _entry(version: 2)],
      );
      await tester.pumpWidget(_wrap(HistorySection(value: invoice)));
      expect(find.byType(ListTile), findsNWidgets(2));
    });

    testWidgets('renders HistorySection widget type', (tester) async {
      final invoice = InvoiceFactories.empty();
      await tester.pumpWidget(_wrap(HistorySection(value: invoice)));
      expect(find.byType(HistorySection), findsOneWidget);
    });
  });
}
