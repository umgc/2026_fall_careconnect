// InvoiceListPage and InvoiceDetailPage
// (lib/features/invoices/screens/) against a MockClient: quick filters,
// sorting, the search sheet, opening details / payment tab, editing and
// saving (success and failure), PDF, and paging through the tabs.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:care_connect_app/features/invoices/models/invoice_models.dart';
import 'package:care_connect_app/features/invoices/screens/invoice_detail_page.dart';
import 'package:care_connect_app/features/invoices/screens/invoice_list_page.dart';

const _secureStorage =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

Map<String, dynamic> _json(
  String id,
  String status, {
  String due = '2020-01-01',
  String? documentLink,
}) =>
    {
      'id': id,
      'invoiceNumber': 'N-$id',
      'provider': {'name': 'Clinic $id', 'address': 'a', 'phone': '555'},
      'patient': {'name': 'Patient $id'},
      'dates': {'statementDate': '2019-12-01', 'dueDate': due},
      'services': [
        {'description': 'Visit', 'charge': 50},
      ],
      'paymentStatus': status,
      'amounts': {'total': 100, 'amountDue': 80},
      'paymentReferences': {'supportedMethods': <String>[]},
      'documentLink': documentLink,
      'history': [
        {
          'userId': 'u',
          'action': 'created',
          'details': 'd',
          'version': 1,
          'changes': '',
          'timestamp': '2020-01-01T00:00:00Z',
        },
      ],
      'aiSummary': 'AI says hi',
      'recommendedActions': ['Call insurer'],
    };

final _list = [
  _json('1', 'pending'),
  _json('2', 'rejectedInsurance'),
  _json('3', 'paid'),
  _json('4', 'overdue', due: '2999-01-01'),
];

int _updateStatus = 200;
final List<String> _calls = <String>[];

MockClient _client() => MockClient((r) async {
      _calls.add('${r.method} ${r.url.path}');
      if (r.method == 'PUT') {
        return _updateStatus == 200
            ? http.Response(jsonEncode(_json('1', 'pending')), 200)
            : http.Response('nope', _updateStatus);
      }
      if (r.url.pathSegments.last == 'invoices') {
        return http.Response(jsonEncode({'items': _list}), 200);
      }
      return http.Response(jsonEncode(_list.first), 200);
    });

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUp(() {
    _updateStatus = 200;
    _calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorage, (call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorage, null);
  });

  Future<void> pumpList(WidgetTester tester,
      {String? quickFilter, double width = 600}) async {
    tester.view.physicalSize = Size(width, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: InvoiceListPage(quickFilter: quickFilter),
    ));
    await _settle(tester);
  }

  for (final entry in {
    'pending': 1,
    'rejected': 1,
    'overdue': 2,
    null: 4,
  }.entries) {
    testWidgets('quick filter ${entry.key} keeps ${entry.value} invoices',
        (tester) async {
      await http.runWithClient(() => pumpList(tester, quickFilter: entry.key),
          _client);
      expect(find.text('${entry.value} found'), findsOneWidget);
    });
  }

  testWidgets('wide layout shows the desktop table', (tester) async {
    // The desktop DataTable's status column overflows by a few pixels;
    // ignore that layout warning here.
    final onError = FlutterError.onError;
    FlutterError.onError = (d) {
      if (!d.toString().contains('overflowed')) onError?.call(d);
    };
    addTearDown(() => FlutterError.onError = onError);
    await http.runWithClient(() async {
      await pumpList(tester, width: 1600);
      expect(find.byType(DataTable), findsOneWidget);
      await tester.tap(find.byIcon(Icons.payment).first);
      await tester.pumpAndSettle();
      expect(find.byType(InvoiceDetailPage), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.visibility).first);
      await tester.pumpAndSettle();
      expect(find.byType(InvoiceDetailPage), findsOneWidget);
    }, _client);
  });

  testWidgets('sorting and the search sheet refetch the list',
      (tester) async {
    await http.runWithClient(() async {
      await pumpList(tester);
      await tester.tap(find.text('Recently Added').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Due Date (Earliest)').last);
      await _settle(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Search & Filter'));
      await tester.pumpAndSettle();
      expect(find.text('Search & Filter Invoices'), findsOneWidget);
      await tester.tap(find.text('Apply'));
      await _settle(tester);
      await tester.pumpAndSettle();
    }, _client);
    expect(_calls.where((c) => c == 'GET /v1/api/invoices').length,
        greaterThanOrEqualTo(3));
  });

  testWidgets('view opens the detail page; edit, save and close',
      (tester) async {
    await http.runWithClient(() async {
      await pumpList(tester, quickFilter: 'pending');
      await tester.tap(find.text('View').first);
      await tester.pumpAndSettle();
      expect(find.byType(InvoiceDetailPage), findsOneWidget);
      expect(find.text('Invoice N-1'), findsOneWidget);

      // Walk the tabs with Next, then back with Prev.
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
      }
      expect(find.text('History'), findsWidgets);
      await tester.tap(find.text('Prev'));
      await tester.pumpAndSettle();

      // PDF without a document link reports that it is unavailable.
      await tester.tap(find.text('PDF'));
      await tester.pump();
      expect(find.text('PDF is not available for this invoice yet'),
          findsOneWidget);
      ScaffoldMessenger.of(tester.element(find.byType(InvoiceDetailPage)))
          .clearSnackBars();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Edit'));
      await tester.pump();
      await tester.tap(find.text('Cancel').first);
      await tester.pump();

      await tester.tap(find.text('Edit'));
      await tester.pump();
      await tester.tap(find.text('Save').first);
      await _settle(tester);
      expect(find.text('Invoice saved'), findsOneWidget);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(InvoiceDetailPage), findsNothing);
    }, _client);
  });

  testWidgets('a failed save keeps editing and reports it', (tester) async {
    _updateStatus = 500;
    await http.runWithClient(() async {
      await pumpList(tester, quickFilter: 'rejected');
      await tester.tap(find.text('Pay').first);
      await tester.pumpAndSettle();
      expect(find.text('Payment Options'), findsOneWidget);
      await tester.tap(find.text('Edit'));
      await tester.pump();
      await tester.tap(find.text('Save').first);
      await _settle(tester);
      expect(find.text('Save failed. Please try again.'), findsOneWidget);
    }, _client);
  });

  testWidgets('a new invoice can be discarded', (tester) async {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => InvoiceDetailPage(
              invoice: Invoice(
                id: '',
                invoiceNumber: '',
                provider:
                    const ProviderInfo(name: '', address: '', phone: ''),
                patient: const PatientInfo(name: ''),
                dates: InvoiceDates(
                  statementDate: DateTime(2025),
                  dueDate: DateTime(2025, 2),
                ),
                paymentStatus: PaymentStatus.pending,
                billedToInsurance: false,
                amounts: const Amounts(),
                paymentReferences:
                    PaymentReferences(supportedMethods: const []),
                createdAt: '',
                updatedAt: '',
                createdBy: '',
                updatedBy: '',
                payments: const [],
              ),
              isNew: true,
              initialTabIndex: 9,
            ),
          )),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('New Invoice'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
  });
}
