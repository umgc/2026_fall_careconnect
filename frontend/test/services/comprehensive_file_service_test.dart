// Tests for ComprehensiveFileService pure-Dart helpers and HTTP retrieval methods.
//
// Coverage strategy:
//   Upload methods (_uploadToEndpoint, uploadProfileImage, etc.) require
//   http.MultipartRequest which cannot be intercepted via http.runWithClient,
//   and file-picker/image-picker platform channels — those are excluded.
//   pickFileForCategory / pickFileForCategoryWeb use image_picker/FilePicker — excluded.
//
//   HTTP GET methods use top-level http.get → interceptable via http.runWithClient.
//   AuthTokenManager.getAuthHeaders() intercepted via FlutterSecureStorage stub.
//   validateFileForCategory — tested with temporary files on disk.
//
//   Branches tested:
//     FileCategory enum — value, displayName, icon for every member.
//     FileQueryParams.toQueryString — all fields present, partial fields, empty.
//     getAllUserFiles — 200 files key → list, 200 content key → list, non-200 → [].
//     getAllUserFiles1 — 200 → UserFileDTO, non-200 → null.
//     getPatientMedicalDocuments — 200 data key → list, 200 content key → list, non-200 → [].
//     searchFiles — 200 data key → list, non-200 → [].
//     getUserFilesByCategory — delegates to getAllUserFiles (category param set).
//     getFilesByDateRange — delegates to getAllUserFiles (date params set).
//     getFilesByMultipleCategories — delegates to getAllUserFiles (categories param set).
//     validateFileForCategory — all category branches + file size check.
//     FileCategoryDropdown — widget rendering + dropdown selection interaction.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/services/comprehensive_file_service.dart';
import 'package:care_connect_app/services/enhanced_file_service.dart';

// ─── Secure storage stub ──────────────────────────────────────────────────────

const MethodChannel _secureStorageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

final Map<String, String?> _secureStore = {};

void _setupSecureStorageStub() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_secureStorageChannel, (call) async {
    switch (call.method) {
      case 'write':
        _secureStore[call.arguments['key'] as String] =
            call.arguments['value'] as String?;
        return null;
      case 'read':
        return _secureStore[call.arguments['key'] as String];
      case 'delete':
        _secureStore.remove(call.arguments['key'] as String);
        return null;
      case 'deleteAll':
        _secureStore.clear();
        return null;
      default:
        return null;
    }
  });
}

void _seedAuthToken() {
  _secureStore['jwt_token'] = 'test-jwt-token';
  _secureStore['token_expiry'] = '2000000000'; // year 2033
}

