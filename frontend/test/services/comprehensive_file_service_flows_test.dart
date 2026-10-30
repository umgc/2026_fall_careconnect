// Flow tests for ComprehensiveFileService
// (lib/services/comprehensive_file_service.dart): multipart uploads for each
// document kind, export/import, file picking through a fake FilePicker,
// category validation and the category dropdown widgets.
// MultipartRequest.send() creates its client through package:http, so
// http.runWithClient intercepts uploads too.

import 'dart:convert';
import 'dart:io';

import 'package:care_connect_app/services/comprehensive_file_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakeFilePicker extends Fake
    with MockPlatformInterfaceMixin
    implements FilePicker {
  _FakeFilePicker(this.path);
  final String? path;

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
      path == null
          ? null
          : FilePickerResult(
              [PlatformFile(name: 'doc.pdf', size: 4, path: path)]);
}

final List<http.BaseRequest> _requests = [];

MockClient _client({int status = 200}) => MockClient((req) async {
      _requests.add(req);
      if (status != 200) {
        return http.Response(jsonEncode({'error': 'nope'}), status);
      }
      if (req.url.path.contains('/export')) {
        return http.Response.bytes([1, 2, 3], 200);
      }
      return http.Response(
          jsonEncode({
            'data': {
              'fileId': 5,
              'originalFilename': 'doc.pdf',
              'fileUrl': 'u',
              'downloadUrl': 'd',
            }
          }),
          200);
    });

