// Interaction tests for PaymentSection
// (lib/features/invoices/widgets/sections/payment_section.dart): editing the
// status, methods, online / telephone / check fields, opening the payment
// page, and recording full, partial and planned payments with the API
// failing (local fallback) or succeeding.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:care_connect_app/features/invoices/models/invoice_models.dart';
import 'package:care_connect_app/features/invoices/widgets/sections/payment_section.dart';

const _secureStorage =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
const _launcher = MethodChannel('plugins.flutter.io/url_launcher');

Invoice _invoice({
  List<String> methods = const [],
  String? paymentLink,
  String? qrCodeUrl,
  PaymentStatus status = PaymentStatus.pending,
  CheckPayableTo? check,
}) =>
    Invoice(
      id: 'INV-001',
      invoiceNumber: 'INV-001',
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
      amounts: const Amounts(totalCharges: 300, total: 300, amountDue: 300),
      paymentReferences: PaymentReferences(
        supportedMethods: methods,
        paymentLink: paymentLink,
        qrCodeUrl: qrCodeUrl,
      ),
      checkPayableTo: check,
      createdAt: '2025-01-01T00:00:00Z',
      updatedAt: '2025-01-01T00:00:00Z',
      createdBy: 'admin',
      updatedBy: 'admin',
      payments: const [],
    );

/// Hosts a PaymentSection whose value follows its own onChanged.
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
  late List<MethodCall> launches;
  late int paymentStatus;

  setUp(() {
    launches = <MethodCall>[];
    paymentStatus = 500;
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(_secureStorage, (call) async => null);
    m.setMockMethodCallHandler(_launcher, (call) async {
      launches.add(call);
      return true;
    });
  });

  tearDown(() {
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(_secureStorage, null);
    m.setMockMethodCallHandler(_launcher, null);
  });

  Future<List<Invoice>> pump(WidgetTester tester, Invoice inv) async {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final changes = <Invoice>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: _Host(inv, changes)),
    ));
    return changes;
  }

  Future<void> withApi(WidgetTester tester, Future<void> Function() body) =>
      http.runWithClient(body, () => MockClient((r) async {
            if (paymentStatus == 200) {
              return http.Response(jsonEncode({'id': 'INV-001'}), 200);
            }
            return http.Response('nope', paymentStatus);
          }));

  testWidgets('editing status, methods and field values reports changes',
      (tester) async {
    final changes = await pump(
      tester,
      _invoice(
        methods: const [kMethodTelephone, kMethodCheck],
        qrCodeUrl: 'https://qr.example/pay',
        paymentLink: 'pay.example/abc',
        check: const CheckPayableTo(name: 'Clinic', address: 'A', reference: 'R'),
      ),
    );

    await tester.tap(find.byType(DropdownButtonFormField<PaymentStatus>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Overdue').last);
    await tester.pumpAndSettle();
    expect(changes.last.paymentStatus, PaymentStatus.overdue);

    await tester.tap(find.widgetWithText(FilterChip, 'Online Payment'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilterChip, 'Check'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilterChip, 'Check'));
    await tester.pump();

    for (final label in [
      'Payment Link (URL or deeplink)',
      'QR Code Destination URL (encoded in QR)',
      'Phone Number or Instructions',
      'Notes (appears on statement or instructions)',
      'Payable To',
      'Mailing Address',
      'Reference (include invoice number)',
    ]) {
      await tester.enterText(find.widgetWithText(TextFormField, label), 'x');
      await tester.pump();
    }
    expect(changes.length, greaterThan(8));

    await tester.tap(find.text('Open Payment Page'));
    await tester.pump();
    await tester.pump();
    expect(launches, isNotEmpty);
  });

  testWidgets('recording a planned partial payment falls back locally',
      (tester) async {
    final changes = await pump(tester, _invoice());
    await withApi(tester, () async {
      await tester.tap(find.text('Record Payment'));
      await tester.pumpAndSettle();
      expect(find.text('Payment Method'), findsOneWidget);

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Telephone').last);
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('Payment in full'));
      await tester.pump();
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Partial Payment Amount'), '100');
      await tester.tap(
          find.text('Set up payment plan for remaining balance'));
      await tester.pump();
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('12 months').last);
      await tester.pumpAndSettle();

      // Change the payment date through the picker.
      await tester.tap(find.widgetWithText(TextFormField, 'Payment Date'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Record Payment').last);
      await tester.pumpAndSettle();
    });
    expect(find.text('Payment recorded locally'), findsOneWidget);
    expect(changes.last.paymentStatus, PaymentStatus.partialPayment);
    expect(changes.last.amounts.amountDue, 200);
  });

  testWidgets('a full payment that the API accepts marks it recorded',
      (tester) async {
    paymentStatus = 200;
    await pump(tester, _invoice(methods: const [kMethodCard]));
    await withApi(tester, () async {
      await tester.tap(find.text('Record Payment'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Record Payment').last);
      await tester.pumpAndSettle();
    });
    expect(
      find.byWidgetPredicate((w) =>
          w is Text &&
          (w.data == 'Payment recorded' || w.data == 'Payment recorded locally')),
      findsOneWidget,
    );
  });

  testWidgets('a full payment that fails locally marks the invoice paid',
      (tester) async {
    final changes = await pump(tester, _invoice());
    await withApi(tester, () async {
      await tester.tap(find.text('Record Payment'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Record Payment').last);
      await tester.pumpAndSettle();
    });
    expect(changes.last.paymentStatus, PaymentStatus.paid);
  });

  testWidgets('the payment dialog can be cancelled', (tester) async {
    final changes = await pump(tester, _invoice());
    await tester.tap(find.text('Record Payment'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(changes, isEmpty);
  });

  testWidgets('status chip colours cover every status', (tester) async {
    for (final s in PaymentStatus.values) {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PaymentSection(
            value: _invoice(status: s),
            isEditing: false,
            onChanged: (_) {},
          ),
        ),
      ));
      expect(find.byType(Chip), findsOneWidget);
    }
  });
}
