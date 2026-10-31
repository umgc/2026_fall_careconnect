// Coverage tests for PaymentSection
// (lib/features/invoices/widgets/sections/payment_section.dart): the
// payment-link-only QR layout (with and without an http link) and the
// copyWith extensions.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:care_connect_app/features/invoices/models/invoice_models.dart';
import 'package:care_connect_app/features/invoices/widgets/sections/payment_section.dart';

const _secureStorage =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

Invoice _invoice({
  String? paymentLink,
  String? qrCodeUrl,
  PaymentStatus status = PaymentStatus.pending,
}) =>
    Invoice(
      id: 'INV-9',
      invoiceNumber: 'INV-9',
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
      amounts: const Amounts(totalCharges: 100, total: 100, amountDue: 100),
      paymentReferences: PaymentReferences(
        supportedMethods: const [kMethodCard],
        paymentLink: paymentLink,
        qrCodeUrl: qrCodeUrl,
      ),
      createdAt: '2025-01-01T00:00:00Z',
      updatedAt: '2025-01-01T00:00:00Z',
      createdBy: 'admin',
      updatedBy: 'admin',
      payments: const [],
    );

Future<List<Invoice>> _pump(WidgetTester tester, Invoice inv) async {
  tester.view.physicalSize = const Size(1000, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final changes = <Invoice>[];
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: PaymentSection(
        value: inv,
        isEditing: false,
        onChanged: changes.add,
      ),
    ),
  ));
  return changes;
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

  testWidgets('a payment link without QR data shows the link layout',
      (tester) async {
    await _pump(
        tester, _invoice(paymentLink: 'https://pay.example/x', qrCodeUrl: ' '));
    expect(find.text('Open Payment Page'), findsOneWidget);
    expect(
        find.text('Scan the QR or tap the button to open the payment page.'),
        findsOneWidget);
  });

  testWidgets('a deeplink payment link is also openable',
      (tester) async {
    // Any parseable link is treated as openable.
    await _pump(tester, _invoice(paymentLink: 'app://pay/x', qrCodeUrl: ' '));
    expect(find.text('Open Payment Page'), findsOneWidget);
  });

  test('copyWith extensions keep or replace each field', () {
    final refs = PaymentReferences(
      paymentLink: 'a',
      qrCodeUrl: 'b',
      notes: 'c',
      supportedMethods: [kMethodCheck],
    );
    final same = PaymentReferencesCopy(refs).copyWith();
    expect(same.paymentLink, 'a');
    expect(same.supportedMethods, [kMethodCheck]);
    final changed =
        PaymentReferencesCopy(refs).copyWith(notes: 'n', supportedMethods: [kMethodOnline]);
    expect(changed.notes, 'n');
    expect(changed.supportedMethods, [kMethodOnline]);

    const check = CheckPayableTo(name: 'N', address: 'A', reference: 'R');
    expect(CheckPayableToCopy(check).copyWith().name, 'N');
    expect(CheckPayableToCopy(check).copyWith(reference: 'R2').reference, 'R2');

    const amounts =
        Amounts(totalCharges: 1.0, totalAdjustments: 2.0, total: 3.0);
    expect(AmountsCopy(amounts).copyWith().total, 3);
    expect(AmountsCopy(amounts).copyWith(amountDue: 9.0).amountDue, 9);
  });
}
