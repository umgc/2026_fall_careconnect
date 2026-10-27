// Page-title tests for OverdueBlock (lib/features/invoices/screens/dashboard/widgets/overdue_block.dart).
// Setup copied from overdue_block_test.dart; adds the page-title
// checks (WCAG 2.4.2) for this PR's TitledMaterialPageRoute changes.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/invoices/screens/dashboard/widgets/overdue_block.dart';
import 'package:care_connect_app/features/invoices/models/invoice_models.dart';
import '../../../../../helpers/titled_route_probe.dart';

// Minimal Invoice builder for tests
Invoice _makeInvoice({
  required String id,
  required String providerName,
  required PaymentStatus status,
  required DateTime dueDate,
  double amountDue = 100.0,
}) {
  final now = DateTime.now();
  return Invoice(
    id: id,
    invoiceNumber: 'INV-$id',
    provider: ProviderInfo(name: providerName, address: 'Addr', phone: '555'),
    patient: const PatientInfo(name: 'Patient'),
    dates: InvoiceDates(
      statementDate: now,
      dueDate: dueDate,
    ),
    paymentStatus: status,
    billedToInsurance: false,
    amounts: Amounts(amountDue: amountDue),
    paymentReferences: PaymentReferences(supportedMethods: const []),
    createdAt: now.toIso8601String(),
    updatedAt: now.toIso8601String(),
    createdBy: 'test',
    updatedBy: 'test',
    payments: const [],
  );
}

final _pastDate = DateTime.now().subtract(const Duration(days: 10));
final _futureDate = DateTime.now().add(const Duration(days: 10));

Widget _wrap(Widget child) => MaterialApp(
      navigatorObservers: [probe],
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

TitledRouteProbe probe = TitledRouteProbe();

void main() {
  setUp(() => probe = TitledRouteProbe());

  testWidgets(
      '"View" on an overdue invoice opens a page titled '
      '"Invoice Details"', (tester) async {
    final invoices = [
      _makeInvoice(
        id: '1',
        providerName: 'City Clinic',
        status: PaymentStatus.overdue,
        dueDate: DateTime.now().subtract(const Duration(days: 5)),
      ),
    ];
    await tester
        .pumpWidget(_wrap(OverdueBlock(invoices: invoices, loading: false)));
    await tester.pump();
    expect(await probe.tapAndReadTitle(tester, find.text('View').first),
        'Invoice Details');
  });
}
