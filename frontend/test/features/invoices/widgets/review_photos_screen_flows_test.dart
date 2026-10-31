// Add / remove / finish flows for ReviewPhotosScreen
// (lib/features/invoices/widgets/review_photos_screen.dart) with the image
// picker channel and FilePicker faked.

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:care_connect_app/features/invoices/widgets/review_photos_screen.dart';

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
  late String photoPath;
  late String pdfPath;
  String? cameraPath;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('review_photos_');
    photoPath = (File('${tmp.path}/bill.jpg')..writeAsBytesSync([1, 2, 3]))
        .path;
    pdfPath =
        (File('${tmp.path}/bill.pdf')..writeAsBytesSync([37, 80, 68, 70])).path;
    cameraPath = '${tmp.path}/camera.jpg';
    File(cameraPath!).writeAsBytesSync([4, 5, 6]);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_imagePicker, (call) async => cameraPath);
    FilePicker.platform = _FakeFilePicker(FilePickerResult([
      PlatformFile(name: 'bill.jpg', size: 3, path: photoPath),
      PlatformFile(name: 'bill.pdf', size: 4, path: pdfPath),
      PlatformFile(name: 'nopath.jpg', size: 1),
    ]));
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_imagePicker, null);
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<List<XFile>?> pumpAndFinish(
    WidgetTester tester,
    Future<void> Function() interact,
  ) async {
    List<XFile>? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              result = await Navigator.of(context).push<List<XFile>>(
                MaterialPageRoute(
                  builder: (_) => const ReviewPhotosScreen(initialPhotos: []),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await interact();
    return result;
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('camera and gallery add files, remove drops one, Done returns',
      (tester) async {
    final result = await pumpAndFinish(tester, () async {
      await tester.tap(find.text('Take photo'));
      await settle(tester);
      expect(find.text('1 selected'), findsOneWidget);

      // Taking the same photo again does not duplicate it.
      await tester.tap(find.text('Add').first);
      await settle(tester);
      expect(find.text('1 selected'), findsOneWidget);

      await tester.tap(find.text('Gallery'));
      await settle(tester);
      expect(find.text('3 selected'), findsOneWidget);
      expect(find.byIcon(Icons.picture_as_pdf_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close).first);
      await tester.pump();
      expect(find.text('2 selected'), findsOneWidget);

      await tester.tap(find.text('Done (2)'));
      await tester.pumpAndSettle();
    });
    expect(result, hasLength(2));
  });

  testWidgets('gallery from the empty state and the app bar Done',
      (tester) async {
    final result = await pumpAndFinish(tester, () async {
      await tester.tap(find.text('From gallery'));
      await settle(tester);
      expect(find.text('2 selected'), findsOneWidget);
      // The floating action button opens the gallery too.
      await tester.tap(find.byIcon(Icons.add_photo_alternate_outlined));
      await settle(tester);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
    });
    expect(result, hasLength(2));
  });

  testWidgets('cancelled pickers add nothing', (tester) async {
    cameraPath = null;
    FilePicker.platform = _FakeFilePicker(null);
    await pumpAndFinish(tester, () async {
      await tester.tap(find.text('Take photo'));
      await settle(tester);
      await tester.tap(find.text('From gallery'));
      await settle(tester);
    });
    expect(find.text('No files yet'), findsOneWidget);
  });
}
