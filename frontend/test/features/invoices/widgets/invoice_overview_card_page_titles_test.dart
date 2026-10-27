// Page-title tests for InvoiceOverviewCard
// (lib/features/invoices/widgets/invoice_overview_card.dart): tapping the card
// opens the invoice assistant in a titled page (WCAG 2.4.2).
import 'package:care_connect_app/features/invoices/widgets/invoice_overview_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/titled_route_probe.dart';

void main() {
  testWidgets('tapping the card opens a page titled "Invoice Assistant"',
      (tester) async {
    final probe = TitledRouteProbe();
    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [probe],
      home: Scaffold(
          body: InvoiceOverviewCard(getUnpaidCount: () async => 2)),
    ));
    await tester.pumpAndSettle();
    expect(
        await probe.tapAndReadTitle(tester, find.byType(InkWell).first),
        'Invoice Assistant');
  });
}
