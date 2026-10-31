// InvoiceOcrLlmApi.extractWithLlm
// (lib/features/invoices/services/invoice_ocr_llm_api.dart) against a
// MockClient: multipart upload of images / PDFs, mapping of the server
// InvoiceDto (new and legacy response shapes) and error responses.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';

import 'package:care_connect_app/features/invoices/models/invoice_models.dart';
import 'package:care_connect_app/features/invoices/services/invoice_ocr_llm_api.dart';

const _secureStorage =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');

Map<String, dynamic> _invoiceDto({String status = 'paid'}) => {
      'id': 'inv-1',
      'invoiceNumber': 'INV-100',
      'provider': {
        'name': 'Clinic',
        'address': '1 Main St',
        'phone': '555-0100',
        'email': 'billing@clinic.example',
      },
      'patient': {
        'name': 'Pat Patient',
        'address': '2 Side St',
        'accountNumber': 'ACC-1',
        'billingAddress': '3 Bill St',
      },
      'dates': {
        'statementDate': '2026-09-01',
        'dueDate': '2026-10-01',
        'paidDate': 'not-a-date',
      },
      'services': [
        {
          'description': 'Visit',
          'serviceCode': '99213',
          'serviceDate': '2026-08-30',
          'charge': 120,
          'patientBalance': '20.5',
          'insuranceAdjustments': null,
        },
      ],
      'paymentStatus': status,
      'billedToInsurance': true,
      'amounts': {
        'totalCharges': 120,
        'totalAdjustments': 100,
        'total': 20.5,
        'amountDue': '20.5',
      },
      'paymentReferences': {
        'paymentLink': 'https://pay.example',
        'qrCodeUrl': null,
        'notes': 'Thanks',
        'supportedMethods': ['card', 'check'],
      },
      'checkPayableTo': {
        'name': 'Clinic',
        'address': '1 Main St',
        'reference': 'INV-100',
      },
      'history': [
        {
          'userId': 'u1',
          'action': 'created',
          'details': 'd',
          'version': 2,
          'changes': 'c',
          'timestamp': '2026-09-01T00:00:00Z',
        },
      ],
      'payments': [
        {
          'id': 'p1',
          'confirmationNumber': 'CONF',
          'date': '2026-09-15',
          'methodKey': 'card',
          'amountPaid': 10,
          'planEnabled': true,
          'planDurationMonths': 3,
        },
      ],
      'aiSummary': 'Summary',
      'recommendedActions': ['Pay soon'],
    };

XFile _file(Directory dir, String name, List<int> bytes, {String? mimeType}) {
  final f = File('${dir.path}/$name')..writeAsBytesSync(bytes);
  return XFile(f.path, mimeType: mimeType);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late List<http.BaseRequest> sent;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('ocr_llm_');
    sent = <http.BaseRequest>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorage, (call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorage, null);
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<InvoiceResponseDto?> run(
    http.Response Function() reply, {
    List<XFile> images = const [],
    List<String> pdfPaths = const [],
    List<Uint8List> pdfBytes = const [],
  }) {
    return http.runWithClient(
      () => InvoiceOcrLlmApi.extractWithLlm(
        images: images,
        pdfPaths: pdfPaths,
        pdfBytes: pdfBytes,
      ),
      () => MockClient.streaming((request, body) async {
        await body.drain<void>();
        sent.add(request);
        final r = reply();
        return http.StreamedResponse(
          Stream.value(utf8.encode(r.body)),
          r.statusCode,
        );
      }),
    );
  }

  test('uploads images and PDFs and maps the new response shape', () async {
    final pdf = File('${tmp.path}/scan.pdf')..writeAsBytesSync([37, 80, 68, 70]);
    final result = await run(
      () => http.Response(
        jsonEncode({
          'invoice': _invoiceDto(),
          'duplicate': true,
          'message': 'Already uploaded',
          'duplicateId': 'inv-0',
          'duplicateInvoiceNumber': 'INV-099',
        }),
        200,
      ),
      images: [
        _file(tmp, 'photo.png', _png, mimeType: 'image/png'),
        _file(tmp, 'photo.jpeg', Uint8List.fromList([1, 2, 3, 4])),
        _file(tmp, 'odd', Uint8List.fromList([1, 2, 3]), mimeType: 'weird'),
      ],
      pdfPaths: [pdf.path],
      pdfBytes: [Uint8List.fromList([37, 80, 68, 70])],
    );

    final req = sent.single as http.MultipartRequest;
    expect(req.url.path, endsWith('/extract-llm'));
    expect(req.files.map((f) => f.filename), [
      'photo.png',
      'photo.jpg',
      'odd.bin',
      'scan.pdf',
      'upload_0.pdf',
    ]);

    expect(result!.duplicate, isTrue);
    expect(result.message, 'Already uploaded');
    expect(result.duplicateInvoiceNumber, 'INV-099');
    final inv = result.invoice;
    expect(inv.invoiceNumber, 'INV-100');
    expect(inv.paymentStatus, PaymentStatus.paid);
    expect(inv.services.single.patientBalance, 20.5);
    expect(inv.dates.paidDate, isNull);
    expect(inv.checkPayableTo?.reference, 'INV-100');
    expect(inv.history.single.version, 2);
    expect(inv.payments!.single.planDurationMonths, 3);
    expect(inv.paymentReferences.supportedMethods, ['card', 'check']);
    expect(inv.recommendedActions, ['Pay soon']);
  });

  test('HEIC images are converted to PNG before upload', () async {
    await run(
      () => http.Response(jsonEncode({'invoice': _invoiceDto()}), 200),
      images: [_file(tmp, 'scan.heic', _png)],
    );
    final req = sent.single as http.MultipartRequest;
    expect(req.files.single.filename, 'scan.png');
  });

  test('legacy response shape maps every payment status', () async {
    for (final s in [
      'pending',
      'overdue',
      'pendingInsurance',
      'sent',
      'paid',
      'partialPayment',
      'rejectedInsurance',
      'unknown',
    ]) {
      final dto = _invoiceDto(status: s)
        ..remove('checkPayableTo')
        ..remove('dates');
      final result = await run(() => http.Response(jsonEncode(dto), 200));
      expect(result!.duplicate, isFalse);
      expect(result.invoice.checkPayableTo, isNull);
    }
  });

  test('a non-200 response throws with the status', () async {
    await expectLater(
      run(() => http.Response('boom', 500)),
      throwsA(isA<Exception>().having(
          (e) => e.toString(), 'message', contains('500'))),
    );
  });

  test('an unexpected response shape throws', () async {
    await expectLater(
      run(() => http.Response('[1,2]', 200)),
      throwsA(isA<Exception>()),
    );
  });
}
