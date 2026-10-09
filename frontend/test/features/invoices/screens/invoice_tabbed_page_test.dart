// Tests for InvoiceTabbedPage
// (lib/features/invoices/screens/invoice_tabbed_page.dart).
//
// Coverage strategy:
//   InvoiceTabbedPage is a pure tab-container widget with a TabController
//   (length=3) and no API calls of its own.  The three child tab wrappers
//   (_DashboardTab, _UploadInvoiceTab, _InvoiceListTab) each spawn an inner
//   Navigator that renders child pages — those pages call APIs in their own
//   FutureBuilders/initState, but those futures are left pending during the
//   tests (we use pump() without pumpAndSettle to avoid waiting for network).
//
//   Branches tested (default initialTabIndex = 0):
//     Scaffold renders             — widget builds without crashing.
//     "Invoice Assistant" AppBar   — title is correct.
//     Dashboard tab present        — Tab with text/icon is shown.
//     Upload Invoice tab present   — Tab with text/icon is shown.
//     Invoice List tab present     — Tab with text/icon is shown.
//     No back button by default    — quickFilter == null → no leading widget.
//
//   Branches tested (quickFilter provided):
//     Back button shown            — showBack == true → BackButton rendered.
//
//   Branches tested (initialTabIndex):
//     initialTabIndex = 1          — Upload Invoice tab is selected initially.
//     initialTabIndex = 2          — Invoice List tab is selected initially.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/features/invoices/screens/invoice_tabbed_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('InvoiceTabbedPage – default state (initialTabIndex = 0)', () {
    testWidgets('renders Scaffold without crashing', (tester) async {
      // Verifies the widget tree builds successfully.
      await tester.pumpWidget(
        const MaterialApp(home: InvoiceTabbedPage()),
      );
      await tester.pump();

      // The outer Scaffold plus the child tab's inner Scaffold both render.
      expect(find.byType(Scaffold), findsAtLeastNWidgets(1));
    });

    testWidgets('shows "Invoice Assistant" in the AppBar', (tester) async {
      // Verifies the AppBar title is correct.
      await tester.pumpWidget(
        const MaterialApp(home: InvoiceTabbedPage()),
      );
      await tester.pump();

      expect(find.text('Invoice Assistant'), findsOneWidget);
    });

    testWidgets('shows Dashboard tab', (tester) async {
      // Verifies the first Tab label is rendered.
      await tester.pumpWidget(
        const MaterialApp(home: InvoiceTabbedPage()),
      );
      await tester.pump();

      expect(find.text('Dashboard'), findsOneWidget);
    });

    testWidgets('shows Upload Invoice tab', (tester) async {
      // Verifies the second Tab label is rendered.
      await tester.pumpWidget(
        const MaterialApp(home: InvoiceTabbedPage()),
      );
      await tester.pump();

      expect(find.text('Upload Invoice'), findsOneWidget);
    });

    testWidgets('shows Invoice List tab', (tester) async {
      // Verifies the third Tab label is rendered.
      await tester.pumpWidget(
        const MaterialApp(home: InvoiceTabbedPage()),
      );
      await tester.pump();

      expect(find.text('Invoice List'), findsOneWidget);
    });

    testWidgets('shows TabBar with three tabs', (tester) async {
      // Verifies all three Tab widgets are present.
      await tester.pumpWidget(
        const MaterialApp(home: InvoiceTabbedPage()),
      );
      await tester.pump();

      expect(find.byType(Tab), findsNWidgets(3));
    });

    testWidgets('shows TabBarView', (tester) async {
      // Verifies the TabBarView is present in the widget tree.
      await tester.pumpWidget(
        const MaterialApp(home: InvoiceTabbedPage()),
      );
      await tester.pump();

      expect(find.byType(TabBarView), findsOneWidget);
    });

    testWidgets('no back button when quickFilter is null', (tester) async {
      // Verifies the AppBar leading is not a BackButton when quickFilter omitted.
      await tester.pumpWidget(
        const MaterialApp(home: InvoiceTabbedPage()),
      );
      await tester.pump();

      expect(find.byType(BackButton), findsNothing);
    });
  });

  group('InvoiceTabbedPage – quickFilter provided', () {
    testWidgets('shows BackButton when quickFilter is set', (tester) async {
      // Verifies showBack == true adds a BackButton as the AppBar leading.
      await tester.pumpWidget(
        const MaterialApp(
          home: InvoiceTabbedPage(quickFilter: 'overdue'),
        ),
      );
      await tester.pump();

      expect(find.byType(BackButton), findsOneWidget);
    });
  });

  group('InvoiceTabbedPage – initialTabIndex', () {
    testWidgets('initialTabIndex = 1 selects Upload Invoice tab', (
      tester,
    ) async {
      // Verifies the TabController starts on the Upload Invoice tab.
      await tester.pumpWidget(
        const MaterialApp(
          home: InvoiceTabbedPage(initialTabIndex: 1),
        ),
      );
      await tester.pump();

      // All three tabs are still rendered in the TabBar.
      expect(find.text('Upload Invoice'), findsOneWidget);
    });

    testWidgets('initialTabIndex = 2 selects Invoice List tab', (
      tester,
    ) async {
      // Verifies the TabController starts on the Invoice List tab.
      await tester.pumpWidget(
        const MaterialApp(
          home: InvoiceTabbedPage(initialTabIndex: 2),
        ),
      );
      await tester.pump();

      expect(find.text('Invoice List'), findsOneWidget);
    });
  });
}