void main() {
  late Directory tmp;
  late File pdf;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  setUp(() {
    _requests.clear();
    FlutterSecureStorage.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('cfs_flows');
    pdf = File('${tmp.path}${Platform.pathSeparator}doc.pdf')
      ..writeAsBytesSync([1, 2, 3, 4]);
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('every upload kind posts a multipart request', () async {
    await http.runWithClient(() async {
      expect(
          (await ComprehensiveFileService.uploadProfileImage(
                  userId: 1, imageFile: pdf))
              ?.fileId,
          5);
      expect(
          await ComprehensiveFileService.uploadMedicalDocument(
              patientId: 2, documentFile: pdf, description: 'labs'),
          isNotNull);
      expect(
          await ComprehensiveFileService.uploadClinicalNotesAttachment(
              patientId: 2, attachmentFile: pdf),
          isNotNull);
      expect(
          await ComprehensiveFileService.uploadChatFile(chatFile: pdf),
          isNotNull);
      expect(
          await ComprehensiveFileService.uploadPrescription(
              patientId: 2, prescriptionFile: pdf),
          isNotNull);
      expect(
          await ComprehensiveFileService.uploadEmergencyContactDocument(
              userId: 1, documentFile: pdf),
          isNotNull);
      expect(
          await ComprehensiveFileService.uploadInsuranceDocument(
              patientId: 2, insuranceFile: pdf),
          isNotNull);
      expect(
          await ComprehensiveFileService.uploadEmploymentDocument(
            documentFile: pdf,
            documentType: FileCategory.taxForm,
            patientId: 2,
            careCircleId: 3,
          ),
          isNotNull);
      expect(
          await ComprehensiveFileService.uploadBackupFile(
              backupFile: pdf, backupType: 'full'),
          isNotNull);
      final imported = await ComprehensiveFileService.importBulkHealthData(
          dataFile: pdf, validateOnly: true);
      expect(imported?['success'], isTrue);
      expect(
          await ComprehensiveFileService.exportUserDataWithFiles(
              userId: 1, includeFiles: false),
          [1, 2, 3]);
    }, () => _client());
    expect(_requests.length, 11);
    // MockClient flattens the multipart body into a plain request.
    final intake = (_requests[7] as http.Request).body;
    expect(intake, contains(FileCategory.taxForm.value));
    expect(intake, contains('careCircleId'));
  });

  test('upload and export failures return null', () async {
    await http.runWithClient(() async {
      expect(
          await ComprehensiveFileService.uploadChatFile(chatFile: pdf),
          isNull);
      expect(
          await ComprehensiveFileService.importBulkHealthData(dataFile: pdf),
          isNull);
      expect(
          await ComprehensiveFileService.exportUserDataWithFiles(userId: 1),
          isNull);
    }, () => _client(status: 500));
    // Non-intake document types are rejected before any request.
    expect(
      await ComprehensiveFileService.uploadEmploymentDocument(
        documentFile: pdf,
        documentType: FileCategory.labResult,
      ),
      isNull,
    );
  });

  test('picker-backed upload and category picking', () async {
    FilePicker.platform = _FakeFilePicker(pdf.path);
    await http.runWithClient(() async {
      expect(
          await ComprehensiveFileService.uploadMedicalDocument(patientId: 2),
          isNotNull);
    }, () => _client());
    expect(
        await ComprehensiveFileService.pickFileForCategory(
            FileCategory.labResult),
        isNull);
    expect(
        await ComprehensiveFileService.pickFileForCategory(
            FileCategory.backupFile),
        isNull);
    expect(
        await ComprehensiveFileService.pickFileForCategoryWeb(
            FileCategory.medicalReport),
        isNull);
    expect(
        await ComprehensiveFileService.pickFileForCategoryWeb(
            FileCategory.backupFile),
        isNull);

    FilePicker.platform = _FakeFilePicker(null);
    expect(
        await ComprehensiveFileService.uploadMedicalDocument(patientId: 2),
        isNull);
    expect(
        await ComprehensiveFileService.pickFileForCategory(
            FileCategory.insuranceDoc),
        isNull);
    expect(
        await ComprehensiveFileService.pickFileForCategory(
            FileCategory.backupFile),
        isNull);
    expect(
        await ComprehensiveFileService.pickFileForCategoryWeb(
            FileCategory.labResult),
        isNull);
    expect(
        await ComprehensiveFileService.pickFileForCategoryWeb(
            FileCategory.backupFile),
        isNull);
  });

  test('validateFileForCategory checks extensions by category', () {
    File make(String name) =>
        File('${tmp.path}${Platform.pathSeparator}$name')
          ..writeAsBytesSync([0]);
    final png = make('a.png');
    final txt = make('a.txt');
    final exe = make('a.exe');
    expect(ComprehensiveFileService.validateFileForCategory(
        png, FileCategory.profilePicture), isTrue);
    expect(ComprehensiveFileService.validateFileForCategory(
        txt, FileCategory.profilePicture), isFalse);
    expect(ComprehensiveFileService.validateFileForCategory(
        txt, FileCategory.prescription), isTrue);
    expect(ComprehensiveFileService.validateFileForCategory(
        exe, FileCategory.medicalReport), isFalse);
    expect(ComprehensiveFileService.validateFileForCategory(
        exe, FileCategory.backupFile), isTrue);
  });

  group('dropdowns', () {
    testWidgets('FileCategoryDropdown lists and selects categories',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: FileCategoryDropdown(allowedCategories: [
            FileCategory.labResult,
            FileCategory.prescription,
          ]),
        ),
      ));
      await tester.tap(find.byType(DropdownButtonFormField<FileCategory>));
      await tester.pumpAndSettle();
      await tester.tap(find
          .textContaining(FileCategory.prescription.displayName)
          .last);
      await tester.pumpAndSettle();
      expect(find.textContaining(FileCategory.prescription.displayName),
          findsOneWidget);

      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: FileCategoryDropdown()),
      ));
      expect(find.byType(DropdownButtonFormField<FileCategory>),
          findsOneWidget);
    });

    testWidgets('EmploymentDocumentTypeDropdown reports changes',
        (tester) async {
      FileCategory? chosen;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: EmploymentDocumentTypeDropdown(
            initialType: FileCategory.labResult,
            onChanged: (c) => chosen = c,
          ),
        ),
      ));
      await tester.tap(find.byType(DropdownButtonFormField<FileCategory>));
      await tester.pumpAndSettle();
      await tester
          .tap(find.textContaining(FileCategory.taxForm.displayName).last);
      await tester.pumpAndSettle();
      expect(chosen, FileCategory.taxForm);
    });
  });
}
