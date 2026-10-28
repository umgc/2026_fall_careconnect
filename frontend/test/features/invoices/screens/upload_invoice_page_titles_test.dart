// Page-title tests for UploadInvoicePage
// (lib/features/invoices/screens/upload_invoice.dart): picked files and photos
// go to "Review Invoice Photos", and manual entry or an extracted invoice
// opens "Invoice Details" (WCAG 2.4.2). Pickers and the extract call are faked.
import 'dart:convert';
import 'dart:io';

import 'package:care_connect_app/features/invoices/screens/upload_invoice.dart';
import 'package:care_connect_app/widgets/page_title.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/titled_route_probe.dart';

class _FakeFilePicker extends Fake
    with MockPlatformInterfaceMixin
    implements FilePicker {
  _FakeFilePicker(this.path);

  final String path;

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
      FilePickerResult([PlatformFile(name: 'bill.png', size: 4, path: path)]);
}

void main() {
  late Directory tmp;
  late String imagePath;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (_) async => null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => call.method == 'check' ? ['wifi'] : null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
      (_) async => null,
    );
    tmp = Directory.systemTemp.createTempSync('upload_invoice_titles');
    imagePath = '${tmp.path}${Platform.pathSeparator}bill.png';
    File(imagePath).writeAsBytesSync([0x89, 0x50, 0x4E, 0x47]);
    FilePicker.platform = _FakeFilePicker(imagePath);
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/image_picker'),
      (_) async => imagePath,
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/image_picker'),
      null,
    );
    tmp.deleteSync(recursive: true);
  });

  Future<TitledRouteProbe> pumpPage(WidgetTester tester) async {
    final probe = TitledRouteProbe();
    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [probe],
      home: const UploadInvoicePage(),
    ));
    await tester.pump();
    return probe;
  }

  testWidgets('Upload File opens a page titled "Review Invoice Photos"',
      (tester) async {
    final probe = await pumpPage(tester);
    expect(await probe.tapAndReadTitle(tester, find.text('Upload File')),
        'Review Invoice Photos');
  });

  testWidgets('Take Photo opens a page titled "Review Invoice Photos"',
      (tester) async {
    final probe = await pumpPage(tester);
    expect(await probe.tapAndReadTitle(tester, find.text('Take Photo')),
        'Review Invoice Photos');
  });

  testWidgets('Manual Entry opens a page titled "Invoice Details"',
      (tester) async {
    final probe = await pumpPage(tester);
    expect(await probe.tapAndReadTitle(tester, find.text('Manual Entry')),
        'Invoice Details');
  });

  testWidgets('an extracted invoice opens a page titled "Invoice Details"',
      (tester) async {
    await http.runWithClient(() async {
      final probe = await pumpPage(tester);

      // Wait (without building pages) for the next titled page to be pushed.
      Future<TitledMaterialPageRoute> nextTitledRoute(int before) async {
        bool pushed() => probe.pushed
            .skip(before)
            .any((route) => route is TitledMaterialPageRoute);
        for (var i = 0; i < 20 && !pushed(); i++) {
          // The extract step reads the photo from disk: real I/O.
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)));
          await tester.idle();
        }
        for (var i = 0; i < 20 && !pushed(); i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        return probe.pushed
            .skip(before)
            .whereType<TitledMaterialPageRoute>()
            .first;
      }

      var before = probe.pushed.length;
      await tester.tap(find.text('Upload File'));
      final review = await nextTitledRoute(before);
      // Finish the review with the picked photo, as its Done button would.
      before = probe.pushed.length;
      probe.navigator!.removeRoute(review, [XFile(imagePath)]);

      final details = await nextTitledRoute(before);
      final content = details.buildContent(probe.navigator!.context);
      expect((content as PageTitle).title, 'Invoice Details');
      probe.navigator!.removeRoute(details);
      await tester.pump();
    },
        () => MockClient((_) async => http.Response(
            jsonEncode({
              'invoice': {'invoiceNumber': 'INV-9'},
              'duplicate': false,
            }),
            200)));
  });
}
