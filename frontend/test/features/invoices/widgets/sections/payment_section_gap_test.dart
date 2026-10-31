// Gap coverage for PaymentSection: a payment the API accepts replaces the
// invoice with the server copy. Only fakes are used: HTTP via http.testing MockClient, secure
// storage and url_launcher via mocked channels. No real card data.
import 'dart:convert';

import 'package:care_connect_app/features/invoices/models/invoice_models.dart';
import 'package:care_connect_app/features/invoices/widgets/sections/payment_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _secureStorage = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

Invoice _invoice({
  PaymentStatus status = PaymentStatus.pending,
  double amountDue = 300,
  List<String> methods = const [],
  CheckPayableTo? check,
}) =>
    Invoice(
      id: 'INV-GAP',
      invoiceNumber: 'INV-GAP',
      provider: const ProviderInfo(
        name: 'City Medical Center',
        address: '100 Health Ave',
        phone: '555-1234',
      ),
      patient: const PatientInfo(name: 'John Doe'),
      dates: InvoiceDates(
        statementDate: DateTime(2025, 1, 1),
        dueDate: DateTime(2025, 2, 1),
      ),
      paymentStatus: status,
      billedToInsurance: false,
      amounts: Amounts(totalCharges: 300, total: 300, amountDue: amountDue),
      paymentReferences: PaymentReferences(supportedMethods: methods),
      checkPayableTo: check,
      createdAt: '2025-01-01T00:00:00Z',
      updatedAt: '2025-01-01T00:00:00Z',
      createdBy: 'admin',
      updatedBy: 'admin',
      payments: const [],
    );

class _Host extends StatefulWidget {
  const _Host(this.initial, this.changes);
  final Invoice initial;
  final List<Invoice> changes;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late Invoice value = widget.initial;

  @override
  Widget build(BuildContext context) => PaymentSection(
        value: value,
        isEditing: true,
        onChanged: (v) {
          widget.changes.add(v);
          setState(() => value = v);
        },
      );
}

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorage, (call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorage, null);
  });

  testWidgets('a payment accepted by the API replaces the invoice',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final serverCopy = {
      'id': 'INV-GAP',
      'invoiceNumber': 'INV-GAP',
      'provider': {'name': 'City Medical Center'},
      'patient': {'name': 'John Doe'},
      'dates': {'statementDate': '2025-01-01', 'dueDate': '2025-02-01'},
      'paymentStatus': 'paid',
      'amounts': {'totalCharges': 300, 'total': 300, 'amountDue': 0},
      'paymentReferences': {'supportedMethods': <String>[]},
    };
    final requests = <http.Request>[];
    final changes = <Invoice>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: _Host(_invoice(), changes)),
      ),
    );

    await http.runWithClient(() async {
      await tester.tap(find.text('Record Payment'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Record Payment').last,
      );
      await tester.pumpAndSettle();
    },
        () => MockClient((request) async {
              requests.add(request);
              return http.Response(jsonEncode(serverCopy), 200);
            }));

    expect(requests, hasLength(1));
    expect(requests.single.method, 'POST');
    expect(requests.single.url.path, endsWith('/INV-GAP/payments'));
    final sent = jsonDecode(requests.single.body) as Map<String, dynamic>;
    expect(sent['amountPaid'], 300);

    expect(find.text('Payment recorded'), findsOneWidget);
    expect(find.text('Payment recorded locally'), findsNothing);
    expect(changes.last.paymentStatus, PaymentStatus.paid);
    expect(changes.last.amounts.amountDue, 0);
  });
}
