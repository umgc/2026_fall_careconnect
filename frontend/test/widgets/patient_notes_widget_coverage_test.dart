// Coverage tests for PatientNotesWidget (lib/widgets/patient_notes_widget.dart):
// the upload flow from the picker through the note details dialog
// (category change) to a successful or failed multipart upload. The picked
// file is a real temp file, so the upload's file reads run in
// tester.runAsync; HTTP goes through http.runWithClient.

import 'dart:convert';
import 'dart:io';

import 'package:care_connect_app/widgets/patient_notes_widget.dart';
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
  _Backend({this.uploadCode = 200});
  final int uploadCode;
  final requests = <http.BaseRequest>[];

  MockClient client() => MockClient((req) async {
        requests.add(req);
        if (req.url.path.endsWith('/upload')) {
          return uploadCode == 200
              ? http.Response(
                  jsonEncode({
                    'data': {
                      'fileId': 55,
                      'originalFilename': 'visit.txt',
                      'fileUrl': 'https://example.test/visit.txt',
                    },
                  }),
                  200)
              : http.Response('{"error":"rejected"}', uploadCode);
        }
        return http.Response(jsonEncode({'data': []}), 200);
      });
}

void main() {
  late _FakeFilePicker picker;
  late Directory dir;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FilePicker.platform = picker = _FakeFilePicker();
    dir = Directory.systemTemp.createTempSync('notes_cov_');
    final path = '${dir.path}${Platform.pathSeparator}visit.txt';
    File(path).writeAsStringSync('Visit summary');
    picker.result = FilePickerResult([
      PlatformFile(name: 'visit.txt', size: 13, path: path),
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
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: PatientNotesWidget(patientId: 4, patientName: 'Pat'),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> fillDialogAndUpload(WidgetTester tester, Finder done) async {
    await tester.tap(find.text('Add Note'));
    await tester.pumpAndSettle();
    expect(find.text('Patient Note Details'), findsOneWidget);
    // Title defaults to the picked file name.
    expect(find.widgetWithText(TextField, 'visit.txt'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Medications').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Description (Optional)'),
      'Follow-up',
    );
    await tester.tap(find.text('Upload'));
    await tester.pump();
    expect(find.text('Uploading...'), findsOneWidget);
    // Let the real file I/O run until the expected result appears.
    for (var i = 0; i < 250 && done.evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('a successful upload adds the note to the list',
      (tester) async {
    final backend = _Backend();
    await http.runWithClient(() async {
      await pumpWidget(tester);
      await fillDialogAndUpload(
          tester, find.text('Patient note uploaded successfully'));
    }, backend.client);
    final upload = backend.requests
        .whereType<http.Request>()
        .singleWhere((r) => r.url.path.endsWith('/upload'));
    expect(upload.url.path, endsWith('/users/4/upload'));
    expect(upload.headers['content-type'], startsWith('multipart/form-data'));
    expect(upload.body, contains('filename="visit.txt"'));
    expect(upload.body, contains('OTHER_DOCUMENT'));
    expect(find.text('Patient note uploaded successfully'), findsOneWidget);
    expect(find.text('Add Note'), findsOneWidget);
  });

  testWidgets('a rejected upload is reported', (tester) async {
    final backend = _Backend(uploadCode: 500);
    await http.runWithClient(() async {
      await pumpWidget(tester);
      await fillDialogAndUpload(
          tester, find.text('Failed to upload patient note'));
    }, backend.client);
    expect(find.text('Failed to upload patient note'), findsOneWidget);
    expect(find.text('Patient note uploaded successfully'), findsNothing);
  });
}
