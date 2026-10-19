// Tests for InvoiceDashboardPage
// (lib/features/invoices/screens/dashboard/invoice_dashboard_page.dart).
//
// InvoiceDashboardPage fetches invoices via FutureBuilder on construction.
// While loading (future pending), the grid renders KPI cards with loading=true
// and empty invoice data — KPI titles are always visible.
//
// Tests use pump() only (NOT pumpAndSettle) to stay in the loading state.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/invoices/screens/dashboard/invoice_dashboard_page.dart';

Widget _wrap() => const MaterialApp(home: InvoiceDashboardPage());

void main() {
  group('InvoiceDashboardPage – initial loading state', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(InvoiceDashboardPage), findsOneWidget);
    });

    testWidgets('shows a Scaffold', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows "Total Invoices" KPI card title', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Total Invoices'), findsOneWidget);
    });

    testWidgets('shows "Total Amount" KPI card title', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Total Amount'), findsOneWidget);
    });

    testWidgets('shows "Pending Payments" KPI card title', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Pending Payments'), findsOneWidget);
    });

    testWidgets('shows "Active medical invoices" subtitle', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Active medical invoices'), findsOneWidget);
    });

    testWidgets('shows Text widgets for KPI titles', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(Text), findsWidgets);
    });

    testWidgets('shows Column layout', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(Column), findsWidgets);
    });
  });
}