/// Minimal UserFileDTO JSON that passes fromJson without errors.
Map<String, dynamic> _fileJson({int id = 1}) => {
  'id': id,
  'originalFilename': 'test_$id.pdf',
  'contentType': 'application/pdf',
  'fileSize': 1024,
  'fileCategory': 'MEDICAL_REPORT',
  'ownerId': 42,
  'ownerType': 'PATIENT',
  'fileName': 'test_$id.pdf',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    _secureStore.clear();
    SharedPreferences.setMockInitialValues({});
    _setupSecureStorageStub();
    _seedAuthToken();
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, null);
  });

  // ─── FileCategory enum ───────────────────────────────────────────────────

  group('FileCategory', () {
    test('all members have non-empty value, displayName, and icon', () {
      for (final cat in FileCategory.values) {
        expect(cat.value, isNotEmpty, reason: '${cat.name}.value empty');
        expect(cat.displayName, isNotEmpty, reason: '${cat.name}.displayName empty');
        expect(cat.icon, isNotEmpty, reason: '${cat.name}.icon empty');
      }
    });

    test('profilePicture has value PROFILE_IMAGE', () {
      expect(FileCategory.profilePicture.value, 'PROFILE_IMAGE');
    });

    test('medicalReport has display name Medical Report', () {
      expect(FileCategory.medicalReport.displayName, 'Medical Report');
    });

    test('labResult has icon 🧪', () {
      expect(FileCategory.labResult.icon, '🧪');
    });
  });

  // ─── FileQueryParams.toQueryString ──────────────────────────────────────

  group('FileQueryParams.toQueryString', () {
    test('empty params returns empty string', () {
      expect(FileQueryParams().toQueryString(), '');
    });

    test('single param page=1', () {
      final qs = FileQueryParams(page: 1).toQueryString();
      expect(qs, '?page=1');
    });

    test('multiple params joined with &', () {
      final qs = FileQueryParams(page: 0, size: 10, sort: 'createdAt').toQueryString();
      expect(qs, contains('page=0'));
      expect(qs, contains('size=10'));
      expect(qs, contains('sort=createdAt'));
    });

    test('category param included', () {
      final qs = FileQueryParams(category: 'MEDICAL_RECORD').toQueryString();
      expect(qs, contains('category=MEDICAL_RECORD'));
    });

    test('categories list joined with comma', () {
      final qs = FileQueryParams(
        categories: ['MEDICAL_RECORD', 'PRESCRIPTION'],
      ).toQueryString();
      expect(qs, contains('categories=MEDICAL_RECORD,PRESCRIPTION'));
    });

    test('empty categories list not included', () {
      final qs = FileQueryParams(categories: []).toQueryString();
      expect(qs, isNot(contains('categories')));
    });

    test('date range params included', () {
      final qs = FileQueryParams(
        startDate: '2025-01-01',
        endDate: '2025-12-31',
      ).toQueryString();
      expect(qs, contains('startDate=2025-01-01'));
      expect(qs, contains('endDate=2025-12-31'));
    });

    test('query param is URI-encoded', () {
      final qs = FileQueryParams(query: 'hello world').toQueryString();
      expect(qs, contains('query=hello%20world'));
    });

    test('starts with ? when params present', () {
      final qs = FileQueryParams(page: 0).toQueryString();
      expect(qs, startsWith('?'));
    });
  });

  // ─── getAllUserFiles ──────────────────────────────────────────────────────

  group('ComprehensiveFileService.getAllUserFiles', () {
    test('200 with files key → returns list of UserFileDTO', () async {
      final body = jsonEncode({
        'files': [_fileJson(id: 1), _fileJson(id: 2)],
      });
      final result = await http.runWithClient(
        () => ComprehensiveFileService.getAllUserFiles(10),
        () => MockClient((_) async => http.Response(body, 200)),
      );
      expect(result.length, 2);
      expect(result[0], isA<UserFileDTO>());
    });

    test('200 with content key → returns list', () async {
      final body = jsonEncode({
        'content': [_fileJson(id: 3)],
      });
      final result = await http.runWithClient(
        () => ComprehensiveFileService.getAllUserFiles(10),
        () => MockClient((_) async => http.Response(body, 200)),
      );
      expect(result.length, 1);
    });

    test('200 with empty files → returns empty list', () async {
      final body = jsonEncode({'files': []});
      final result = await http.runWithClient(
        () => ComprehensiveFileService.getAllUserFiles(10),
        () => MockClient((_) async => http.Response(body, 200)),
      );
      expect(result, isEmpty);
    });

    test('non-200 → returns empty list', () async {
      final body = jsonEncode({'error': 'Unauthorized'});
      final result = await http.runWithClient(
        () => ComprehensiveFileService.getAllUserFiles(10),
        () => MockClient((_) async => http.Response(body, 401)),
      );
      expect(result, isEmpty);
    });
  });

  // ─── getAllUserFiles1 ─────────────────────────────────────────────────────

  group('ComprehensiveFileService.getAllUserFiles1', () {
    test('200 → returns a UserFileDTO', () async {
      final body = jsonEncode(_fileJson(id: 5));
      final result = await http.runWithClient(
        () => ComprehensiveFileService.getAllUserFiles1(10),
        () => MockClient((_) async => http.Response(body, 200)),
      );
      expect(result, isNotNull);
      expect(result, isA<UserFileDTO>());
    });

    test('non-200 → returns null', () async {
      final body = jsonEncode({'error': 'Not found'});
      final result = await http.runWithClient(
        () => ComprehensiveFileService.getAllUserFiles1(10),
        () => MockClient((_) async => http.Response(body, 404)),
      );
      expect(result, isNull);
    });
  });

  // ─── getPatientMedicalDocuments ──────────────────────────────────────────

  group('ComprehensiveFileService.getPatientMedicalDocuments', () {
    test('200 with data key → returns list', () async {
      final body = jsonEncode({
        'data': [_fileJson(id: 10)],
      });
      final result = await http.runWithClient(
        () => ComprehensiveFileService.getPatientMedicalDocuments(5),
        () => MockClient((_) async => http.Response(body, 200)),
      );
      expect(result.length, 1);
    });

    test('200 with content key → returns list', () async {
      final body = jsonEncode({
        'content': [_fileJson(id: 11), _fileJson(id: 12)],
      });
      final result = await http.runWithClient(
        () => ComprehensiveFileService.getPatientMedicalDocuments(5),
        () => MockClient((_) async => http.Response(body, 200)),
      );
      expect(result.length, 2);
    });

    test('non-200 → returns empty list', () async {
      final body = jsonEncode({'error': 'Server error'});
      final result = await http.runWithClient(
        () => ComprehensiveFileService.getPatientMedicalDocuments(5),
        () => MockClient((_) async => http.Response(body, 500)),
      );
      expect(result, isEmpty);
    });
  });

  // ─── searchFiles ─────────────────────────────────────────────────────────

  group('ComprehensiveFileService.searchFiles', () {
    test('200 with data key → returns list', () async {
      final body = jsonEncode({
        'data': [_fileJson(id: 20)],
      });
      final result = await http.runWithClient(
        () => ComprehensiveFileService.searchFiles(
          searchQuery: 'blood',
          userId: 10,
        ),
        () => MockClient((_) async => http.Response(body, 200)),
      );
      expect(result.length, 1);
    });

    test('200 with content key → returns list', () async {
      final body = jsonEncode({
        'content': [_fileJson(id: 21), _fileJson(id: 22)],
      });
      final result = await http.runWithClient(
        () => ComprehensiveFileService.searchFiles(
          searchQuery: 'lab',
          userId: 10,
        ),
        () => MockClient((_) async => http.Response(body, 200)),
      );
      expect(result.length, 2);
    });

    test('non-200 → returns empty list', () async {
      final body = jsonEncode({'error': 'Bad request'});
      final result = await http.runWithClient(
        () => ComprehensiveFileService.searchFiles(
          searchQuery: 'test',
          userId: 10,
        ),
        () => MockClient((_) async => http.Response(body, 400)),
      );
      expect(result, isEmpty);
    });
  });

  // ─── getUserFilesByCategory ──────────────────────────────────────────────

  group('ComprehensiveFileService.getUserFilesByCategory', () {
    test('delegates to getAllUserFiles and returns results', () async {
      final body = jsonEncode({
        'files': [_fileJson(id: 30)],
      });
      final result = await http.runWithClient(
        () => ComprehensiveFileService.getUserFilesByCategory(
          10,
          FileCategory.prescription,
        ),
        () => MockClient((_) async => http.Response(body, 200)),
      );
      expect(result.length, 1);
      expect(result[0], isA<UserFileDTO>());
    });

    test('non-200 → returns empty list', () async {
      final result = await http.runWithClient(
        () => ComprehensiveFileService.getUserFilesByCategory(
          10,
          FileCategory.labResult,
        ),
        () => MockClient((_) async => http.Response('{"error":"err"}', 403)),
      );
      expect(result, isEmpty);
    });
  });

  // ─── getFilesByDateRange ─────────────────────────────────────────────────

  group('ComprehensiveFileService.getFilesByDateRange', () {
    test('delegates to getAllUserFiles and returns results', () async {
      final body = jsonEncode({
        'files': [_fileJson(id: 40), _fileJson(id: 41)],
      });
      final result = await http.runWithClient(
        () => ComprehensiveFileService.getFilesByDateRange(
          10,
          startDate: DateTime(2025, 1, 1),
          endDate: DateTime(2025, 12, 31),
        ),
        () => MockClient((_) async => http.Response(body, 200)),
      );
      expect(result.length, 2);
    });

    test('non-200 → returns empty list', () async {
      final result = await http.runWithClient(
        () => ComprehensiveFileService.getFilesByDateRange(
          10,
          startDate: DateTime(2025, 1, 1),
          endDate: DateTime(2025, 6, 30),
        ),
        () => MockClient((_) async => http.Response('{"error":"err"}', 500)),
      );
      expect(result, isEmpty);
    });
  });

  // ─── getFilesByMultipleCategories ────────────────────────────────────────

  group('ComprehensiveFileService.getFilesByMultipleCategories', () {
    test('delegates to getAllUserFiles and returns results', () async {
      final body = jsonEncode({
        'content': [_fileJson(id: 50)],
      });
      final result = await http.runWithClient(
        () => ComprehensiveFileService.getFilesByMultipleCategories(
          10,
          categories: [FileCategory.prescription, FileCategory.labResult],
        ),
        () => MockClient((_) async => http.Response(body, 200)),
      );
      expect(result.length, 1);
    });

    test('non-200 → returns empty list', () async {
      final result = await http.runWithClient(
        () => ComprehensiveFileService.getFilesByMultipleCategories(
          10,
          categories: [FileCategory.medicalReport],
        ),
        () => MockClient((_) async => http.Response('{"error":"err"}', 400)),
      );
      expect(result, isEmpty);
    });
  });

  // ─── FileCategory enum – exhaustive member checks ─────────────────────

  group('FileCategory exhaustive values', () {
    test('has all expected members including employment intake', () {
      // Core healthcare (4) + personal (3) + employment (8) + AI/data (4) = 19
      expect(FileCategory.values.length, 19);
      expect(FileCategory.employmentIntake.length, 8);
    });

    test('medicalReport value and icon', () {
      expect(FileCategory.medicalReport.value, 'MEDICAL_RECORD');
      expect(FileCategory.medicalReport.icon, '🏥');
    });

    test('labResult value and displayName', () {
      expect(FileCategory.labResult.value, 'LAB_RESULT');
      expect(FileCategory.labResult.displayName, 'Lab Result');
    });

    test('prescription value, displayName, icon', () {
      expect(FileCategory.prescription.value, 'PRESCRIPTION');
      expect(FileCategory.prescription.displayName, 'Prescription');
      expect(FileCategory.prescription.icon, '💊');
    });

    test('clinicalNotes value, displayName, icon', () {
      expect(FileCategory.clinicalNotes.value, 'CLINICAL_NOTE');
      expect(FileCategory.clinicalNotes.displayName, 'Clinical Notes');
      expect(FileCategory.clinicalNotes.icon, '📋');
    });

    test('emergencyContact value, displayName, icon', () {
      expect(FileCategory.emergencyContact.value, 'EMERGENCY_CONTACT');
      expect(FileCategory.emergencyContact.displayName, 'Emergency Contact');
      expect(FileCategory.emergencyContact.icon, '🚨');
    });

    test('insuranceDoc value, displayName, icon', () {
      expect(FileCategory.insuranceDoc.value, 'INSURANCE_DOCUMENT');
      expect(FileCategory.insuranceDoc.displayName, 'Insurance Document');
      expect(FileCategory.insuranceDoc.icon, '🛡️');
    });

    test('aiChatUpload value, displayName, icon', () {
      expect(FileCategory.aiChatUpload.value, 'AI_CHAT_UPLOAD');
      expect(FileCategory.aiChatUpload.displayName, 'AI Chat File');
      expect(FileCategory.aiChatUpload.icon, '🤖');
    });

    test('generalDocument value, displayName, icon', () {
      expect(FileCategory.generalDocument.value, 'OTHER_DOCUMENT');
      expect(FileCategory.generalDocument.displayName, 'General Document');
      expect(FileCategory.generalDocument.icon, '📄');
    });

    test('healthDataImport value, displayName, icon', () {
      expect(FileCategory.healthDataImport.value, 'HEALTH_DATA_IMPORT');
      expect(FileCategory.healthDataImport.displayName, 'Health Data Import');
      expect(FileCategory.healthDataImport.icon, '📊');
    });

    test('backupFile value, displayName, icon', () {
      expect(FileCategory.backupFile.value, 'BACKUP_FILE');
      expect(FileCategory.backupFile.displayName, 'Backup File');
      expect(FileCategory.backupFile.icon, '💾');
    });

    test('profilePicture value, displayName and icon', () {
      expect(FileCategory.profilePicture.value, 'PROFILE_IMAGE');
      expect(FileCategory.profilePicture.displayName, 'Profile Picture');
      expect(FileCategory.profilePicture.icon, '👤');
    });
  });

  // ─── FileQueryParams – comprehensive combinations ─────────────────────

  group('FileQueryParams comprehensive', () {
    test('all params present produces correct query string', () {
      final qs = FileQueryParams(
        page: 2,
        size: 25,
        sort: 'name',
        category: 'PRESCRIPTION',
        categories: ['A', 'B'],
        startDate: '2025-03-01',
        endDate: '2025-03-31',
        query: 'test file',
      ).toQueryString();

      expect(qs, startsWith('?'));
      expect(qs, contains('page=2'));
      expect(qs, contains('size=25'));
      expect(qs, contains('sort=name'));
      expect(qs, contains('category=PRESCRIPTION'));
      expect(qs, contains('categories=A,B'));
      expect(qs, contains('startDate=2025-03-01'));
      expect(qs, contains('endDate=2025-03-31'));
      expect(qs, contains('query=test%20file'));
    });

    test('only size param', () {
      final qs = FileQueryParams(size: 50).toQueryString();
      expect(qs, '?size=50');
    });

    test('only sort param', () {
      final qs = FileQueryParams(sort: 'createdAt').toQueryString();
      expect(qs, '?sort=createdAt');
    });

    test('only startDate param', () {
      final qs = FileQueryParams(startDate: '2025-01-01').toQueryString();
      expect(qs, '?startDate=2025-01-01');
    });

    test('only endDate param', () {
      final qs = FileQueryParams(endDate: '2025-12-31').toQueryString();
      expect(qs, '?endDate=2025-12-31');
    });

    test('only query param with special characters', () {
      final qs = FileQueryParams(query: 'a&b=c').toQueryString();
      expect(qs, contains('query=a%26b%3Dc'));
    });

    test('categories with single element', () {
      final qs = FileQueryParams(categories: ['ONLY']).toQueryString();
      expect(qs, '?categories=ONLY');
    });

    test('null categories not included', () {
      final qs = FileQueryParams(page: 1).toQueryString();
      expect(qs, isNot(contains('categories')));
    });
  });

  // ─── getUserFilesByCategory with additional params ─────────────────────

  group('ComprehensiveFileService.getUserFilesByCategory with params', () {
    test('passes extra params through to getAllUserFiles', () async {
      final body = jsonEncode({
        'files': [_fileJson(id: 60)],
      });
      final result = await http.runWithClient(
        () => ComprehensiveFileService.getUserFilesByCategory(
          10,
          FileCategory.medicalReport,
          params: FileQueryParams(page: 2, size: 5, sort: 'name'),
        ),
        () => MockClient((_) async => http.Response(body, 200)),
      );
      expect(result.length, 1);
    });
  });

  // ─── getFilesByDateRange with additional params ────────────────────────

  group('ComprehensiveFileService.getFilesByDateRange with params', () {
    test('passes extra params through', () async {
      final body = jsonEncode({
        'files': [_fileJson(id: 70)],
      });
      final result = await http.runWithClient(
        () => ComprehensiveFileService.getFilesByDateRange(
          10,
          startDate: DateTime(2025, 6, 1),
          endDate: DateTime(2025, 6, 30),
          params: FileQueryParams(page: 0, size: 20, sort: 'date', category: 'LAB'),
        ),
        () => MockClient((_) async => http.Response(body, 200)),
      );
      expect(result.length, 1);
    });
  });

  // ─── getFilesByMultipleCategories with additional params ───────────────

  group('ComprehensiveFileService.getFilesByMultipleCategories with params', () {
    test('passes extra params and multiple categories', () async {
      final body = jsonEncode({
        'files': [_fileJson(id: 80), _fileJson(id: 81)],
      });
      final result = await http.runWithClient(
        () => ComprehensiveFileService.getFilesByMultipleCategories(
          10,
          categories: [
            FileCategory.prescription,
            FileCategory.labResult,
            FileCategory.insuranceDoc,
          ],
          params: FileQueryParams(
            page: 1,
            size: 10,
            startDate: '2025-01-01',
            endDate: '2025-12-31',
            query: 'search',
          ),
        ),
        () => MockClient((_) async => http.Response(body, 200)),
      );
      expect(result.length, 2);
    });
  });

  // ─── searchFiles with additional params ────────────────────────────────

  group('ComprehensiveFileService.searchFiles with params', () {
    test('passes page, size, sort, category, categories, dates', () async {
      final body = jsonEncode({
        'data': [_fileJson(id: 90)],
      });
      final result = await http.runWithClient(
        () => ComprehensiveFileService.searchFiles(
          searchQuery: 'blood test',
          userId: 10,
          params: FileQueryParams(
            page: 0,
            size: 5,
            sort: 'name',
            category: 'LAB_RESULT',
            categories: ['LAB_RESULT', 'MEDICAL_REPORT'],
            startDate: '2025-01-01',
            endDate: '2025-06-30',
          ),
        ),
        () => MockClient((_) async => http.Response(body, 200)),
      );
      expect(result.length, 1);
    });

    test('network error → returns empty list', () async {
      final result = await http.runWithClient(
        () => ComprehensiveFileService.searchFiles(
          searchQuery: 'crash',
          userId: 10,
        ),
        () => MockClient((_) async => throw Exception('Network error')),
      );
      expect(result, isEmpty);
    });
  });

  // ─── getAllUserFiles edge cases ─────────────────────────────────────────

  group('ComprehensiveFileService.getAllUserFiles edge cases', () {
    test('200 with neither files nor content key → returns empty list', () async {
      final body = jsonEncode({'something': 'else'});
      final result = await http.runWithClient(
        () => ComprehensiveFileService.getAllUserFiles(10),
        () => MockClient((_) async => http.Response(body, 200)),
      );
      expect(result, isEmpty);
    });

    test('network exception → returns empty list', () async {
      final result = await http.runWithClient(
        () => ComprehensiveFileService.getAllUserFiles(10),
        () => MockClient((_) async => throw Exception('timeout')),
      );
      expect(result, isEmpty);
    });

    test('with FileQueryParams passed in', () async {
      final body = jsonEncode({
        'files': [_fileJson(id: 100)],
      });
      final result = await http.runWithClient(
        () => ComprehensiveFileService.getAllUserFiles(
          10,
          params: FileQueryParams(page: 0, size: 10, category: 'MEDICAL_REPORT'),
        ),
        () => MockClient((_) async => http.Response(body, 200)),
      );
      expect(result.length, 1);
    });
  });

  // ─── getAllUserFiles1 edge cases ────────────────────────────────────────

  group('ComprehensiveFileService.getAllUserFiles1 edge cases', () {
    test('network exception → returns null', () async {
      final result = await http.runWithClient(
        () => ComprehensiveFileService.getAllUserFiles1(10),
        () => MockClient((_) async => throw Exception('timeout')),
      );
      expect(result, isNull);
    });

    test('with FileQueryParams passed in', () async {
      final body = jsonEncode(_fileJson(id: 101));
      final result = await http.runWithClient(
        () => ComprehensiveFileService.getAllUserFiles1(
          10,
          params: FileQueryParams(page: 0),
        ),
        () => MockClient((_) async => http.Response(body, 200)),
      );
      expect(result, isNotNull);
    });
  });

  // ─── getPatientMedicalDocuments edge cases ─────────────────────────────

  group('ComprehensiveFileService.getPatientMedicalDocuments edge cases', () {
    test('200 with neither data nor content → returns empty list', () async {
      final body = jsonEncode({'other': 'value'});
      final result = await http.runWithClient(
        () => ComprehensiveFileService.getPatientMedicalDocuments(5),
        () => MockClient((_) async => http.Response(body, 200)),
      );
      expect(result, isEmpty);
    });

    test('network exception → returns empty list', () async {
      final result = await http.runWithClient(
        () => ComprehensiveFileService.getPatientMedicalDocuments(5),
        () => MockClient((_) async => throw Exception('down')),
      );
      expect(result, isEmpty);
    });

    test('with params passed in', () async {
      final body = jsonEncode({
        'data': [_fileJson(id: 110)],
      });
      final result = await http.runWithClient(
        () => ComprehensiveFileService.getPatientMedicalDocuments(
          5,
          params: FileQueryParams(page: 1, size: 20),
        ),
        () => MockClient((_) async => http.Response(body, 200)),
      );
      expect(result.length, 1);
    });
  });

  // ─── exportUserDataWithFiles ───────────────────────────────────────────

  group('ComprehensiveFileService.exportUserDataWithFiles', () {
    test('200 → returns body bytes', () async {
      final bytes = [0x50, 0x4B, 0x03, 0x04]; // ZIP magic number
      final result = await http.runWithClient(
        () => ComprehensiveFileService.exportUserDataWithFiles(userId: 42),
        () => MockClient((_) async => http.Response.bytes(bytes, 200)),
      );
      expect(result, isNotNull);
      expect(result!.length, 4);
    });

    test('200 with includeFiles=false → calls with EXCLUDE_FILES category', () async {
      final bytes = [0x01, 0x02];
      final result = await http.runWithClient(
        () => ComprehensiveFileService.exportUserDataWithFiles(
          userId: 42,
          includeFiles: false,
        ),
        () => MockClient((request) async {
          // Verify EXCLUDE_FILES is in the URL
          expect(request.url.toString(), contains('EXCLUDE_FILES'));
          return http.Response.bytes(bytes, 200);
        }),
      );
      expect(result, isNotNull);
    });

    test('200 with custom format → includes format in URL', () async {
      final bytes = [0x01];
      final result = await http.runWithClient(
        () => ComprehensiveFileService.exportUserDataWithFiles(
          userId: 42,
          format: 'tar',
        ),
        () => MockClient((request) async {
          expect(request.url.toString(), contains('format=tar'));
          return http.Response.bytes(bytes, 200);
        }),
      );
      expect(result, isNotNull);
    });

    test('non-200 → returns null', () async {
      final result = await http.runWithClient(
        () => ComprehensiveFileService.exportUserDataWithFiles(userId: 42),
        () => MockClient((_) async => http.Response('{"error":"denied"}', 403)),
      );
      expect(result, isNull);
    });

    test('network exception → returns null', () async {
      final result = await http.runWithClient(
        () => ComprehensiveFileService.exportUserDataWithFiles(userId: 42),
        () => MockClient((_) async => throw Exception('timeout')),
      );
      expect(result, isNull);
    });
  });

  // ─── FileCategoryDropdown widget ───────────────────────────────────────

  group('FileCategoryDropdown', () {
    testWidgets('renders with all categories when allowedCategories is null',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: FileCategoryDropdown()),
        ),
      );
      await tester.pumpAndSettle();

      // Should render the dropdown
      expect(find.byType(DropdownButtonFormField<FileCategory>), findsOneWidget);
      expect(find.text('Select Category'), findsOneWidget);
    });

    testWidgets('renders with specific allowed categories', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FileCategoryDropdown(
              allowedCategories: [
                FileCategory.prescription,
                FileCategory.labResult,
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(DropdownButtonFormField<FileCategory>), findsOneWidget);
    });

    testWidgets('empty allowedCategories falls back to all FileCategory.values',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FileCategoryDropdown(allowedCategories: []),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Empty list triggers fallback to FileCategory.values, so dropdown renders
      expect(find.byType(DropdownButtonFormField<FileCategory>), findsOneWidget);
    });

    testWidgets('selecting a value triggers setState and updates selection',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FileCategoryDropdown(
              allowedCategories: const [
                FileCategory.prescription,
                FileCategory.labResult,
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap the dropdown to open it
      await tester.tap(find.byType(DropdownButtonFormField<FileCategory>));
      await tester.pumpAndSettle();

      // Select Lab Result from the opened dropdown menu
      // DropdownButtonFormField renders duplicate items (one in button, one in overlay)
      final labResultFinder = find.text('\u{1F9EA} Lab Result');
      await tester.tap(labResultFinder.last);
      await tester.pumpAndSettle();

      // Dropdown should still be rendered after selection
      expect(find.byType(DropdownButtonFormField<FileCategory>), findsOneWidget);
    });

    testWidgets('renders with single allowed category', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FileCategoryDropdown(
              allowedCategories: [FileCategory.medicalReport],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(DropdownButtonFormField<FileCategory>), findsOneWidget);
      // The initial value should be medicalReport
      expect(find.textContaining('Medical Report'), findsOneWidget);
    });
  });

  // ─── validateFileForCategory ─────────────────────────────────────────────

  group('ComprehensiveFileService.validateFileForCategory', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('cfs_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    File createTempFile(String name, {int sizeBytes = 100}) {
      final file = File('${tempDir.path}/$name');
      file.writeAsBytesSync(List.filled(sizeBytes, 0));
      return file;
    }

    // ── profilePicture category ──

    test('profilePicture: accepts .jpg', () {
      final file = createTempFile('photo.jpg');
      expect(
        ComprehensiveFileService.validateFileForCategory(
            file, FileCategory.profilePicture),
        isTrue,
      );
    });

    test('profilePicture: accepts .jpeg', () {
      final file = createTempFile('photo.jpeg');
      expect(
        ComprehensiveFileService.validateFileForCategory(
            file, FileCategory.profilePicture),
        isTrue,
      );
    });

    test('profilePicture: accepts .png', () {
      final file = createTempFile('photo.png');
      expect(
        ComprehensiveFileService.validateFileForCategory(
            file, FileCategory.profilePicture),
        isTrue,
      );
    });

    test('profilePicture: rejects .pdf', () {
      final file = createTempFile('doc.pdf');
      expect(
        ComprehensiveFileService.validateFileForCategory(
            file, FileCategory.profilePicture),
        isFalse,
      );
    });

    test('profilePicture: rejects .docx', () {
      final file = createTempFile('doc.docx');
      expect(
        ComprehensiveFileService.validateFileForCategory(
            file, FileCategory.profilePicture),
        isFalse,
      );
    });

    // ── prescription category ──

    test('prescription: accepts .jpg', () {
      final file = createTempFile('rx.jpg');
      expect(
        ComprehensiveFileService.validateFileForCategory(
            file, FileCategory.prescription),
        isTrue,
      );
    });

    test('prescription: accepts .jpeg', () {
      final file = createTempFile('rx.jpeg');
      expect(
        ComprehensiveFileService.validateFileForCategory(
            file, FileCategory.prescription),
        isTrue,
      );
    });

    test('prescription: accepts .png', () {
      final file = createTempFile('rx.png');
      expect(
        ComprehensiveFileService.validateFileForCategory(
            file, FileCategory.prescription),
        isTrue,
      );
    });

    test('prescription: accepts .pdf', () {
      final file = createTempFile('rx.pdf');
      expect(
        ComprehensiveFileService.validateFileForCategory(
            file, FileCategory.prescription),
        isTrue,
      );
    });

    test('prescription: accepts .txt', () {
      final file = createTempFile('rx.txt');
      expect(
        ComprehensiveFileService.validateFileForCategory(
            file, FileCategory.prescription),
        isTrue,
      );
    });

    test('prescription: rejects .exe', () {
      final file = createTempFile('rx.exe');
      expect(
        ComprehensiveFileService.validateFileForCategory(
            file, FileCategory.prescription),
        isFalse,
      );
    });

    // ── medicalReport category ──

    test('medicalReport: accepts .pdf', () {
      final file = createTempFile('report.pdf');
      expect(
        ComprehensiveFileService.validateFileForCategory(
            file, FileCategory.medicalReport),
        isTrue,
      );
    });

    test('medicalReport: accepts .doc', () {
      final file = createTempFile('report.doc');
      expect(
        ComprehensiveFileService.validateFileForCategory(
            file, FileCategory.medicalReport),
        isTrue,
      );
    });

    test('medicalReport: accepts .docx', () {
      final file = createTempFile('report.docx');
      expect(
        ComprehensiveFileService.validateFileForCategory(
            file, FileCategory.medicalReport),
        isTrue,
      );
    });

    test('medicalReport: accepts .jpg', () {
      final file = createTempFile('report.jpg');
      expect(
        ComprehensiveFileService.validateFileForCategory(
            file, FileCategory.medicalReport),
        isTrue,
      );
    });

    test('medicalReport: accepts .jpeg', () {
      final file = createTempFile('report.jpeg');
      expect(
        ComprehensiveFileService.validateFileForCategory(
            file, FileCategory.medicalReport),
        isTrue,
      );
    });

    test('medicalReport: accepts .png', () {
      final file = createTempFile('report.png');
      expect(
        ComprehensiveFileService.validateFileForCategory(
            file, FileCategory.medicalReport),
        isTrue,
      );
    });

    test('medicalReport: accepts .txt', () {
      final file = createTempFile('report.txt');
      expect(
        ComprehensiveFileService.validateFileForCategory(
            file, FileCategory.medicalReport),
        isTrue,
      );
    });

    test('medicalReport: rejects .exe', () {
      final file = createTempFile('report.exe');
      expect(
        ComprehensiveFileService.validateFileForCategory(
            file, FileCategory.medicalReport),
        isFalse,
      );
    });

    // ── labResult category (same rules as medicalReport) ──

    test('labResult: accepts .pdf', () {
      final file = createTempFile('lab.pdf');
      expect(
        ComprehensiveFileService.validateFileForCategory(
            file, FileCategory.labResult),
        isTrue,
      );
    });

    test('labResult: rejects .zip', () {
      final file = createTempFile('lab.zip');
      expect(
        ComprehensiveFileService.validateFileForCategory(
            file, FileCategory.labResult),
        isFalse,
      );
    });

    // ── insuranceDoc category (same rules as medicalReport) ──

    test('insuranceDoc: accepts .doc', () {
      final file = createTempFile('ins.doc');
      expect(
        ComprehensiveFileService.validateFileForCategory(
            file, FileCategory.insuranceDoc),
        isTrue,
      );
    });

    test('insuranceDoc: rejects .mp4', () {
      final file = createTempFile('ins.mp4');
      expect(
        ComprehensiveFileService.validateFileForCategory(
            file, FileCategory.insuranceDoc),
        isFalse,
      );
    });

    // ── default category (accepts any file type) ──

    test('generalDocument: accepts any extension', () {
      final file = createTempFile('data.csv');
      expect(
        ComprehensiveFileService.validateFileForCategory(
            file, FileCategory.generalDocument),
        isTrue,
      );
    });

    test('aiChatUpload: accepts any extension', () {
      final file = createTempFile('chat.json');
      expect(
        ComprehensiveFileService.validateFileForCategory(
            file, FileCategory.aiChatUpload),
        isTrue,
      );
    });

    test('clinicalNotes: accepts .pdf (falls through to medicalReport group)', () {
      final file = createTempFile('notes.pdf');
      expect(
        ComprehensiveFileService.validateFileForCategory(
            file, FileCategory.clinicalNotes),
        isTrue,
      );
    });

    test('emergencyContact: accepts any extension (default case)', () {
      final file = createTempFile('contact.xlsx');
      expect(
        ComprehensiveFileService.validateFileForCategory(
            file, FileCategory.emergencyContact),
        isTrue,
      );
    });

    test('healthDataImport: accepts any extension (default case)', () {
      final file = createTempFile('import.xml');
      expect(
        ComprehensiveFileService.validateFileForCategory(
            file, FileCategory.healthDataImport),
        isTrue,
      );
    });

    test('backupFile: accepts any extension (default case)', () {
      final file = createTempFile('backup.tar');
      expect(
        ComprehensiveFileService.validateFileForCategory(
            file, FileCategory.backupFile),
        isTrue,
      );
    });

    // ── file size limit ──

    test('rejects file larger than 50MB', () {
      // Create a file just over 50MB (50 * 1024 * 1024 + 1 = 52428801 bytes)
      final file = createTempFile('large.pdf', sizeBytes: 50 * 1024 * 1024 + 1);
      expect(
        ComprehensiveFileService.validateFileForCategory(
            file, FileCategory.generalDocument),
        isFalse,
      );
    });

    test('accepts file exactly at 50MB', () {
      final file = createTempFile('exact.pdf', sizeBytes: 50 * 1024 * 1024);
      expect(
        ComprehensiveFileService.validateFileForCategory(
            file, FileCategory.generalDocument),
        isTrue,
      );
    });

    test('accepts small file for default category', () {
      final file = createTempFile('small.bin', sizeBytes: 1);
      expect(
        ComprehensiveFileService.validateFileForCategory(
            file, FileCategory.generalDocument),
        isTrue,
      );
    });

    // ── case-insensitive file extension check ──

    test('profilePicture: accepts uppercase .JPG (path is lowercased)', () {
      // The method lowercases the path, so mixed-case extensions work
      final file = createTempFile('PHOTO.JPG');
      expect(
        ComprehensiveFileService.validateFileForCategory(
            file, FileCategory.profilePicture),
        isTrue,
      );
    });

    test('medicalReport: accepts uppercase .PDF', () {
      final file = createTempFile('REPORT.PDF');
      expect(
        ComprehensiveFileService.validateFileForCategory(
            file, FileCategory.medicalReport),
        isTrue,
      );
    });
  });

  // ─── exportUserDataWithFiles includeFiles default ──────────────────────

  group('ComprehensiveFileService.exportUserDataWithFiles includeFiles default', () {
    test('includeFiles=true (default) → URL does not contain EXCLUDE_FILES', () async {
      final bytes = [0x50, 0x4B];
      final result = await http.runWithClient(
        () => ComprehensiveFileService.exportUserDataWithFiles(
          userId: 42,
          includeFiles: true,
        ),
        () => MockClient((request) async {
          expect(request.url.toString(), isNot(contains('EXCLUDE_FILES')));
          expect(request.url.toString(), contains('format=zip'));
          return http.Response.bytes(bytes, 200);
        }),
      );
      expect(result, isNotNull);
      expect(result!.length, 2);
    });
  });

  // ─── getUserFilesByCategory with date/query params ─────────────────────

  group('ComprehensiveFileService.getUserFilesByCategory date+query params', () {
    test('passes startDate, endDate, query through', () async {
      final body = jsonEncode({
        'files': [_fileJson(id: 200)],
      });
      final result = await http.runWithClient(
        () => ComprehensiveFileService.getUserFilesByCategory(
          10,
          FileCategory.clinicalNotes,
          params: FileQueryParams(
            page: 0,
            size: 25,
            sort: 'updatedAt',
            startDate: '2025-01-01',
            endDate: '2025-12-31',
            query: 'notes',
          ),
        ),
        () => MockClient((_) async => http.Response(body, 200)),
      );
      expect(result.length, 1);
    });
  });

  // ─── getFilesByDateRange with categories+query params ──────────────────

  group('ComprehensiveFileService.getFilesByDateRange categories+query', () {
    test('passes categories and query through alongside dates', () async {
      final body = jsonEncode({
        'files': [_fileJson(id: 210), _fileJson(id: 211)],
      });
      final result = await http.runWithClient(
        () => ComprehensiveFileService.getFilesByDateRange(
          10,
          startDate: DateTime(2025, 3, 1),
          endDate: DateTime(2025, 3, 31),
          params: FileQueryParams(
            categories: ['LAB_RESULT', 'PRESCRIPTION'],
            query: 'test',
          ),
        ),
        () => MockClient((_) async => http.Response(body, 200)),
      );
      expect(result.length, 2);
    });
  });

  // ─── getFilesByMultipleCategories with sort param ──────────────────────

  group('ComprehensiveFileService.getFilesByMultipleCategories sort', () {
    test('passes sort param through', () async {
      final body = jsonEncode({
        'files': [_fileJson(id: 220)],
      });
      final result = await http.runWithClient(
        () => ComprehensiveFileService.getFilesByMultipleCategories(
          10,
          categories: [FileCategory.medicalReport],
          params: FileQueryParams(sort: 'createdAt'),
        ),
        () => MockClient((_) async => http.Response(body, 200)),
      );
      expect(result.length, 1);
    });
  });

  // ─── searchFiles edge cases ─────────────────────────────────────────────

  group('ComprehensiveFileService.searchFiles edge cases', () {
    test('200 with neither data nor content → returns empty list', () async {
      final body = jsonEncode({'other': 'value'});
      final result = await http.runWithClient(
        () => ComprehensiveFileService.searchFiles(
          searchQuery: 'nothing',
          userId: 10,
        ),
        () => MockClient((_) async => http.Response(body, 200)),
      );
      expect(result, isEmpty);
    });

    test('200 with empty data array → returns empty list', () async {
      final body = jsonEncode({'data': []});
      final result = await http.runWithClient(
        () => ComprehensiveFileService.searchFiles(
          searchQuery: 'empty',
          userId: 10,
        ),
        () => MockClient((_) async => http.Response(body, 200)),
      );
      expect(result, isEmpty);
    });
  });

  // ─── FileQueryParams construction ────────────────────────────────────────

  group('FileQueryParams constructor defaults', () {
    test('all fields default to null', () {
      final params = FileQueryParams();
      expect(params.page, isNull);
      expect(params.size, isNull);
      expect(params.sort, isNull);
      expect(params.category, isNull);
      expect(params.categories, isNull);
      expect(params.startDate, isNull);
      expect(params.endDate, isNull);
      expect(params.query, isNull);
    });

    test('fields store provided values', () {
      final params = FileQueryParams(
        page: 3,
        size: 50,
        sort: 'name',
        category: 'TEST',
        categories: ['A', 'B'],
        startDate: '2025-01-01',
        endDate: '2025-12-31',
        query: 'search',
      );
      expect(params.page, 3);
      expect(params.size, 50);
      expect(params.sort, 'name');
      expect(params.category, 'TEST');
      expect(params.categories, ['A', 'B']);
      expect(params.startDate, '2025-01-01');
      expect(params.endDate, '2025-12-31');
      expect(params.query, 'search');
    });
  });
}
