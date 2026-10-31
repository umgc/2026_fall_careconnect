// Flow tests for EnhancedPatientNotesWidget and MedicalNotesWidget with a
// file list served by a MockClient: listing, show all/less, preview,
// download, delete, edit and the upload dialog.

import 'dart:convert';

import 'package:care_connect_app/widgets/enhanced_patient_notes_widget.dart';
import 'package:care_connect_app/widgets/medical_notes_widget.dart' as medical;
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
const _pathProvider = MethodChannel('plugins.flutter.io/path_provider');
const _urlLauncher = MethodChannel('plugins.flutter.io/url_launcher');

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

Map<String, dynamic> _file(
  int id,
  String name,
  String contentType, {
  String? description,
  int size = 512,
}) =>
    {
      'id': id,
      'originalFilename': name,
      'contentType': contentType,
      'fileSize': size,
      'fileCategory': 'MEDICAL_NOTE',
      'description': description,
      'ownerId': 3,
      'createdAt': '2026-01-02T03:04:05',
    };

final _files = [
  _file(1, 'report.pdf', 'application/pdf', description: 'Annual report'),
  _file(2, 'scan.png', 'image/png', size: 2048),
  _file(3, 'notes.txt', 'text/plain', size: 3 * 1024 * 1024),
  _file(4, 'letter.docx', 'application/msword'),
  _file(5, 'photo.jpeg', 'image/jpeg'),
  _file(6, 'other.bin', 'application/octet-stream'),
];

class _Backend {
  _Backend({
    this.deleteCode = 200,
    this.downloadCode = 200,
    List<Map<String, dynamic>>? files,
  }) : files = files ?? _files;

  final int deleteCode;
  final int downloadCode;
  final List<Map<String, dynamic>> files;
  final List<String> requests = <String>[];

