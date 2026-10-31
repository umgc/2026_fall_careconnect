// Coverage tests for FileUploadDemo (lib/widgets/file_upload_demo.dart):
// quick photo and prescription uploads from real temp files (success and
// rejection), an invalid file type, a failed download and a failed delete,
// and the embedded FileUploadWidget callbacks.

import 'dart:convert';
import 'dart:io';

import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/services/enhanced_file_service.dart';
import 'package:care_connect_app/widgets/file_upload_demo.dart';
import 'package:care_connect_app/widgets/file_upload_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _secureStorage =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
const _imagePicker = MethodChannel('plugins.flutter.io/image_picker');
const _connectivity = MethodChannel('dev.fluttercommunity.plus/connectivity');

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

class _Backend {
  _Backend({this.uploadCode = 200, this.downloadCode = 200, this.deleteCode = 200});
  final int uploadCode;
  final int downloadCode;
  final int deleteCode;
  final requests = <http.Request>[];

  MockClient client() => MockClient((req) async {
        requests.add(req);
        final path = req.url.path;
        if (path.endsWith('/list')) {
          return http.Response(
              jsonEncode({
                'files': [
                  {
                    'id': 1,
                    'originalFilename': 'tiny.txt',
                    'contentType': 'text/plain',
                    'fileSize': 100,
                  },
                ],
              }),
              200);
        }
        if (path.endsWith('/download')) {
          return downloadCode == 200
              ? http.Response.bytes([1, 2], 200)
              : http.Response('{"error":"gone"}', downloadCode);
        }
        if (req.method == 'DELETE') {
          return http.Response('{"error":"locked"}', deleteCode);
        }
        if (req.method == 'POST') {
          return uploadCode == 200
              ? http.Response(
                  jsonEncode({
                    'data': {'fileId': 8, 'originalFilename': 'me.jpg'},
                  }),
                  200)
              : http.Response('{"error":"rejected"}', uploadCode);
        }
        return http.Response('{}', 200);
      });

  int count(bool Function(http.Request r) test) =>
      requests.where(test).length;
}

void main() {
  late Directory dir;
  late String jpgPath;
  late String gifPath;
  late List<MethodCall> pickerCalls;
  late String pickedPath;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('demo_cov_');
    jpgPath = '${dir.path}${Platform.pathSeparator}me.jpg';
    gifPath = '${dir.path}${Platform.pathSeparator}me.gif';
    File(jpgPath).writeAsBytesSync(_png);
    File(gifPath).writeAsBytesSync(_png);
    pickedPath = jpgPath;
    pickerCalls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_secureStorage, (call) async => null);
    messenger.setMockMethodCallHandler(_connectivity, (call) async {
      if (call.method == 'check') return ['wifi'];
      return null;
    });
    messenger.setMockMethodCallHandler(_imagePicker, (call) async {
      pickerCalls.add(call);
      return pickedPath;
    });
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_secureStorage, null);
    messenger.setMockMethodCallHandler(_imagePicker, null);
    messenger.setMockMethodCallHandler(_connectivity, null);
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<void> pumpDemo(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: FileUploadDemo(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  // The demo first shows an "Uploading/Downloading..." snackbar; pump
  // until it times out and the queued result snackbar is visible.
  Future<void> waitForSnackBar(WidgetTester tester, Finder done) async {
    for (var i = 0; i < 40 && done.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
  }

  Future<void> quickUpload(
      WidgetTester tester, String label, Finder done) async {
    await tester.tap(find.text(label));
    await tester.pump();
    // Let the real file I/O run until the expected result appears.
    for (var i = 0; i < 250 && done.evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 500));
    }
  }

  testWidgets('a quick profile photo upload succeeds and reloads',
      (tester) async {
    final backend = _Backend();
    await http.runWithClient(() async {
      await pumpDemo(tester);
      await quickUpload(tester, 'Profile Photo',
          find.text('Profile Picture uploaded successfully!'));
    }, backend.client);
    expect(pickerCalls.single.method, 'pickImage');
    expect(
      backend.count((r) => r.url.path.endsWith('/users/1/profile-image')),
      1,
    );
    expect(find.text('Profile Picture uploaded successfully!'), findsOneWidget);
    expect(backend.count((r) => r.url.path.endsWith('/list')), 2);
  });

  testWidgets('a rejected prescription upload is reported', (tester) async {
    final backend = _Backend(uploadCode: 500);
    await http.runWithClient(() async {
      await pumpDemo(tester);
      await quickUpload(
          tester, 'Prescription', find.text('Failed to upload Prescription'));
    }, backend.client);
    expect(
      backend.count((r) => r.url.path.endsWith('/prescriptions/upload')),
      1,
    );
    expect(find.text('Failed to upload Prescription'), findsOneWidget);
  });

  testWidgets('an unsupported photo type is rejected before upload',
      (tester) async {
    pickedPath = gifPath;
    final backend = _Backend();
    await http.runWithClient(() async {
      await pumpDemo(tester);
      await quickUpload(tester, 'Profile Photo',
          find.text('Invalid file type for Profile Picture'));
    }, backend.client);
    expect(find.text('Invalid file type for Profile Picture'), findsOneWidget);
    expect(backend.count((r) => r.method == 'POST'), 0);
  });

  testWidgets('failed download and delete are reported', (tester) async {
    final backend = _Backend(downloadCode: 404, deleteCode: 500);
    await http.runWithClient(() async {
      await pumpDemo(tester);
      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Download').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await waitForSnackBar(tester, find.text('Failed to download file'));
      expect(find.text('Failed to download file'), findsOneWidget);
      ScaffoldMessenger.of(tester.element(find.byType(FileUploadDemo)))
          .clearSnackBars();
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Delete'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await waitForSnackBar(tester, find.text('Failed to delete tiny.txt'));
      expect(find.text('Failed to delete tiny.txt'), findsOneWidget);
    }, backend.client);
  });

  testWidgets('upload widget callbacks show snackbars and reload',
      (tester) async {
    final backend = _Backend();
    await http.runWithClient(() async {
      await pumpDemo(tester);
      final widget = tester.widget<FileUploadWidget>(
        find.byType(FileUploadWidget),
      );
      widget.onUploadError!('Upload broke');
      await tester.pump();
      expect(find.text('Upload broke'), findsOneWidget);
      ScaffoldMessenger.of(tester.element(find.byType(FileUploadDemo)))
          .clearSnackBars();
      await tester.pumpAndSettle();

      widget.onUploadSuccess!(FileUploadResponse(
        fileId: 4,
        originalFilename: 'chart.pdf',
        fileUrl: '',
        downloadUrl: '',
        message: '',
        fileName: 'chart.pdf',
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }, backend.client);
    expect(find.text('File uploaded: chart.pdf'), findsOneWidget);
    expect(backend.count((r) => r.url.path.endsWith('/list')), 2);
  });
}
