// Coverage tests for EnhancedPatientNotesWidget
// (lib/widgets/enhanced_patient_notes_widget.dart): uploading a real temp
// file (uploading spinner, success with reload, rejected upload) and an
// image preview that loads successfully.

import 'dart:convert';
import 'dart:io';

import 'package:care_connect_app/widgets/enhanced_patient_notes_widget.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _secureStorage =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

class _FakeFilePicker extends Fake
    with MockPlatformInterfaceMixin
    implements FilePicker {
  FilePickerResult? result;

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

class _Backend {
  _Backend({this.uploadCode = 200, List<Map<String, dynamic>>? files})
      : files = files ?? const [];
  final int uploadCode;
  final List<Map<String, dynamic>> files;
  final requests = <http.Request>[];

  MockClient client() => MockClient((req) async {
        requests.add(req);
        final path = req.url.path;
        if (path.endsWith('/upload')) {
          return uploadCode == 200
              ? http.Response(
                  jsonEncode({
                    'data': {'fileId': 3, 'originalFilename': 'labs.pdf'},
                  }),
                  200)
              : http.Response('{"error":"rejected"}', uploadCode);
        }
        if (path.endsWith('/download')) {
          return http.Response.bytes(_png, 200);
        }
        if (path.contains('/patient/')) {
          return http.Response(jsonEncode({'data': files}), 200);
        }
        return http.Response('{}', 200);
      });
}

void main() {
  late _FakeFilePicker picker;
  late Directory dir;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FilePicker.platform = picker = _FakeFilePicker();
    dir = Directory.systemTemp.createTempSync('enh_notes_cov_');
    final path = '${dir.path}${Platform.pathSeparator}labs.pdf';
    File(path).writeAsStringSync('%PDF-1.4');
    picker.result = FilePickerResult([
      PlatformFile(name: 'labs.pdf', size: 8, path: path),
    ]);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorage, (call) async {
      if (call.method == 'read' &&
          (call.arguments as Map)['key'] == 'jwt_token') {
        return 'jwt';
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorage, null);
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<void> pumpWidget(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: EnhancedPatientNotesWidget(patientId: 9),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> upload(WidgetTester tester, Finder done) async {
    await tester.tap(find.text('Add File'));
    await tester.pumpAndSettle();
    expect(find.text('File Details'), findsOneWidget);
    await tester.tap(find.text('Upload'));
    await tester.pump();
    // The add button is replaced by a spinner while uploading.
    expect(find.text('Add File'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    // Let the real file I/O run until the expected result appears.
    for (var i = 0; i < 250 && done.evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('a successful upload reloads the file list', (tester) async {
    final backend = _Backend();
    await http.runWithClient(() async {
      await pumpWidget(tester);
      await upload(tester, find.text('File uploaded successfully'));
    }, backend.client);
    final upload0 =
        backend.requests.singleWhere((r) => r.url.path.endsWith('/upload'));
    expect(upload0.url.path, endsWith('/users/9/upload'));
    expect(upload0.body, contains('filename="labs.pdf"'));
    expect(find.text('File uploaded successfully'), findsOneWidget);
    expect(find.text('Add File'), findsOneWidget);
    expect(
      backend.requests.where((r) => r.url.path.contains('/patient/')),
      hasLength(2),
    );
  });

  testWidgets('a rejected upload is reported', (tester) async {
    final backend = _Backend(uploadCode: 500);
    await http.runWithClient(() async {
      await pumpWidget(tester);
      await upload(tester, find.text('Failed to upload file'));
    }, backend.client);
    expect(find.text('Failed to upload file'), findsOneWidget);
  });

  testWidgets('an image preview shows the downloaded image', (tester) async {
    final backend = _Backend(files: [
      {
        'id': 2,
        'originalFilename': 'scan.png',
        'contentType': 'image/png',
        'fileSize': 2048,
        'fileCategory': 'MEDICAL_NOTE',
        'ownerId': 3,
        'createdAt': '2026-01-02T03:04:05',
      },
    ]);
    await http.runWithClient(() async {
      await pumpWidget(tester);
      await tester.tap(find.text('scan.png'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }, backend.client);
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('Failed to load image'), findsNothing);
  });
}