  MockClient client() => MockClient((request) async {
        final path = request.url.path;
        requests.add('${request.method} $path');
        if (request.method == 'DELETE') {
          return http.Response('{"error":"nope"}', deleteCode);
        }
        if (path.endsWith('/download')) {
          return downloadCode == 200
              ? http.Response.bytes([1, 2, 3], 200)
              : http.Response('{"error":"missing"}', downloadCode);
        }
        if (path.contains('/patient/')) {
          return http.Response(jsonEncode({'data': files}), 200);
        }
        return http.Response('{}', 200);
      });
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child))),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _menu(WidgetTester tester, int index, String item) async {
  await tester.tap(find.byType(PopupMenuButton<String>).at(index));
  await tester.pumpAndSettle();
  await tester.tap(find.text(item).last);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  late List<MethodCall> launcherCalls;
  late bool canLaunch;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    launcherCalls = <MethodCall>[];
    canLaunch = true;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_secureStorage, (call) async {
      if (call.method == 'read' &&
          (call.arguments as Map)['key'] == 'jwt_token') {
        return 'jwt';
      }
      return null;
    });
    messenger.setMockMethodCallHandler(_pathProvider, (call) async => null);
    messenger.setMockMethodCallHandler(_urlLauncher, (call) async {
      launcherCalls.add(call);
      return call.method == 'canLaunch' ? canLaunch : true;
    });
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final channel in [_secureStorage, _pathProvider, _urlLauncher]) {
      messenger.setMockMethodCallHandler(channel, null);
    }
  });

  group('EnhancedPatientNotesWidget', () {
    late _FakeFilePicker picker;

    setUp(() => FilePicker.platform = picker = _FakeFilePicker());

    testWidgets('lists files and toggles between three and all',
        (tester) async {
      final backend = _Backend();
      await http.runWithClient(() async {
        await _pump(tester, const EnhancedPatientNotesWidget(patientId: 9));
        expect(find.text('report.pdf'), findsOneWidget);
        expect(find.text('Annual report'), findsOneWidget);
        expect(find.text('letter.docx'), findsNothing);
        expect(find.text('Show All (6 files)'), findsOneWidget);

        await tester.tap(find.text('Show All (6 files)'));
        await tester.pump();
        expect(find.text('letter.docx'), findsOneWidget);
        expect(find.textContaining('MB'), findsOneWidget);
        expect(find.textContaining('KB'), findsWidgets);

        await tester.tap(find.text('Show Less'));
        await tester.pump();
        expect(find.text('letter.docx'), findsNothing);
      }, backend.client);
    });

    testWidgets('compact view shows every file and reloads on a new patient',
        (tester) async {
      final backend = _Backend();
      await http.runWithClient(() async {
        await _pump(
          tester,
          const EnhancedPatientNotesWidget(patientId: 9, showCompactView: true),
        );
        expect(find.text('other.bin'), findsOneWidget);
        expect(find.textContaining('Show All'), findsNothing);
        await _pump(
          tester,
          const EnhancedPatientNotesWidget(
            patientId: 10,
            showCompactView: true,
          ),
        );
      }, backend.client);
      expect(
        backend.requests.where((r) => r.contains('/patient/')),
        hasLength(2),
      );
    });

    testWidgets('previewing a document offers a download', (tester) async {
      final backend = _Backend();
      await http.runWithClient(() async {
        await _pump(tester, const EnhancedPatientNotesWidget(patientId: 9));
        await _menu(tester, 0, 'Preview');
        expect(find.text('Document Preview'), findsOneWidget);
        expect(find.text('File: report.pdf'), findsOneWidget);
        await tester.tap(find.text('Download to View'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        // The host has no downloads directory in tests, so saving fails.
        expect(find.textContaining('Error downloading file'), findsOneWidget);
        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();
        expect(find.text('Document Preview'), findsNothing);
      }, backend.client);
    });

    testWidgets('previewing an image that cannot load says so', (tester) async {
      final backend = _Backend(downloadCode: 404);
      await http.runWithClient(() async {
        await _pump(tester, const EnhancedPatientNotesWidget(patientId: 9));
        await tester.tap(find.text('scan.png'));
        await tester.pump();
        expect(find.byType(CircularProgressIndicator), findsWidgets);
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('Failed to load image'), findsOneWidget);
      }, backend.client);
    });

    testWidgets('a non-previewable file is downloaded directly',
        (tester) async {
      final backend = _Backend(downloadCode: 404);
      await http.runWithClient(() async {
        await _pump(tester, const EnhancedPatientNotesWidget(patientId: 9));
        await tester.tap(find.text('notes.txt'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('Failed to download file'), findsOneWidget);
      }, backend.client);
    });

    testWidgets('download from the menu reports a save failure',
        (tester) async {
      final backend = _Backend();
      await http.runWithClient(() async {
        await _pump(tester, const EnhancedPatientNotesWidget(patientId: 9));
        await _menu(tester, 1, 'Download');
        expect(find.textContaining('Error downloading file'), findsOneWidget);
      }, backend.client);
    });

    testWidgets('deleting a file confirms, deletes and reloads',
        (tester) async {
      final backend = _Backend();
      await http.runWithClient(() async {
        await _pump(tester, const EnhancedPatientNotesWidget(patientId: 9));
        await _menu(tester, 0, 'Delete');
        expect(
          find.text('Are you sure you want to delete "report.pdf"?'),
          findsOneWidget,
        );
        await tester.tap(find.widgetWithText(ElevatedButton, 'Delete'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('File deleted successfully'), findsOneWidget);
      }, backend.client);
      expect(
        backend.requests.where((r) => r.contains('/patient/')),
        hasLength(2),
      );
    });

    testWidgets('a failed delete is reported and cancel does nothing',
        (tester) async {
      final backend = _Backend(deleteCode: 500);
      await http.runWithClient(() async {
        await _pump(tester, const EnhancedPatientNotesWidget(patientId: 9));
        await _menu(tester, 0, 'Delete');
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        await _menu(tester, 0, 'Delete');
        await tester.tap(find.widgetWithText(ElevatedButton, 'Delete'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('Failed to delete file'), findsOneWidget);
      }, backend.client);
      expect(
          backend.requests.where((r) => r.startsWith('DELETE')), hasLength(1));
    });

    testWidgets('upload dialog collects details and reports processing errors',
        (tester) async {
      picker.result = FilePickerResult([
        PlatformFile(name: 'new.pdf', size: 4, bytes: Uint8List(4)),
      ]);
      final backend = _Backend(files: const []);
      await http.runWithClient(() async {
        await _pump(tester, const EnhancedPatientNotesWidget(patientId: 9));
        expect(find.text('No files uploaded yet'), findsOneWidget);

        await tester.tap(find.text('Add File'));
        await tester.pumpAndSettle();
        expect(find.text('File Details'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Add File'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Medical Note'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Lab Result').last);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, 'Description (Optional)'),
          'Results',
        );
        // An empty title keeps the dialog open.
        await tester.enterText(find.widgetWithText(TextField, 'new.pdf'), '');
        await tester.tap(find.text('Upload'));
        await tester.pump();
        expect(find.text('File Details'), findsOneWidget);

        await tester.enterText(find.byType(TextField).first, 'New file');
        await tester.tap(find.text('Upload'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        // Native processing needs a file path, which a byte-only pick lacks.
        expect(find.textContaining('Error uploading file'), findsOneWidget);
      }, backend.client);
    });

    testWidgets('cancelling the picker uploads nothing', (tester) async {
      picker.result = null;
      final backend = _Backend(files: const []);
      await http.runWithClient(() async {
        await _pump(tester, const EnhancedPatientNotesWidget(patientId: 9));
        await tester.tap(find.text('Add File'));
        await tester.pumpAndSettle();
        expect(find.text('File Details'), findsNothing);
      }, backend.client);
    });
  });

  group('PatientNotesWidget (medical_notes_widget.dart)', () {
    setUp(() => FilePicker.platform = _FakeFilePicker());

    testWidgets('lists notes with icons, descriptions and uploader',
        (tester) async {
      final backend = _Backend();
      await http.runWithClient(() async {
        await _pump(
          tester,
          const medical.PatientNotesWidget(
            patientId: 9,
            patientName: 'Pat',
            filterCategory: 'labResult',
          ),
        );
        expect(find.text('report.pdf'), findsOneWidget);
        expect(find.text('Annual report'), findsOneWidget);
        expect(find.text('By: User 3'), findsWidgets);
        expect(find.byIcon(Icons.picture_as_pdf), findsOneWidget);
        expect(find.byIcon(Icons.image), findsNWidgets(2));
        expect(find.byIcon(Icons.text_snippet), findsOneWidget);
        expect(find.byIcon(Icons.description), findsOneWidget);
        expect(find.byIcon(Icons.attach_file), findsOneWidget);
      }, backend.client);
      expect(
        backend.requests.where((r) => r.contains('/patient/9')),
        isNotEmpty,
      );
    });

    testWidgets('filter categories map to backend categories', (tester) async {
      final backend = _Backend(files: const []);
      await http.runWithClient(() async {
        for (final category in const [
          'medicalNote',
          'appointment',
          'prescription',
          'generalNote',
          'careNote',
          'custom',
        ]) {
          await _pump(
            tester,
            medical.PatientNotesWidget(
              key: ValueKey(category),
              patientId: 9,
              patientName: 'Pat',
              filterCategory: category,
            ),
          );
        }
      }, backend.client);
      expect(
        backend.requests.where((r) => r.contains('/patient/')),
        hasLength(6),
      );
    });

    testWidgets('read-only empty state names the patient', (tester) async {
      final backend = _Backend(files: const []);
      await http.runWithClient(() async {
        await _pump(
          tester,
          const medical.PatientNotesWidget(
            patientId: 9,
            patientName: 'Pat',
            isReadOnly: true,
          ),
        );
        expect(
          find.text('No patient notes have been uploaded for Pat'),
          findsOneWidget,
        );
        expect(find.text('Upload Note'), findsNothing);
      }, backend.client);
    });

    testWidgets('read-only notes only offer download', (tester) async {
      final backend = _Backend();
      await http.runWithClient(() async {
        await _pump(
          tester,
          const medical.PatientNotesWidget(
            patientId: 9,
            patientName: 'Pat',
            isReadOnly: true,
          ),
        );
        await tester.tap(find.byType(PopupMenuButton<String>).first);
        await tester.pumpAndSettle();
        expect(find.text('Download'), findsOneWidget);
        expect(find.text('Edit'), findsNothing);
      }, backend.client);
    });

    testWidgets('download opens the file when it can be launched',
        (tester) async {
      final backend = _Backend();
      await http.runWithClient(() async {
        await _pump(
          tester,
          const medical.PatientNotesWidget(patientId: 9, patientName: 'Pat'),
        );
        await _menu(tester, 0, 'Download');
      }, backend.client);
      expect(launcherCalls.map((c) => c.method), contains('launch'));
    });

    testWidgets('download reports when the file cannot be opened',
        (tester) async {
      canLaunch = false;
      final backend = _Backend();
      await http.runWithClient(() async {
        await _pump(
          tester,
          const medical.PatientNotesWidget(patientId: 9, patientName: 'Pat'),
        );
        await _menu(tester, 0, 'Download');
        expect(find.text('Cannot open file'), findsOneWidget);
      }, backend.client);
    });

    testWidgets('download reports a missing link', (tester) async {
      final backend = _Backend(downloadCode: 404);
      await http.runWithClient(() async {
        await _pump(
          tester,
          const medical.PatientNotesWidget(patientId: 9, patientName: 'Pat'),
        );
        await _menu(tester, 0, 'Download');
        expect(find.text('Failed to get download link'), findsOneWidget);
      }, backend.client);
    });

    testWidgets('editing a note reports that the update failed',
        (tester) async {
      final backend = _Backend();
      await http.runWithClient(() async {
        await _pump(
          tester,
          const medical.PatientNotesWidget(patientId: 9, patientName: 'Pat'),
        );
        await _menu(tester, 0, 'Edit');
        expect(find.text('Edit Patient Note'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        await _menu(tester, 0, 'Edit');
        await tester.enterText(
          find.widgetWithText(TextField, 'Title *'),
          '',
        );
        await tester.tap(find.text('Save'));
        await tester.pump();
        expect(find.text('Edit Patient Note'), findsOneWidget);
        await tester.enterText(find.byType(TextField).first, 'Renamed');
        await tester.tap(find.text('Save'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        // The notes service does not support metadata updates yet.
        expect(find.text('Failed to update patient note'), findsOneWidget);
      }, backend.client);
    });

    testWidgets('deleting a note removes it from the list', (tester) async {
      final backend = _Backend();
      await http.runWithClient(() async {
        await _pump(
          tester,
          const medical.PatientNotesWidget(patientId: 9, patientName: 'Pat'),
        );
        await _menu(tester, 0, 'Delete');
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        await _menu(tester, 0, 'Delete');
        await tester.tap(find.widgetWithText(ElevatedButton, 'Delete'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('Patient note deleted successfully'), findsOneWidget);
        expect(find.text('report.pdf'), findsNothing);
      }, backend.client);
    });

    testWidgets('a failed note delete is reported', (tester) async {
      final backend = _Backend(deleteCode: 500);
      await http.runWithClient(() async {
        await _pump(
          tester,
          const medical.PatientNotesWidget(patientId: 9, patientName: 'Pat'),
        );
        await _menu(tester, 0, 'Delete');
        await tester.tap(find.widgetWithText(ElevatedButton, 'Delete'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('Failed to delete patient note'), findsOneWidget);
      }, backend.client);
    });

    testWidgets('upload is a no-op when no file is picked', (tester) async {
      final backend = _Backend(files: const []);
      await http.runWithClient(() async {
        await _pump(
          tester,
          const medical.PatientNotesWidget(patientId: 9, patientName: 'Pat'),
        );
        await tester.tap(find.text('Upload Note'));
        await tester.pump();
        expect(find.text('Note Details'), findsNothing);
      }, backend.client);
    });
  });
}
