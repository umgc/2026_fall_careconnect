// Page-title tests for RecentActivityCard (lib/features/invoices/screens/dashboard/widgets/activity_and_charts.dart).
// Setup copied from activity_and_charts_test.dart; adds the page-title
// checks (WCAG 2.4.2) for this PR's TitledMaterialPageRoute changes.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/invoices/screens/dashboard/widgets/activity_and_charts.dart';
import 'package:care_connect_app/features/invoices/screens/dashboard/utilis/metrics.dart';
import 'package:care_connect_app/features/invoices/models/invoice_models.dart';
import '../../../../../helpers/titled_route_probe.dart';

// Minimal Invoice builder
Invoice _makeInvoice({
  required String id,
  required String providerName,
  required PaymentStatus status,
  double amountDue = 100.0,
  DateTime? statementDate,
}) {
  final now = DateTime.now();
  return Invoice(
    id: id,
    invoiceNumber: 'INV-$id',
    provider: ProviderInfo(name: providerName, address: 'Addr', phone: '555'),
    patient: const PatientInfo(name: 'Patient'),
    dates: InvoiceDates(
      statementDate: statementDate ?? now,
      dueDate: now.add(const Duration(days: 30)),
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

Widget _wrap(Widget child) => MaterialApp(
    navigatorObservers: [probe],
    home: Scaffold(body: SingleChildScrollView(child: child)));

TitledRouteProbe probe = TitledRouteProbe();

void main() {
  setUp(() => probe = TitledRouteProbe());

  testWidgets(
      '"View" in recent activity opens a page titled '
      '"Invoice Details"', (tester) async {
    await tester.pumpWidget(_wrap(RecentActivityCard(invoices: [
      _makeInvoice(
          id: '1', providerName: 'City Clinic', status: PaymentStatus.pending),
    ], loading: false)));
    await tester.pump();
    expect(await probe.tapAndReadTitle(tester, find.text('View').first),
        'Invoice Details');
  });
}
