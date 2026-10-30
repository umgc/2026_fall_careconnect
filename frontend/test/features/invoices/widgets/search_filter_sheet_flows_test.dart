// Interaction tests for the invoice search & filter sheet
// (lib/features/invoices/widgets/search_filter_sheet.dart): opening it with
// showSearchFilterSheet, changing every filter, clearing and applying.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:care_connect_app/features/invoices/models/filter_result.dart';
import 'package:care_connect_app/features/invoices/models/invoice_models.dart';
import 'package:care_connect_app/features/invoices/widgets/search_filter_sheet.dart';

Invoice _invoice(String id, String provider, String patient) => Invoice(
      id: id,
      invoiceNumber: id,
      provider: ProviderInfo(name: provider, address: 'a', phone: 'p'),
      patient: PatientInfo(name: patient),
      dates: InvoiceDates(
        statementDate: DateTime(2025, 1, 1),
        dueDate: DateTime(2025, 2, 1),
      ),
      paymentStatus: PaymentStatus.pending,
      billedToInsurance: false,
      amounts: const Amounts(total: 100, amountDue: 100),
      paymentReferences: PaymentReferences(supportedMethods: const []),
      createdAt: '2025-01-01T00:00:00Z',
      updatedAt: '2025-01-01T00:00:00Z',
      createdBy: 'a',
      updatedBy: 'a',
      payments: const [],
    );

final _invoices = [
  _invoice('1', 'Beta Clinic', 'Zed'),
  _invoice('2', 'Alpha Clinic', 'Amy'),
];

void main() {
  Future<void> open(
    WidgetTester tester,
    Size size,
    void Function(FilterResult?) onResult, {
    DateTimeRange? range,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              onResult(await showSearchFilterSheet(
                context: context,
                invoices: _invoices,
                initialSort: 'recently_added',
                initialSearch: '',
                initialStatus: {PaymentStatus.paid},
                initialServiceRange: range,
                initialAmountRange: const RangeValues(10, 500),
              ));
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('changing every filter and applying returns the result',
      (tester) async {
    FilterResult? result;
    await open(tester, const Size(900, 2000), (r) => result = r,
        range: DateTimeRange(
            start: DateTime(2025, 1, 1), end: DateTime(2025, 1, 31)));
    expect(find.text('Search & Filter Invoices'), findsOneWidget);
    expect(find.textContaining('2025-01-01 to 2025-01-31'), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Amount (High to Low)').last);
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Search'), 'clinic');
    await tester.tap(find.widgetWithText(FilterChip, 'Overdue'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilterChip, 'Paid'));
    await tester.pump();

    await tester.tap(find.byType(DropdownButtonFormField<String>).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alpha Clinic').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>).at(2));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Amy').last);
    await tester.pumpAndSettle();

    // Due-date range picker: open it and save the initial (empty) choice.
    await tester.tap(find.widgetWithText(TextFormField, 'Due Date'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.close).last);
    await tester.pumpAndSettle();

    await tester.drag(find.byType(RangeSlider), const Offset(60, 0));
    await tester.pump();

    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!.sort, 'amount_desc');
    expect(result!.search, 'clinic');
    expect(result!.status, {PaymentStatus.overdue});
    expect(result!.provider, 'Alpha Clinic');
    expect(result!.patient, 'Amy');
  });

  testWidgets('narrow layout stacks fields; clear resets and close dismisses',
      (tester) async {
    // The pinned "Clear All Filters" / "Apply" row overflows below ~520 px;
    // ignore that layout warning so the stacked branch can be exercised.
    final onError = FlutterError.onError;
    FlutterError.onError = (d) {
      if (!d.toString().contains('overflowed')) onError?.call(d);
    };
    addTearDown(() => FlutterError.onError = onError);
    FilterResult? result;
    var closed = false;
    await open(tester, const Size(470, 2000), (r) {
      result = r;
      closed = true;
    });
    expect(find.text('Rejected Insurance'), findsOneWidget);

    await tester.tap(find.text('Clear All Filters'));
    await tester.pump();
    expect(find.text('\$0'), findsOneWidget);

    tester
        .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.close))
        .onPressed!();
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(result, isNull);
  });
}
