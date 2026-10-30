// End-to-end flows on UploadInvoicePage
// (lib/features/invoices/screens/upload_invoice.dart): offline banner, upload
// of images + PDFs through review and extraction, the duplicate warning
// (cancel / proceed), Take Photo, and the empty-selection messages.

import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/features/invoices/screens/invoice_detail_page.dart';
import 'package:care_connect_app/features/invoices/screens/upload_invoice.dart';
import 'package:care_connect_app/features/invoices/widgets/review_photos_screen.dart';

const _secureStorage =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
const _connectivity = MethodChannel('dev.fluttercommunity.plus/connectivity');
const _connectivityStatus =
    MethodChannel('dev.fluttercommunity.plus/connectivity_status');
const _imagePicker = MethodChannel('plugins.flutter.io/image_picker');

class _FakeFilePicker extends Fake
    with MockPlatformInterfaceMixin
    implements FilePicker {
  _FakeFilePicker(this.result);
  final FilePickerResult? result;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    dynamic Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async =>
      result;
}

void main() {
  late Directory tmp;
  late String imagePath;
  late String pdfPath;
  late List<String> connectivity;
  late Map<String, dynamic> extractBody;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    connectivity = ['wifi'];
    extractBody = {
      'invoice': {'invoiceNumber': 'INV-9'},
      'duplicate': false,
    };
    tmp = Directory.systemTemp.createTempSync('upload_invoice_flows');
    imagePath = '${tmp.path}${Platform.pathSeparator}bill.jpg';
    pdfPath = '${tmp.path}${Platform.pathSeparator}bill.pdf';
    File(imagePath).writeAsBytesSync([1, 2, 3]);
    File(pdfPath).writeAsBytesSync([37, 80, 68, 70]);
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(_secureStorage, (_) async => null);
    m.setMockMethodCallHandler(_connectivity,
        (call) async => call.method == 'check' ? connectivity : null);
    m.setMockMethodCallHandler(_connectivityStatus, (_) async => null);
    m.setMockMethodCallHandler(_imagePicker, (_) async => imagePath);
    FilePicker.platform = _FakeFilePicker(FilePickerResult([
      PlatformFile(name: 'bill.jpg', size: 3, path: imagePath),
      PlatformFile(name: 'bill.pdf', size: 4, path: pdfPath),
    ]));
  });

  tearDown(() {
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final c in [
      _secureStorage,
      _connectivity,
      _connectivityStatus,
      _imagePicker,
    ]) {
      m.setMockMethodCallHandler(c, null);
    }
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<void> settle(WidgetTester tester, [int n = 10]) async {
    for (var i = 0; i < n; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: UploadInvoicePage()));
    await settle(tester, 2);
  }

  MockClient client() => MockClient.streaming((request, body) async {
        await body.drain<void>();
        return http.StreamedResponse(
            Stream.value(utf8.encode(jsonEncode(extractBody))), 200);
      });

  testWidgets('offline status shows the banner', (tester) async {
    connectivity = ['none'];
    await pumpPage(tester);
    expect(find.byIcon(Icons.wifi_off), findsOneWidget);
  });

  testWidgets('upload with a duplicate can be cancelled', (tester) async {
    extractBody = {
      'invoice': {'id': 'x', 'invoiceNumber': 'INV-9'},
      'duplicate': true,
      'message': 'Looks familiar',
      'duplicateInvoiceNumber': 'INV-1',
    };
    await http.runWithClient(() async {
      await pumpPage(tester);
      await tester.tap(find.text('Upload File'));
      await settle(tester);
      expect(find.byType(ReviewPhotosScreen), findsOneWidget);
      await tester.tap(find.text('Done (2)'));
      await settle(tester, 20);
      expect(find.text('Possible duplicate'), findsOneWidget);
      expect(find.textContaining('Existing invoice number: INV-1'),
          findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(InvoiceDetailPage), findsNothing);
    }, client);
  });

  testWidgets('take photo with a duplicate can proceed to details',
      (tester) async {
    extractBody = {
      'invoice': {'invoiceNumber': 'INV-9'},
      'duplicate': true,
    };
    await http.runWithClient(() async {
      await pumpPage(tester);
      await tester.tap(find.text('Take Photo'));
      await settle(tester);
      await tester.tap(find.text('Done (1)'));
      await settle(tester, 20);
      expect(find.textContaining('appears to be a duplicate'), findsOneWidget);
      await tester.tap(find.text('Proceed'));
      await tester.pumpAndSettle();
      expect(find.byType(InvoiceDetailPage), findsOneWidget);
    }, client);
  });

  testWidgets('empty selections report why nothing happened',
      (tester) async {
    FilePicker.platform = _FakeFilePicker(FilePickerResult([
      PlatformFile(name: 'nopath.jpg', size: 1),
    ]));
    await pumpPage(tester);
    await tester.tap(find.text('Upload File'));
    await settle(tester);
    expect(find.text('No supported files selected'), findsOneWidget);

    // Reviewing and removing every file returns nothing.
    FilePicker.platform = _FakeFilePicker(FilePickerResult([
      PlatformFile(name: 'bill.jpg', size: 3, path: imagePath),
    ]));
    ScaffoldMessenger.of(tester.element(find.byType(UploadInvoicePage)))
        .clearSnackBars();
    await tester.tap(find.text('Upload File'));
    await settle(tester);
    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pump();
    // Leave the review without finishing: the route returns null.
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await settle(tester);
    expect(find.text('No files selected'), findsOneWidget);
  });
}
