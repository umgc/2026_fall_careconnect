// Additional coverage for ComprehensiveFileService: image-picker backed
// uploads (mocked image_picker channel), XFile uploads, picker failures and
// the employment document dropdown's initial selection.

import 'dart:convert';
import 'dart:io';

import 'package:care_connect_app/services/comprehensive_file_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

const _imagePickerChannel = MethodChannel('plugins.flutter.io/image_picker');

class _ThrowingFilePicker extends Fake
    with MockPlatformInterfaceMixin
    implements FilePicker {
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
      throw PlatformException(code: 'picker_failed');
}

MockClient _okClient(List<http.BaseRequest> seen) => MockClient((req) async {
      seen.add(req);
      return http.Response(
        jsonEncode({
          'data': {
            'fileId': 9,
            'originalFilename': 'pic.png',
            'fileUrl': 'u',
            'downloadUrl': 'd',
          },
        }),
        200,
      );
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  late File png;
  String? pickedPath;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('cfs_cov');
    png = File('${tmp.path}${Platform.pathSeparator}pic.png')
      ..writeAsBytesSync([1, 2, 3]);
    pickedPath = png.path;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_imagePickerChannel, (call) async {
      if (call.method == 'pickImage') return pickedPath;
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_imagePickerChannel, null);
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('profile image and prescription uploads use the image picker',
      () async {
    final seen = <http.BaseRequest>[];
    await http.runWithClient(() async {
      final profile =
          await ComprehensiveFileService.uploadProfileImage(userId: 1);
      expect(profile?.fileId, 9);
      final rx =
          await ComprehensiveFileService.uploadPrescription(patientId: 2);
      expect(rx?.fileId, 9);
      final fromXFile = await ComprehensiveFileService.uploadProfileImage(
          userId: 1, pickedFile: XFile(png.path));
      expect(fromXFile?.fileId, 9);
    }, () => _okClient(seen));
    expect(seen, hasLength(3));
    expect(seen.first.url.path, endsWith('/users/1/profile-image'));
  });

  test('cancelled image picks return null without uploading', () async {
    pickedPath = null;
    expect(await ComprehensiveFileService.uploadProfileImage(userId: 1),
        isNull);
    expect(await ComprehensiveFileService.uploadPrescription(patientId: 1),
        isNull);
  });

  test('pickFileForCategory returns picked images', () async {
    final profile = await ComprehensiveFileService.pickFileForCategory(
        FileCategory.profilePicture);
    expect(profile?.path, png.path);
    final rx = await ComprehensiveFileService.pickFileForCategory(
        FileCategory.prescription);
    expect(rx?.path, png.path);
  });

  test('picker failures are caught and return null', () async {
    FilePicker.platform = _ThrowingFilePicker();
    expect(
        await ComprehensiveFileService.pickFileForCategory(
            FileCategory.labResult),
        isNull);
    expect(
        await ComprehensiveFileService.pickFileForCategoryWeb(
            FileCategory.labResult),
        isNull);
    expect(await ComprehensiveFileService.uploadMedicalDocument(patientId: 3),
        isNull);
  });

  testWidgets('employment dropdown honours a valid initial type',
      (tester) async {
    final intake = FileCategory.employmentIntake.last;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: EmploymentDocumentTypeDropdown(initialType: intake),
      ),
    ));
    expect(find.textContaining(intake.displayName), findsWidgets);
  });
}
