// Page-title tests for InvoiceListPage
// (lib/features/invoices/screens/invoice_list_page.dart): View and Pay on an
// invoice card both open a page titled "Invoice Details" (WCAG 2.4.2).
import 'dart:convert';

import 'package:care_connect_app/features/invoices/screens/invoice_list_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/titled_route_probe.dart';

final _invoice = {
  'id': 'inv-001',
  'invoiceNumber': 'INV-001',
  'provider': {
    'name': 'ACME Health',
    'address': '1 Clinic Rd',
    'phone': '800-555-0001',
    'email': 'billing@acme.com',
  },
  'patient': {
    'name': 'Jane Doe',
    'address': '42 Oak Ave',
    'accountNumber': 'P-100',
    'billingAddress': '42 Oak Ave',
  },
  'dates': {
    'statementDate': '2025-03-01T00:00:00.000Z',
    'dueDate': '2025-04-01T00:00:00.000Z',
  },
  'paymentStatus': 'pending',
  'billedToInsurance': false,
  'amounts': {
    'totalCharges': 200.0,
    'totalAdjustments': 50.0,
    'total': 150.0,
    'amountDue': 75.0,
  },
  'services': [],
  'history': [],
  'payments': [],
};

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => null,
    );
  });

  Future<String?> titleAfterTapping(WidgetTester tester, String label) async {
    // Narrow enough for the card layout rather than the wide table.
    tester.view.physicalSize = const Size(600, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final probe = TitledRouteProbe();
    String? title;
    await http.runWithClient(() async {
      await tester.pumpWidget(MaterialApp(
        navigatorObservers: [probe],
        home: const InvoiceListPage(),
      ));
      for (var i = 0; i < 5; i++) {
        await tester.idle();
        await tester.pump();
      }
      title = await probe.tapAndReadTitle(
          tester, find.text(label, skipOffstage: false).first);
    }, () => MockClient((_) async => http.Response(jsonEncode([_invoice]), 200)));
    return title;
  }

  testWidgets('View opens a page titled "Invoice Details"', (tester) async {
    expect(await titleAfterTapping(tester, 'View'), 'Invoice Details');
  });

  testWidgets('Pay opens a page titled "Invoice Details"', (tester) async {
    expect(await titleAfterTapping(tester, 'Pay'), 'Invoice Details');
  });
}
