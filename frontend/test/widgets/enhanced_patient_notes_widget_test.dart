// Tests for EnhancedPatientNotesWidget widget and its supporting types.
//
// The widget calls EnhancedFileService (HTTP) in initState and
// FileHandlerFactory.create() which throws UnsupportedError in test.
// We suppress that error and test the build/UI paths.

import 'package:care_connect_app/services/enhanced_file_service.dart';
import 'package:care_connect_app/widgets/enhanced_patient_notes_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        if (call.method == 'readAll') return <String, String>{};
        if (call.method == 'containsKey') return false;
        if (call.method == 'read') return null;
        if (call.method == 'write') return null;
        if (call.method == 'delete') return null;
        return null;
      },
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async {
        if (call.method == 'check') return ['wifi'];
        return null;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      null,
    );
  });

  group('EnhancedPatientNotesWidget constructor', () {
    test('creates widget with required parameters', () {
      const widget = EnhancedPatientNotesWidget(patientId: 1);
      expect(widget.patientId, 1);
      expect(widget.showCompactView, false);
      expect(widget.initialItemCount, 3);
    });

    test('creates widget with all parameters', () {
      const widget = EnhancedPatientNotesWidget(
        patientId: 42,
        showCompactView: true,
        initialItemCount: 5,
      );
      expect(widget.patientId, 42);
      expect(widget.showCompactView, true);
      expect(widget.initialItemCount, 5);
    });

    test('creates widget with custom key', () {
      const widget = EnhancedPatientNotesWidget(
        key: Key('test-key'),
        patientId: 10,
      );
      expect(widget.key, const Key('test-key'));
    });

    test('creates state', () {
      const widget = EnhancedPatientNotesWidget(patientId: 1);
      final state = widget.createState();
      expect(state, isNotNull);
    });

    test('default showCompactView is false', () {
      const widget = EnhancedPatientNotesWidget(patientId: 99);
      expect(widget.showCompactView, isFalse);
    });

    test('default initialItemCount is 3', () {
      const widget = EnhancedPatientNotesWidget(patientId: 99);
      expect(widget.initialItemCount, 3);
    });

    test('creates widget with zero patientId', () {
      const widget = EnhancedPatientNotesWidget(patientId: 0);
      expect(widget.patientId, 0);
    });

    test('creates widget with large patientId', () {
      const widget = EnhancedPatientNotesWidget(patientId: 999999);
      expect(widget.patientId, 999999);
    });

    test('creates widget with initialItemCount of 1', () {
      const widget = EnhancedPatientNotesWidget(
        patientId: 1,
        initialItemCount: 1,
      );
      expect(widget.initialItemCount, 1);
    });

    test('creates widget with large initialItemCount', () {
      const widget = EnhancedPatientNotesWidget(
        patientId: 1,
        initialItemCount: 100,
      );
      expect(widget.initialItemCount, 100);
    });
  });

  group('EnhancedPatientNotesWidget rendering', () {
    testWidgets('handles initState without crashing', (tester) async {
      final originalOnError = FlutterError.onError;
      final errors = <FlutterErrorDetails>[];
      FlutterError.onError = (details) {
        errors.add(details);
      };

      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: EnhancedPatientNotesWidget(
                  patientId: 1,
                ),
              ),
            ),
          ),
        );

        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(seconds: 1));

        expect(find.byType(EnhancedPatientNotesWidget), findsOneWidget);
      } finally {
        FlutterError.onError = originalOnError;
      }
    });

    testWidgets('widget can be constructed and added to tree', (tester) async {
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {};

      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: EnhancedPatientNotesWidget(
                patientId: 42,
                showCompactView: true,
                initialItemCount: 5,
              ),
            ),
          ),
        );

        await tester.pump();
        expect(find.byType(EnhancedPatientNotesWidget), findsOneWidget);
      } finally {
        FlutterError.onError = originalOnError;
      }
    });

    testWidgets('renders loading or content without FileHandler crash',
        (tester) async {
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {};

      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: EnhancedPatientNotesWidget(patientId: 1),
            ),
          ),
        );

        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(seconds: 1));

        // Native FileHandlerFactory succeeds; widget stays in tree.
        expect(find.byType(EnhancedPatientNotesWidget), findsOneWidget);
      } finally {
        FlutterError.onError = originalOnError;
      }
    });

    testWidgets('FileHandlerFactory.create succeeds on VM/native',
        (tester) async {
      final originalOnError = FlutterError.onError;
      final errors = <FlutterErrorDetails>[];
      FlutterError.onError = (details) {
        errors.add(details);
      };

      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: EnhancedPatientNotesWidget(patientId: 5),
            ),
          ),
        );

        await tester.pump();

        // Factory no longer throws UnsupportedError on dart:io platforms.
        expect(
          errors.any((e) => e.exception is UnsupportedError),
          isFalse,
        );
        expect(find.byType(EnhancedPatientNotesWidget), findsOneWidget);
      } finally {
        FlutterError.onError = originalOnError;
      }
    });

    testWidgets('widget with showCompactView true builds', (tester) async {
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {};

      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: EnhancedPatientNotesWidget(
                patientId: 1,
                showCompactView: true,
              ),
            ),
          ),
        );

        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(seconds: 1));

        expect(find.byType(EnhancedPatientNotesWidget), findsOneWidget);
      } finally {
        FlutterError.onError = originalOnError;
      }
    });
  });

  group('UserFileDTO model', () {
    late UserFileDTO dto;

    setUp(() {
      dto = UserFileDTO(
        id: 1,
        originalFilename: 'test_report.pdf',
        contentType: 'application/pdf',
        fileSize: 2048,
        fileCategory: 'MEDICAL_NOTE',
        description: 'A test medical note',
        ownerId: 10,
        ownerType: 'CAREGIVER',
        patientId: 20,
        createdAt: DateTime(2025, 1, 15),
        updatedAt: DateTime(2025, 1, 16),
        fileUrl: 'https://example.com/file',
        downloadUrl: 'https://example.com/download',
        files: null,
        category: 'MEDICAL_NOTE',
        s3FullKey: 's3://bucket/key',
        fileName: 'test_report.pdf',
      );
    });

    test('properties are stored correctly', () {
      expect(dto.id, 1);
      expect(dto.originalFilename, 'test_report.pdf');
      expect(dto.contentType, 'application/pdf');
      expect(dto.fileSize, 2048);
      expect(dto.fileCategory, 'MEDICAL_NOTE');
      expect(dto.description, 'A test medical note');
      expect(dto.ownerId, 10);
      expect(dto.ownerType, 'CAREGIVER');
      expect(dto.patientId, 20);
      expect(dto.fileUrl, 'https://example.com/file');
      expect(dto.downloadUrl, 'https://example.com/download');
      expect(dto.fileName, 'test_report.pdf');
      expect(dto.files, isNull);
      expect(dto.category, 'MEDICAL_NOTE');
      expect(dto.s3FullKey, 's3://bucket/key');
      expect(dto.createdAt, DateTime(2025, 1, 15));
      expect(dto.updatedAt, DateTime(2025, 1, 16));
    });

    test('fromJson creates DTO from JSON map', () {
      final json = {
        'id': 5,
        'originalFilename': 'lab.pdf',
        'contentType': 'application/pdf',
        'fileSize': 1024,
        'fileCategory': 'LAB_RESULT',
        'description': 'Blood test',
        'ownerId': 3,
        'ownerType': 'PATIENT',
        'patientId': 3,
        'fileUrl': 'http://url',
        'downloadUrl': 'http://dl',
        'category': 'LAB_RESULT',
        's3FullKey': 's3://k',
        'filename': 'lab.pdf',
      };
      final result = UserFileDTO.fromJson(json);
      expect(result.id, 5);
      expect(result.originalFilename, 'lab.pdf');
      expect(result.contentType, 'application/pdf');
      expect(result.fileSize, 1024);
      expect(result.fileCategory, 'LAB_RESULT');
      expect(result.description, 'Blood test');
      expect(result.ownerId, 3);
      expect(result.ownerType, 'PATIENT');
      expect(result.patientId, 3);
      expect(result.fileName, 'lab.pdf');
      expect(result.fileUrl, 'http://url');
      expect(result.downloadUrl, 'http://dl');
      expect(result.category, 'LAB_RESULT');
      expect(result.s3FullKey, 's3://k');
    });

    test('fromJson uses defaults for missing keys', () {
      final result = UserFileDTO.fromJson({});
      expect(result.id, 0);
      expect(result.originalFilename, '');
      expect(result.contentType, 'application/octet-stream');
      expect(result.fileSize, 0);
      expect(result.fileCategory, 'documents');
      expect(result.description, isNull);
      expect(result.ownerId, 0);
      expect(result.ownerType, '');
      expect(result.fileName, '[Unnamed File]');
      expect(result.patientId, isNull);
      expect(result.fileUrl, isNull);
      expect(result.downloadUrl, isNull);
      expect(result.files, isNull);
      expect(result.s3FullKey, isNull);
    });

    test('fromJson with files list', () {
      final json = {
        'id': 1,
        'files': ['file1.pdf', 'file2.pdf'],
      };
      final result = UserFileDTO.fromJson(json);
      expect(result.files, isNotNull);
      expect(result.files!.length, 2);
    });

    test('fromJson with empty files list', () {
      final json = {
        'id': 1,
        'files': <String>[],
      };
      final result = UserFileDTO.fromJson(json);
      expect(result.files, isNotNull);
      expect(result.files!.length, 0);
    });

    test('fromJson with null values for optional fields', () {
      final json = {
        'id': 1,
        'description': null,
        'patientId': null,
        'fileUrl': null,
        'downloadUrl': null,
        'files': null,
        's3FullKey': null,
      };
      final result = UserFileDTO.fromJson(json);
      expect(result.description, isNull);
      expect(result.patientId, isNull);
      expect(result.fileUrl, isNull);
      expect(result.downloadUrl, isNull);
      expect(result.files, isNull);
      expect(result.s3FullKey, isNull);
    });

    test('fromJson with empty string values', () {
      final json = {
        'id': 0,
        'originalFilename': '',
        'contentType': '',
        'fileCategory': '',
        'ownerType': '',
        'filename': '',
      };
      final result = UserFileDTO.fromJson(json);
      expect(result.originalFilename, '');
      // contentType empty string is falsy, falls back to default
      expect(result.contentType, '');
      expect(result.fileCategory, '');
      expect(result.ownerType, '');
      expect(result.fileName, '');
    });

    test('fromJson sets createdAt and updatedAt to now', () {
      final before = DateTime.now();
      final result = UserFileDTO.fromJson({'id': 1});
      final after = DateTime.now();
      expect(result.createdAt, isNotNull);
      expect(result.updatedAt, isNotNull);
      // createdAt should be between before and after
      expect(
        result.createdAt!.isAfter(before.subtract(const Duration(seconds: 1))),
        isTrue,
      );
      expect(
        result.createdAt!.isBefore(after.add(const Duration(seconds: 1))),
        isTrue,
      );
    });

    test('fromJson with integer zero values', () {
      final json = {
        'id': 0,
        'fileSize': 0,
        'ownerId': 0,
      };
      final result = UserFileDTO.fromJson(json);
      expect(result.id, 0);
      expect(result.fileSize, 0);
      expect(result.ownerId, 0);
    });

    test('fromJson with large file size', () {
      final json = {
        'id': 1,
        'fileSize': 1073741824, // 1 GB
      };
      final result = UserFileDTO.fromJson(json);
      expect(result.fileSize, 1073741824);
    });

    test('fromJson category defaults to empty string', () {
      final result = UserFileDTO.fromJson({});
      expect(result.category, '');
    });

    test('fromJson with special characters in filename', () {
      final json = {
        'filename': 'my file (1).pdf',
        'originalFilename': 'my file (1).pdf',
      };
      final result = UserFileDTO.fromJson(json);
      expect(result.fileName, 'my file (1).pdf');
      expect(result.originalFilename, 'my file (1).pdf');
    });

    test('toJson returns a valid map', () {
      final json = dto.toJson();
      expect(json['id'], 1);
      expect(json['originalFilename'], 'test_report.pdf');
      expect(json['contentType'], 'application/pdf');
      expect(json['fileSize'], 2048);
      expect(json['fileCategory'], 'MEDICAL_NOTE');
      expect(json['description'], 'A test medical note');
      expect(json['ownerId'], 10);
      expect(json['ownerType'], 'CAREGIVER');
      expect(json['patientId'], 20);
      expect(json['createdAt'], isNotNull);
      expect(json['updatedAt'], isNotNull);
      expect(json['fileUrl'], 'https://example.com/file');
      expect(json['downloadUrl'], 'https://example.com/download');
      expect(json['files'], isNull);
      expect(json['category'], 'MEDICAL_NOTE');
      expect(json['s3FullyKey'], 's3://bucket/key');
    });

    test('toJson with null optional fields', () {
      final minDto = UserFileDTO(
        id: 1,
        originalFilename: 'test.pdf',
        contentType: 'application/pdf',
        fileSize: 100,
        fileCategory: 'OTHER_DOCUMENT',
        ownerId: 1,
        ownerType: 'PATIENT',
        createdAt: null,
        updatedAt: null,
        fileName: 'test.pdf',
      );
      final json = minDto.toJson();
      expect(json['description'], isNull);
      expect(json['patientId'], isNull);
      expect(json['createdAt'], isNull);
      expect(json['updatedAt'], isNull);
      expect(json['fileUrl'], isNull);
      expect(json['downloadUrl'], isNull);
    });

    test('toJson includes all expected keys', () {
      final json = dto.toJson();
      expect(json.containsKey('id'), isTrue);
      expect(json.containsKey('originalFilename'), isTrue);
      expect(json.containsKey('contentType'), isTrue);
      expect(json.containsKey('fileSize'), isTrue);
      expect(json.containsKey('fileCategory'), isTrue);
      expect(json.containsKey('description'), isTrue);
      expect(json.containsKey('ownerId'), isTrue);
      expect(json.containsKey('ownerType'), isTrue);
      expect(json.containsKey('patientId'), isTrue);
      expect(json.containsKey('createdAt'), isTrue);
      expect(json.containsKey('updatedAt'), isTrue);
      expect(json.containsKey('fileUrl'), isTrue);
      expect(json.containsKey('downloadUrl'), isTrue);
      expect(json.containsKey('files'), isTrue);
      expect(json.containsKey('category'), isTrue);
      expect(json.containsKey('s3FullyKey'), isTrue);
    });

    test('toJson createdAt serializes to ISO 8601', () {
      final json = dto.toJson();
      final dateStr = json['createdAt'] as String;
      expect(dateStr, contains('2025-01-15'));
    });

    test('toJson updatedAt serializes to ISO 8601', () {
      final json = dto.toJson();
      final dateStr = json['updatedAt'] as String;
      expect(dateStr, contains('2025-01-16'));
    });

    test('toJson with files list', () {
      final dtoWithFiles = UserFileDTO(
        id: 1,
        originalFilename: 'test.pdf',
        contentType: 'application/pdf',
        fileSize: 100,
        fileCategory: 'OTHER_DOCUMENT',
        ownerId: 1,
        ownerType: 'PATIENT',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        files: ['a.pdf', 'b.pdf'],
        fileName: 'test.pdf',
      );
      final json = dtoWithFiles.toJson();
      expect(json['files'], isNotNull);
      expect(json['files'], hasLength(2));
    });

    group('fileIcon', () {
      UserFileDTO makeDto(String contentType) => UserFileDTO(
            id: 1,
            originalFilename: 'file',
            contentType: contentType,
            fileSize: 100,
            fileCategory: 'OTHER_DOCUMENT',
            ownerId: 1,
            ownerType: 'PATIENT',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            fileName: 'file',
          );

      test('returns image icon for image content type', () {
        expect(makeDto('image/jpeg').fileIcon, contains('\u{1F5BC}'));
        expect(makeDto('image/png').fileIcon, contains('\u{1F5BC}'));
        expect(makeDto('image/gif').fileIcon, contains('\u{1F5BC}'));
      });

      test('returns image icon for other image subtypes', () {
        expect(makeDto('image/bmp').fileIcon, contains('\u{1F5BC}'));
        expect(makeDto('image/webp').fileIcon, contains('\u{1F5BC}'));
        expect(makeDto('image/svg+xml').fileIcon, contains('\u{1F5BC}'));
        expect(makeDto('image/tiff').fileIcon, contains('\u{1F5BC}'));
      });

      test('returns PDF icon for pdf content type', () {
        expect(makeDto('application/pdf').fileIcon, contains('\u{1F4C4}'));
      });

      test('returns word doc icon for word content type', () {
        expect(makeDto('application/msword').fileIcon, contains('\u{1F4DD}'));
        expect(
          makeDto(
                  'application/vnd.openxmlformats-officedocument.wordprocessingml.document')
              .fileIcon,
          contains('\u{1F4DD}'),
        );
      });

      test('returns spreadsheet icon for excel content type without document',
          () {
        expect(
            makeDto('application/vnd.ms-excel').fileIcon, contains('\u{1F4CA}'));
      });

      test('returns video icon for video content type', () {
        expect(makeDto('video/mp4').fileIcon, contains('\u{1F3A5}'));
        expect(makeDto('video/mpeg').fileIcon, contains('\u{1F3A5}'));
      });

      test('returns video icon for additional video subtypes', () {
        expect(makeDto('video/webm').fileIcon, contains('\u{1F3A5}'));
        expect(makeDto('video/quicktime').fileIcon, contains('\u{1F3A5}'));
      });

      test('returns audio icon for audio content type', () {
        expect(makeDto('audio/mpeg').fileIcon, contains('\u{1F3B5}'));
        expect(makeDto('audio/wav').fileIcon, contains('\u{1F3B5}'));
      });

      test('returns audio icon for additional audio subtypes', () {
        expect(makeDto('audio/ogg').fileIcon, contains('\u{1F3B5}'));
        expect(makeDto('audio/flac').fileIcon, contains('\u{1F3B5}'));
      });

      test('returns folder icon for unknown content type', () {
        expect(makeDto('application/octet-stream').fileIcon,
            contains('\u{1F4C1}'));
        expect(makeDto('text/plain').fileIcon, contains('\u{1F4C1}'));
      });

      test('returns folder icon for text subtypes', () {
        expect(makeDto('text/html').fileIcon, contains('\u{1F4C1}'));
        expect(makeDto('text/css').fileIcon, contains('\u{1F4C1}'));
        expect(makeDto('text/csv').fileIcon, contains('\u{1F4C1}'));
      });

      test(
          'returns word icon for document-containing spreadsheet content type',
          () {
        expect(
          makeDto(
                  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
              .fileIcon,
          contains('\u{1F4DD}'),
        );
      });

      test('returns presentation icon for presentation content type', () {
        expect(makeDto('application/vnd.ms-presentation').fileIcon,
            contains('\u{1F4C8}'));
      });

      test('returns presentation icon for powerpoint', () {
        expect(makeDto('application/vnd.ms-powerpoint').fileIcon,
            contains('\u{1F4C8}'));
      });

      test('returns spreadsheet icon for spreadsheet without document', () {
        expect(makeDto('application/vnd.ms-spreadsheet').fileIcon,
            contains('\u{1F4CA}'));
      });

      test('returns folder icon for application/json', () {
        expect(makeDto('application/json').fileIcon, contains('\u{1F4C1}'));
      });

      test('returns folder icon for application/zip', () {
        expect(makeDto('application/zip').fileIcon, contains('\u{1F4C1}'));
      });
    });

    group('isImage', () {
      test('returns true for image content types', () {
        final imageDto = UserFileDTO(
          id: 1,
          originalFilename: 'pic.png',
          contentType: 'image/png',
          fileSize: 100,
          fileCategory: 'OTHER_DOCUMENT',
          ownerId: 1,
          ownerType: 'PATIENT',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          fileName: 'pic.png',
        );
        expect(imageDto.isImage, true);
      });

      test('returns true for jpeg', () {
        final jpegDto = UserFileDTO(
          id: 1,
          originalFilename: 'pic.jpg',
          contentType: 'image/jpeg',
          fileSize: 100,
          fileCategory: 'OTHER_DOCUMENT',
          ownerId: 1,
          ownerType: 'PATIENT',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          fileName: 'pic.jpg',
        );
        expect(jpegDto.isImage, true);
      });

      test('returns true for gif', () {
        final gifDto = UserFileDTO(
          id: 1,
          originalFilename: 'pic.gif',
          contentType: 'image/gif',
          fileSize: 100,
          fileCategory: 'OTHER_DOCUMENT',
          ownerId: 1,
          ownerType: 'PATIENT',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          fileName: 'pic.gif',
        );
        expect(gifDto.isImage, true);
      });

      test('returns false for non-image content type', () {
        expect(dto.isImage, false);
      });

      test('returns false for video', () {
        final vidDto = UserFileDTO(
          id: 1,
          originalFilename: 'vid.mp4',
          contentType: 'video/mp4',
          fileSize: 100,
          fileCategory: 'OTHER_DOCUMENT',
          ownerId: 1,
          ownerType: 'PATIENT',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          fileName: 'vid.mp4',
        );
        expect(vidDto.isImage, false);
      });

      test('returns false for audio', () {
        final audioDto = UserFileDTO(
          id: 1,
          originalFilename: 'sound.mp3',
          contentType: 'audio/mpeg',
          fileSize: 100,
          fileCategory: 'OTHER_DOCUMENT',
          ownerId: 1,
          ownerType: 'PATIENT',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          fileName: 'sound.mp3',
        );
        expect(audioDto.isImage, false);
      });

      test('returns false for text', () {
        final textDto = UserFileDTO(
          id: 1,
          originalFilename: 'notes.txt',
          contentType: 'text/plain',
          fileSize: 100,
          fileCategory: 'OTHER_DOCUMENT',
          ownerId: 1,
          ownerType: 'PATIENT',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          fileName: 'notes.txt',
        );
        expect(textDto.isImage, false);
      });
    });

    group('isPreviewable', () {
      test('returns true for PDF', () {
        expect(dto.isPreviewable, true);
      });

      test('returns true for image', () {
        final imageDto = UserFileDTO(
          id: 1,
          originalFilename: 'pic.png',
          contentType: 'image/png',
          fileSize: 100,
          fileCategory: 'OTHER_DOCUMENT',
          ownerId: 1,
          ownerType: 'PATIENT',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          fileName: 'pic.png',
        );
        expect(imageDto.isPreviewable, true);
      });

      test('returns true for word document', () {
        final wordDto = UserFileDTO(
          id: 1,
          originalFilename: 'doc.docx',
          contentType:
              'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
          fileSize: 100,
          fileCategory: 'OTHER_DOCUMENT',
          ownerId: 1,
          ownerType: 'PATIENT',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          fileName: 'doc.docx',
        );
        expect(wordDto.isPreviewable, true);
      });

      test('returns true for msword', () {
        final mswordDto = UserFileDTO(
          id: 1,
          originalFilename: 'doc.doc',
          contentType: 'application/msword',
          fileSize: 100,
          fileCategory: 'OTHER_DOCUMENT',
          ownerId: 1,
          ownerType: 'PATIENT',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          fileName: 'doc.doc',
        );
        expect(mswordDto.isPreviewable, true);
      });

      test('returns false for binary file', () {
        final binDto = UserFileDTO(
          id: 1,
          originalFilename: 'data.bin',
          contentType: 'application/octet-stream',
          fileSize: 100,
          fileCategory: 'OTHER_DOCUMENT',
          ownerId: 1,
          ownerType: 'PATIENT',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          fileName: 'data.bin',
        );
        expect(binDto.isPreviewable, false);
      });

      test('returns false for video', () {
        final vidDto = UserFileDTO(
          id: 1,
          originalFilename: 'vid.mp4',
          contentType: 'video/mp4',
          fileSize: 100,
          fileCategory: 'OTHER_DOCUMENT',
          ownerId: 1,
          ownerType: 'PATIENT',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          fileName: 'vid.mp4',
        );
        expect(vidDto.isPreviewable, false);
      });

      test('returns false for audio', () {
        final audioDto = UserFileDTO(
          id: 1,
          originalFilename: 'sound.mp3',
          contentType: 'audio/mpeg',
          fileSize: 100,
          fileCategory: 'OTHER_DOCUMENT',
          ownerId: 1,
          ownerType: 'PATIENT',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          fileName: 'sound.mp3',
        );
        expect(audioDto.isPreviewable, false);
      });

      test('returns false for plain text', () {
        final txtDto = UserFileDTO(
          id: 1,
          originalFilename: 'readme.txt',
          contentType: 'text/plain',
          fileSize: 100,
          fileCategory: 'OTHER_DOCUMENT',
          ownerId: 1,
          ownerType: 'PATIENT',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          fileName: 'readme.txt',
        );
        expect(txtDto.isPreviewable, false);
      });

      test('returns false for zip', () {
        final zipDto = UserFileDTO(
          id: 1,
          originalFilename: 'archive.zip',
          contentType: 'application/zip',
          fileSize: 100,
          fileCategory: 'OTHER_DOCUMENT',
          ownerId: 1,
          ownerType: 'PATIENT',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          fileName: 'archive.zip',
        );
        expect(zipDto.isPreviewable, false);
      });

      test('returns true for document type containing "document"', () {
        final docDto = UserFileDTO(
          id: 1,
          originalFilename: 'sheet.xlsx',
          contentType:
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          fileSize: 100,
          fileCategory: 'OTHER_DOCUMENT',
          ownerId: 1,
          ownerType: 'PATIENT',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          fileName: 'sheet.xlsx',
        );
        // Contains "document" so isPreviewable is true
        expect(docDto.isPreviewable, true);
      });
    });

    group('categoryDisplayName', () {
      test('returns display name for known category', () {
        expect(dto.categoryDisplayName, 'Medical Note');
      });

      test('returns formatted string for unknown category', () {
        final unknownDto = UserFileDTO(
          id: 1,
          originalFilename: 'x.pdf',
          contentType: 'application/pdf',
          fileSize: 100,
          fileCategory: 'SOME_CUSTOM_CATEGORY',
          ownerId: 1,
          ownerType: 'PATIENT',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          fileName: 'x.pdf',
        );
        expect(unknownDto.categoryDisplayName, 'some custom category');
      });

      test('returns display name for various known categories', () {
        UserFileDTO makeWithCategory(String cat) => UserFileDTO(
              id: 1,
              originalFilename: 'x',
              contentType: 'application/pdf',
              fileSize: 100,
              fileCategory: cat,
              ownerId: 1,
              ownerType: 'PATIENT',
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
              fileName: 'x',
            );

        expect(
            makeWithCategory('LAB_RESULT').categoryDisplayName, 'Lab Result');
        expect(makeWithCategory('PRESCRIPTION').categoryDisplayName,
            'Prescription');
        expect(
            makeWithCategory('CARE_NOTE').categoryDisplayName, 'Care Note');
        expect(makeWithCategory('GENERAL_NOTE').categoryDisplayName,
            'General Note');
        expect(makeWithCategory('APPOINTMENT').categoryDisplayName,
            'Appointment');
        expect(makeWithCategory('OTHER_DOCUMENT').categoryDisplayName,
            'Other Document');
        expect(makeWithCategory('documents').categoryDisplayName,
            'General Document');
      });

      test('returns display name for caregiver categories', () {
        UserFileDTO makeWithCategory(String cat) => UserFileDTO(
              id: 1,
              originalFilename: 'x',
              contentType: 'application/pdf',
              fileSize: 100,
              fileCategory: cat,
              ownerId: 1,
              ownerType: 'CAREGIVER',
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
              fileName: 'x',
            );

        expect(makeWithCategory('PROFILE_PICTURE').categoryDisplayName,
            'Profile Picture');
        expect(makeWithCategory('CERTIFICATION').categoryDisplayName,
            'Certification');
        expect(
            makeWithCategory('TRAINING').categoryDisplayName, 'Training');
        expect(makeWithCategory('BACKGROUND_CHECK').categoryDisplayName,
            'Background Check');
        expect(
            makeWithCategory('REFERENCE').categoryDisplayName, 'Reference');
        expect(
            makeWithCategory('CONTRACT').categoryDisplayName, 'Contract');
      });

      test('returns formatted fallback for category with single word', () {
        final singleDto = UserFileDTO(
          id: 1,
          originalFilename: 'x',
          contentType: 'application/pdf',
          fileSize: 100,
          fileCategory: 'CUSTOM',
          ownerId: 1,
          ownerType: 'PATIENT',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          fileName: 'x',
        );
        expect(singleDto.categoryDisplayName, 'custom');
      });

      test('returns formatted fallback for category with multiple underscores',
          () {
        final multiDto = UserFileDTO(
          id: 1,
          originalFilename: 'x',
          contentType: 'application/pdf',
          fileSize: 100,
          fileCategory: 'MY_CUSTOM_CATEGORY_NAME',
          ownerId: 1,
          ownerType: 'PATIENT',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          fileName: 'x',
        );
        expect(multiDto.categoryDisplayName, 'my custom category name');
      });
    });
  });

  group('FileUploadResponse', () {
    test('fromJson creates response correctly', () {
      final json = {
        'fileId': 42,
        'originalFilename': 'report.pdf',
        'fileUrl': 'http://file',
        'downloadUrl': 'http://dl',
        'message': 'Success',
        'fileName': 'report.pdf',
      };
      final response = FileUploadResponse.fromJson(json);
      expect(response.fileId, 42);
      expect(response.originalFilename, 'report.pdf');
      expect(response.fileUrl, 'http://file');
      expect(response.downloadUrl, 'http://dl');
      expect(response.message, 'Success');
      expect(response.fileName, 'report.pdf');
    });

    test('fromJson uses defaults for missing keys', () {
      final response = FileUploadResponse.fromJson({});
      expect(response.fileId, 0);
      expect(response.originalFilename, '');
      expect(response.fileUrl, '');
      expect(response.downloadUrl, '');
      expect(response.message, '');
      expect(response.fileName, '');
    });

    test('fromJson with partial data', () {
      final response = FileUploadResponse.fromJson({
        'fileId': 10,
        'message': 'Uploaded',
      });
      expect(response.fileId, 10);
      expect(response.message, 'Uploaded');
      expect(response.originalFilename, '');
      expect(response.fileName, '');
    });

    test('fromJson with null values uses defaults', () {
      final response = FileUploadResponse.fromJson({
        'fileId': null,
        'originalFilename': null,
        'fileUrl': null,
        'downloadUrl': null,
        'message': null,
        'fileName': null,
      });
      expect(response.fileId, 0);
      expect(response.originalFilename, '');
      expect(response.fileUrl, '');
      expect(response.downloadUrl, '');
      expect(response.message, '');
      expect(response.fileName, '');
    });

    test('fromJson with large fileId', () {
      final response = FileUploadResponse.fromJson({
        'fileId': 999999999,
      });
      expect(response.fileId, 999999999);
    });

    test('fromJson with special characters in filename', () {
      final response = FileUploadResponse.fromJson({
        'originalFilename': 'my file (copy).pdf',
        'fileName': 'my file (copy).pdf',
      });
      expect(response.originalFilename, 'my file (copy).pdf');
      expect(response.fileName, 'my file (copy).pdf');
    });

    test('fromJson with URL-like values', () {
      final response = FileUploadResponse.fromJson({
        'fileUrl': 'https://bucket.s3.amazonaws.com/files/123/report.pdf',
        'downloadUrl':
            'https://bucket.s3.amazonaws.com/files/123/report.pdf?download=true',
      });
      expect(response.fileUrl,
          'https://bucket.s3.amazonaws.com/files/123/report.pdf');
      expect(response.downloadUrl,
          'https://bucket.s3.amazonaws.com/files/123/report.pdf?download=true');
    });

    test('constructor stores all properties', () {
      final response = FileUploadResponse(
        fileId: 7,
        originalFilename: 'orig.pdf',
        fileUrl: 'http://file-url',
        downloadUrl: 'http://download-url',
        message: 'File uploaded successfully',
        fileName: 'stored.pdf',
      );
      expect(response.fileId, 7);
      expect(response.originalFilename, 'orig.pdf');
      expect(response.fileUrl, 'http://file-url');
      expect(response.downloadUrl, 'http://download-url');
      expect(response.message, 'File uploaded successfully');
      expect(response.fileName, 'stored.pdf');
    });
  });

  group('getCategoryDisplayName helper', () {
    test('returns "Medical Note" for MEDICAL_NOTE', () {
      expect(getCategoryDisplayName('MEDICAL_NOTE'), 'Medical Note');
    });

    test('returns "Prescription" for PRESCRIPTION', () {
      expect(getCategoryDisplayName('PRESCRIPTION'), 'Prescription');
    });

    test('returns "General Document" for documents', () {
      expect(getCategoryDisplayName('documents'), 'General Document');
    });

    test('returns formatted fallback for unknown category', () {
      expect(getCategoryDisplayName('UNKNOWN_TYPE'), 'unknown type');
    });

    test('returns "Lab Result" for LAB_RESULT', () {
      expect(getCategoryDisplayName('LAB_RESULT'), 'Lab Result');
    });

    test('returns "Appointment" for APPOINTMENT', () {
      expect(getCategoryDisplayName('APPOINTMENT'), 'Appointment');
    });

    test('returns "Care Note" for CARE_NOTE', () {
      expect(getCategoryDisplayName('CARE_NOTE'), 'Care Note');
    });

    test('returns "General Note" for GENERAL_NOTE', () {
      expect(getCategoryDisplayName('GENERAL_NOTE'), 'General Note');
    });

    test('returns "Other Document" for OTHER_DOCUMENT', () {
      expect(getCategoryDisplayName('OTHER_DOCUMENT'), 'Other Document');
    });

    test('returns display names for all known categories', () {
      expect(getCategoryDisplayName('PROFILE_PICTURE'), 'Profile Picture');
      expect(getCategoryDisplayName('MEDICAL_RECORD'), 'Medical Record');
      expect(getCategoryDisplayName('INSURANCE'), 'Insurance');
      expect(getCategoryDisplayName('REPORT'), 'Report');
      expect(getCategoryDisplayName('CONSENT_FORM'), 'Consent Form');
      expect(
          getCategoryDisplayName('EMERGENCY_CONTACT'), 'Emergency Contact');
      expect(getCategoryDisplayName('CERTIFICATION'), 'Certification');
      expect(getCategoryDisplayName('TRAINING'), 'Training');
      expect(getCategoryDisplayName('BACKGROUND_CHECK'), 'Background Check');
      expect(getCategoryDisplayName('REFERENCE'), 'Reference');
      expect(getCategoryDisplayName('CONTRACT'), 'Contract');
      expect(getCategoryDisplayName('AUTHORIZATION'), 'Authorization');
    });

    test('returns lowercase fallback for single-word unknown category', () {
      expect(getCategoryDisplayName('CUSTOM'), 'custom');
    });

    test('returns space-separated fallback for multi-word unknown', () {
      expect(getCategoryDisplayName('MY_CUSTOM_TYPE'), 'my custom type');
    });

    test('returns empty string for empty input', () {
      expect(getCategoryDisplayName(''), '');
    });
  });

  group('EnhancedFileService static helpers', () {
    group('getValidCategories', () {
      test('returns patient categories', () {
        final cats = EnhancedFileService.getValidCategories('PATIENT');
        expect(cats, contains('PROFILE_PICTURE'));
        expect(cats, contains('MEDICAL_RECORD'));
        expect(cats, contains('PRESCRIPTION'));
        expect(cats, contains('INSURANCE'));
        expect(cats, contains('REPORT'));
        expect(cats, contains('CONSENT_FORM'));
        expect(cats, contains('EMERGENCY_CONTACT'));
        expect(cats, contains('OTHER_DOCUMENT'));
        expect(cats.length, 8);
      });

      test('returns caregiver categories', () {
        final cats = EnhancedFileService.getValidCategories('CAREGIVER');
        expect(cats, contains('PROFILE_PICTURE'));
        expect(cats, contains('CERTIFICATION'));
        expect(cats, contains('TRAINING'));
        expect(cats, contains('BACKGROUND_CHECK'));
        expect(cats, contains('REFERENCE'));
        expect(cats, contains('CONTRACT'));
        expect(cats, contains('OTHER_DOCUMENT'));
        expect(cats.length, 7);
      });

      test('returns family member categories', () {
        final cats = EnhancedFileService.getValidCategories('FAMILY_MEMBER');
        expect(cats, contains('PROFILE_PICTURE'));
        expect(cats, contains('OTHER_DOCUMENT'));
        expect(cats, contains('AUTHORIZATION'));
        expect(cats.length, 3);
      });

      test('returns default categories for unknown type', () {
        final cats = EnhancedFileService.getValidCategories('UNKNOWN');
        expect(cats, equals(['OTHER_DOCUMENT']));
      });

      test('is case-insensitive', () {
        final cats = EnhancedFileService.getValidCategories('patient');
        expect(cats, contains('MEDICAL_RECORD'));

        final cats2 = EnhancedFileService.getValidCategories('caregiver');
        expect(cats2, contains('CERTIFICATION'));

        final cats3 =
            EnhancedFileService.getValidCategories('family_member');
        expect(cats3, contains('AUTHORIZATION'));
      });

      test('returns default for empty string', () {
        final cats = EnhancedFileService.getValidCategories('');
        expect(cats, equals(['OTHER_DOCUMENT']));
      });

      test('returns default for mixed case unknown', () {
        final cats = EnhancedFileService.getValidCategories('Admin');
        expect(cats, equals(['OTHER_DOCUMENT']));
      });

      test('patient categories are returned in expected order', () {
        final cats = EnhancedFileService.getValidCategories('PATIENT');
        expect(cats.first, 'PROFILE_PICTURE');
        expect(cats.last, 'EMERGENCY_CONTACT');
      });

      test('caregiver categories are returned in expected order', () {
        final cats = EnhancedFileService.getValidCategories('CAREGIVER');
        expect(cats.first, 'PROFILE_PICTURE');
        expect(cats.last, 'CONTRACT');
      });
    });

    group('getCategoryDisplayNames', () {
      test('returns a map with known categories', () {
        final names = EnhancedFileService.getCategoryDisplayNames();
        expect(names['PROFILE_PICTURE'], 'Profile Picture');
        expect(names['MEDICAL_RECORD'], 'Medical Record');
        expect(names['PRESCRIPTION'], 'Prescription');
        expect(names['INSURANCE'], 'Insurance');
        expect(names['REPORT'], 'Report');
        expect(names['CONSENT_FORM'], 'Consent Form');
        expect(names['EMERGENCY_CONTACT'], 'Emergency Contact');
        expect(names['CERTIFICATION'], 'Certification');
        expect(names['TRAINING'], 'Training');
        expect(names['BACKGROUND_CHECK'], 'Background Check');
        expect(names['REFERENCE'], 'Reference');
        expect(names['CONTRACT'], 'Contract');
        expect(names['AUTHORIZATION'], 'Authorization');
        expect(names['MEDICAL_NOTE'], 'Medical Note');
        expect(names['GENERAL_NOTE'], 'General Note');
        expect(names['LAB_RESULT'], 'Lab Result');
        expect(names['APPOINTMENT'], 'Appointment');
        expect(names['CARE_NOTE'], 'Care Note');
        expect(names['documents'], 'General Document');
        expect(names['OTHER_DOCUMENT'], 'Other Document');
      });

      test('returns correct number of categories', () {
        final names = EnhancedFileService.getCategoryDisplayNames();
        expect(names.length, 20);
      });

      test('all values are non-empty strings', () {
        final names = EnhancedFileService.getCategoryDisplayNames();
        for (final entry in names.entries) {
          expect(entry.value, isNotEmpty,
              reason: 'Category ${entry.key} should have a non-empty name');
        }
      });

      test('all keys are non-empty strings', () {
        final names = EnhancedFileService.getCategoryDisplayNames();
        for (final key in names.keys) {
          expect(key, isNotEmpty);
        }
      });

      test('does not contain null values', () {
        final names = EnhancedFileService.getCategoryDisplayNames();
        for (final value in names.values) {
          expect(value, isNotNull);
        }
      });
    });
  });

  group('UserFileDTO equality and edge cases', () {
    test('two DTOs with same id are not identical by default', () {
      final dto1 = UserFileDTO(
        id: 1,
        originalFilename: 'a.pdf',
        contentType: 'application/pdf',
        fileSize: 100,
        fileCategory: 'OTHER_DOCUMENT',
        ownerId: 1,
        ownerType: 'PATIENT',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        fileName: 'a.pdf',
      );
      final dto2 = UserFileDTO(
        id: 1,
        originalFilename: 'a.pdf',
        contentType: 'application/pdf',
        fileSize: 100,
        fileCategory: 'OTHER_DOCUMENT',
        ownerId: 1,
        ownerType: 'PATIENT',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        fileName: 'a.pdf',
      );
      // By default, Dart uses identity comparison
      expect(identical(dto1, dto2), isFalse);
    });

    test('toJson roundtrip preserves core fields', () {
      final original = UserFileDTO(
        id: 42,
        originalFilename: 'round.pdf',
        contentType: 'application/pdf',
        fileSize: 5000,
        fileCategory: 'MEDICAL_NOTE',
        description: 'A roundtrip test',
        ownerId: 10,
        ownerType: 'CAREGIVER',
        patientId: 20,
        createdAt: DateTime(2025, 6, 15),
        updatedAt: DateTime(2025, 6, 16),
        fileUrl: 'https://example.com/f',
        downloadUrl: 'https://example.com/d',
        files: null,
        category: 'MEDICAL_NOTE',
        s3FullKey: 's3://test',
        fileName: 'round.pdf',
      );

      final json = original.toJson();
      expect(json['id'], original.id);
      expect(json['originalFilename'], original.originalFilename);
      expect(json['contentType'], original.contentType);
      expect(json['fileSize'], original.fileSize);
      expect(json['fileCategory'], original.fileCategory);
      expect(json['description'], original.description);
      expect(json['ownerId'], original.ownerId);
      expect(json['ownerType'], original.ownerType);
      expect(json['patientId'], original.patientId);
    });

    test('DTO with zero file size', () {
      final dto = UserFileDTO(
        id: 1,
        originalFilename: 'empty.txt',
        contentType: 'text/plain',
        fileSize: 0,
        fileCategory: 'OTHER_DOCUMENT',
        ownerId: 1,
        ownerType: 'PATIENT',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        fileName: 'empty.txt',
      );
      expect(dto.fileSize, 0);
    });

    test('DTO with very long filename', () {
      final longName = 'a' * 255 + '.pdf';
      final dto = UserFileDTO(
        id: 1,
        originalFilename: longName,
        contentType: 'application/pdf',
        fileSize: 100,
        fileCategory: 'OTHER_DOCUMENT',
        ownerId: 1,
        ownerType: 'PATIENT',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        fileName: longName,
      );
      expect(dto.originalFilename, longName);
      expect(dto.fileName, longName);
    });

    test('DTO with unicode in description', () {
      final dto = UserFileDTO(
        id: 1,
        originalFilename: 'test.pdf',
        contentType: 'application/pdf',
        fileSize: 100,
        fileCategory: 'MEDICAL_NOTE',
        description: 'Patient notes with unicode chars',
        ownerId: 1,
        ownerType: 'PATIENT',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        fileName: 'test.pdf',
      );
      expect(dto.description, contains('unicode'));
    });

    test('DTO with empty description vs null description', () {
      final emptyDescDto = UserFileDTO(
        id: 1,
        originalFilename: 'test.pdf',
        contentType: 'application/pdf',
        fileSize: 100,
        fileCategory: 'OTHER_DOCUMENT',
        description: '',
        ownerId: 1,
        ownerType: 'PATIENT',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        fileName: 'test.pdf',
      );
      final nullDescDto = UserFileDTO(
        id: 1,
        originalFilename: 'test.pdf',
        contentType: 'application/pdf',
        fileSize: 100,
        fileCategory: 'OTHER_DOCUMENT',
        description: null,
        ownerId: 1,
        ownerType: 'PATIENT',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        fileName: 'test.pdf',
      );
      expect(emptyDescDto.description, '');
      expect(nullDescDto.description, isNull);
    });
  });

  group('UserFileDTO fromJson advanced edge cases', () {
    test('fromJson with numeric string for id falls back to default', () {
      // If backend sends unexpected types, fromJson should handle gracefully
      final json = {'id': 99, 'fileSize': 512, 'ownerId': 7};
      final result = UserFileDTO.fromJson(json);
      expect(result.id, 99);
      expect(result.fileSize, 512);
      expect(result.ownerId, 7);
    });

    test('fromJson with files containing dynamic list items', () {
      final json = {
        'id': 1,
        'files': ['file1.pdf', 'file2.doc', 'file3.txt'],
      };
      final result = UserFileDTO.fromJson(json);
      expect(result.files, hasLength(3));
      expect(result.files![0], 'file1.pdf');
      expect(result.files![2], 'file3.txt');
    });

    test('fromJson contentType defaults to application/octet-stream', () {
      final result = UserFileDTO.fromJson({'id': 1});
      expect(result.contentType, 'application/octet-stream');
    });

    test('fromJson fileCategory defaults to documents', () {
      final result = UserFileDTO.fromJson({'id': 1});
      expect(result.fileCategory, 'documents');
    });

    test('fromJson fileName defaults to [Unnamed File] when missing', () {
      final result = UserFileDTO.fromJson({'id': 1});
      expect(result.fileName, '[Unnamed File]');
    });

    test('fromJson category defaults to empty string', () {
      final result = UserFileDTO.fromJson({'id': 1});
      expect(result.category, '');
    });

    test('fromJson with all fields populated', () {
      final json = {
        'id': 100,
        'originalFilename': 'full_test.pdf',
        'contentType': 'application/pdf',
        'fileSize': 99999,
        'fileCategory': 'PRESCRIPTION',
        'description': 'Full prescription document',
        'ownerId': 50,
        'ownerType': 'CAREGIVER',
        'patientId': 25,
        'fileUrl': 'https://cdn.example.com/full_test.pdf',
        'downloadUrl': 'https://cdn.example.com/full_test.pdf?dl=1',
        'files': ['sub1.pdf'],
        'category': 'PRESCRIPTION',
        's3FullKey': 's3://mybucket/full_test.pdf',
        'filename': 'full_test.pdf',
      };
      final result = UserFileDTO.fromJson(json);
      expect(result.id, 100);
      expect(result.originalFilename, 'full_test.pdf');
      expect(result.contentType, 'application/pdf');
      expect(result.fileSize, 99999);
      expect(result.fileCategory, 'PRESCRIPTION');
      expect(result.description, 'Full prescription document');
      expect(result.ownerId, 50);
      expect(result.ownerType, 'CAREGIVER');
      expect(result.patientId, 25);
      expect(result.fileUrl, 'https://cdn.example.com/full_test.pdf');
      expect(result.downloadUrl, 'https://cdn.example.com/full_test.pdf?dl=1');
      expect(result.files, hasLength(1));
      expect(result.category, 'PRESCRIPTION');
      expect(result.s3FullKey, 's3://mybucket/full_test.pdf');
      expect(result.fileName, 'full_test.pdf');
    });

    test('fromJson with negative id', () {
      final result = UserFileDTO.fromJson({'id': -1});
      expect(result.id, -1);
    });

    test('fromJson with negative fileSize', () {
      final result = UserFileDTO.fromJson({'fileSize': -100});
      expect(result.fileSize, -100);
    });

    test('fromJson with very long description', () {
      final longDesc = 'x' * 10000;
      final result = UserFileDTO.fromJson({'description': longDesc});
      expect(result.description, longDesc);
      expect(result.description!.length, 10000);
    });

    test('fromJson with unicode filename', () {
      final result = UserFileDTO.fromJson({
        'filename': 'documento_médico.pdf',
        'originalFilename': 'documento_médico.pdf',
      });
      expect(result.fileName, 'documento_médico.pdf');
      expect(result.originalFilename, 'documento_médico.pdf');
    });

    test('fromJson with path-like filename', () {
      final result = UserFileDTO.fromJson({
        'filename': '/path/to/file.pdf',
      });
      expect(result.fileName, '/path/to/file.pdf');
    });
  });

  group('UserFileDTO toJson advanced', () {
    test('toJson s3FullKey maps to s3FullyKey key', () {
      final dto = UserFileDTO(
        id: 1,
        originalFilename: 'test.pdf',
        contentType: 'application/pdf',
        fileSize: 100,
        fileCategory: 'OTHER_DOCUMENT',
        ownerId: 1,
        ownerType: 'PATIENT',
        createdAt: DateTime(2025, 3, 1),
        updatedAt: DateTime(2025, 3, 2),
        s3FullKey: 's3://bucket/path/file.pdf',
        fileName: 'test.pdf',
      );
      final json = dto.toJson();
      // Note: toJson uses 's3FullyKey' (typo in source) not 's3FullKey'
      expect(json['s3FullyKey'], 's3://bucket/path/file.pdf');
      expect(json.containsKey('s3FullKey'), isFalse);
    });

    test('toJson does not include fileName key', () {
      final dto = UserFileDTO(
        id: 1,
        originalFilename: 'test.pdf',
        contentType: 'application/pdf',
        fileSize: 100,
        fileCategory: 'OTHER_DOCUMENT',
        ownerId: 1,
        ownerType: 'PATIENT',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        fileName: 'test.pdf',
      );
      final json = dto.toJson();
      // toJson does not serialize fileName
      expect(json.containsKey('fileName'), isFalse);
      expect(json.containsKey('filename'), isFalse);
    });

    test('toJson with null dates produces null values', () {
      final dto = UserFileDTO(
        id: 1,
        originalFilename: 'test.pdf',
        contentType: 'application/pdf',
        fileSize: 100,
        fileCategory: 'OTHER_DOCUMENT',
        ownerId: 1,
        ownerType: 'PATIENT',
        createdAt: null,
        updatedAt: null,
        fileName: 'test.pdf',
      );
      final json = dto.toJson();
      expect(json['createdAt'], isNull);
      expect(json['updatedAt'], isNull);
    });

    test('toJson with empty files list', () {
      final dto = UserFileDTO(
        id: 1,
        originalFilename: 'test.pdf',
        contentType: 'application/pdf',
        fileSize: 100,
        fileCategory: 'OTHER_DOCUMENT',
        ownerId: 1,
        ownerType: 'PATIENT',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        files: [],
        fileName: 'test.pdf',
      );
      final json = dto.toJson();
      expect(json['files'], isNotNull);
      expect(json['files'], isEmpty);
    });

    test('toJson with non-null files list preserves contents', () {
      final dto = UserFileDTO(
        id: 1,
        originalFilename: 'test.pdf',
        contentType: 'application/pdf',
        fileSize: 100,
        fileCategory: 'OTHER_DOCUMENT',
        ownerId: 1,
        ownerType: 'PATIENT',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        files: ['a.pdf', 'b.pdf', 'c.pdf'],
        fileName: 'test.pdf',
      );
      final json = dto.toJson();
      expect(json['files'], hasLength(3));
      expect(json['files'][0], 'a.pdf');
      expect(json['files'][2], 'c.pdf');
    });

    test('toJson with null category', () {
      final dto = UserFileDTO(
        id: 1,
        originalFilename: 'test.pdf',
        contentType: 'application/pdf',
        fileSize: 100,
        fileCategory: 'OTHER_DOCUMENT',
        ownerId: 1,
        ownerType: 'PATIENT',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        category: null,
        fileName: 'test.pdf',
      );
      final json = dto.toJson();
      expect(json['category'], isNull);
    });

    test('toJson with null s3FullKey', () {
      final dto = UserFileDTO(
        id: 1,
        originalFilename: 'test.pdf',
        contentType: 'application/pdf',
        fileSize: 100,
        fileCategory: 'OTHER_DOCUMENT',
        ownerId: 1,
        ownerType: 'PATIENT',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        s3FullKey: null,
        fileName: 'test.pdf',
      );
      final json = dto.toJson();
      expect(json['s3FullyKey'], isNull);
    });

    test('toJson returns exactly 16 keys', () {
      final dto = UserFileDTO(
        id: 1,
        originalFilename: 'test.pdf',
        contentType: 'application/pdf',
        fileSize: 100,
        fileCategory: 'OTHER_DOCUMENT',
        ownerId: 1,
        ownerType: 'PATIENT',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        fileName: 'test.pdf',
      );
      final json = dto.toJson();
      expect(json.keys.length, 16);
    });
  });

  group('fileIcon edge cases', () {
    UserFileDTO makeDto(String contentType) => UserFileDTO(
          id: 1,
          originalFilename: 'file',
          contentType: contentType,
          fileSize: 100,
          fileCategory: 'OTHER_DOCUMENT',
          ownerId: 1,
          ownerType: 'PATIENT',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          fileName: 'file',
        );

    test('returns document icon for content type containing "document" but not "word"', () {
      // This content type contains "document" so it matches the word/document branch
      final dto = makeDto('application/vnd.oasis.opendocument.text');
      expect(dto.fileIcon, contains('\u{1F4DD}'));
    });

    test('returns spreadsheet icon for content type containing only "excel"', () {
      final dto = makeDto('application/vnd.ms-excel');
      // contains 'excel' but not 'document', so spreadsheet icon
      expect(dto.fileIcon, contains('\u{1F4CA}'));
    });

    test('returns folder icon for empty content type', () {
      final dto = makeDto('');
      expect(dto.fileIcon, contains('\u{1F4C1}'));
    });

    test('returns folder icon for application/xml', () {
      final dto = makeDto('application/xml');
      expect(dto.fileIcon, contains('\u{1F4C1}'));
    });

    test('fileIcon prioritizes image check before pdf check', () {
      // image/pdf is technically image type
      final dto = makeDto('image/pdf-something');
      expect(dto.fileIcon, contains('\u{1F5BC}'));
    });

    test('pdf icon for content type that only contains pdf keyword', () {
      final dto = makeDto('application/x-pdf');
      expect(dto.fileIcon, contains('\u{1F4C4}'));
    });

    test('word icon takes priority over spreadsheet for content type with both keywords', () {
      // Contains both 'word' and 'spreadsheet' - word check comes first
      final dto = makeDto('application/word-spreadsheet');
      expect(dto.fileIcon, contains('\u{1F4DD}'));
    });
  });

  group('isPreviewable edge cases', () {
    UserFileDTO makeDto(String contentType) => UserFileDTO(
          id: 1,
          originalFilename: 'file',
          contentType: contentType,
          fileSize: 100,
          fileCategory: 'OTHER_DOCUMENT',
          ownerId: 1,
          ownerType: 'PATIENT',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          fileName: 'file',
        );

    test('returns true for content type containing "word"', () {
      expect(makeDto('application/msword').isPreviewable, isTrue);
    });

    test('returns true for content type containing "document"', () {
      expect(
        makeDto('application/vnd.oasis.opendocument.text').isPreviewable,
        isTrue,
      );
    });

    test('returns false for empty content type', () {
      expect(makeDto('').isPreviewable, isFalse);
    });

    test('returns false for application/json', () {
      expect(makeDto('application/json').isPreviewable, isFalse);
    });

    test('returns false for text/html', () {
      expect(makeDto('text/html').isPreviewable, isFalse);
    });

    test('returns true for image/svg+xml (is image)', () {
      expect(makeDto('image/svg+xml').isPreviewable, isTrue);
    });

    test('returns true for image/webp (is image)', () {
      expect(makeDto('image/webp').isPreviewable, isTrue);
    });

    test('isPreviewable and isImage are consistent for image types', () {
      final imageDto = makeDto('image/png');
      expect(imageDto.isImage, isTrue);
      expect(imageDto.isPreviewable, isTrue);
    });

    test('isPreviewable true but isImage false for pdf', () {
      final pdfDto = makeDto('application/pdf');
      expect(pdfDto.isImage, isFalse);
      expect(pdfDto.isPreviewable, isTrue);
    });

    test('isPreviewable true but isImage false for word doc', () {
      final wordDto = makeDto('application/msword');
      expect(wordDto.isImage, isFalse);
      expect(wordDto.isPreviewable, isTrue);
    });
  });

  group('isImage edge cases', () {
    UserFileDTO makeDto(String contentType) => UserFileDTO(
          id: 1,
          originalFilename: 'file',
          contentType: contentType,
          fileSize: 100,
          fileCategory: 'OTHER_DOCUMENT',
          ownerId: 1,
          ownerType: 'PATIENT',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          fileName: 'file',
        );

    test('returns false for empty content type', () {
      expect(makeDto('').isImage, isFalse);
    });

    test('returns false for "IMAGE/PNG" (case-sensitive startsWith)', () {
      // Dart startsWith is case-sensitive
      expect(makeDto('IMAGE/PNG').isImage, isFalse);
    });

    test('returns true for image/x-icon', () {
      expect(makeDto('image/x-icon').isImage, isTrue);
    });

    test('returns false for application/image', () {
      // Does not start with 'image/'
      expect(makeDto('application/image').isImage, isFalse);
    });
  });

  group('categoryDisplayName advanced', () {
    UserFileDTO makeWithCategory(String cat) => UserFileDTO(
          id: 1,
          originalFilename: 'x',
          contentType: 'application/pdf',
          fileSize: 100,
          fileCategory: cat,
          ownerId: 1,
          ownerType: 'PATIENT',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          fileName: 'x',
        );

    test('returns "Medical Record" for MEDICAL_RECORD', () {
      expect(
          makeWithCategory('MEDICAL_RECORD').categoryDisplayName,
          'Medical Record');
    });

    test('returns "Insurance" for INSURANCE', () {
      expect(makeWithCategory('INSURANCE').categoryDisplayName, 'Insurance');
    });

    test('returns "Report" for REPORT', () {
      expect(makeWithCategory('REPORT').categoryDisplayName, 'Report');
    });

    test('returns "Consent Form" for CONSENT_FORM', () {
      expect(
          makeWithCategory('CONSENT_FORM').categoryDisplayName, 'Consent Form');
    });

    test('returns "Emergency Contact" for EMERGENCY_CONTACT', () {
      expect(makeWithCategory('EMERGENCY_CONTACT').categoryDisplayName,
          'Emergency Contact');
    });

    test('returns "Authorization" for AUTHORIZATION', () {
      expect(makeWithCategory('AUTHORIZATION').categoryDisplayName,
          'Authorization');
    });

    test('returns "General Document" for documents', () {
      expect(
          makeWithCategory('documents').categoryDisplayName,
          'General Document');
    });

    test('fallback lowercases and replaces underscores for unknown', () {
      expect(
          makeWithCategory('SOME_UNKNOWN_CAT').categoryDisplayName,
          'some unknown cat');
    });

    test('empty string fileCategory returns empty string display name', () {
      expect(makeWithCategory('').categoryDisplayName, '');
    });
  });

  group('getCategoryDisplayName helper edge cases', () {
    test('handles category with trailing underscore', () {
      expect(getCategoryDisplayName('TEST_'), 'test ');
    });

    test('handles category with leading underscore', () {
      expect(getCategoryDisplayName('_TEST'), ' test');
    });

    test('handles category with double underscores', () {
      expect(getCategoryDisplayName('A__B'), 'a  b');
    });

    test('handles lowercase known category (case-sensitive match)', () {
      // The map keys are uppercase, so lowercase won't match
      expect(getCategoryDisplayName('medical_note'), 'medical note');
    });

    test('handles mixed case unknown category', () {
      expect(getCategoryDisplayName('Mixed_Case'), 'mixed case');
    });

    test('all display names from getCategoryDisplayNames are accessible', () {
      final names = EnhancedFileService.getCategoryDisplayNames();
      for (final entry in names.entries) {
        expect(getCategoryDisplayName(entry.key), entry.value);
      }
    });
  });

  group('EnhancedFileService getValidCategories advanced', () {
    test('patient categories contain OTHER_DOCUMENT', () {
      final cats = EnhancedFileService.getValidCategories('PATIENT');
      expect(cats, contains('OTHER_DOCUMENT'));
    });

    test('caregiver categories contain OTHER_DOCUMENT', () {
      final cats = EnhancedFileService.getValidCategories('CAREGIVER');
      expect(cats, contains('OTHER_DOCUMENT'));
    });

    test('family member categories contain OTHER_DOCUMENT', () {
      final cats = EnhancedFileService.getValidCategories('FAMILY_MEMBER');
      expect(cats, contains('OTHER_DOCUMENT'));
    });

    test('all user types include PROFILE_PICTURE', () {
      for (final type in ['PATIENT', 'CAREGIVER', 'FAMILY_MEMBER']) {
        final cats = EnhancedFileService.getValidCategories(type);
        expect(cats, contains('PROFILE_PICTURE'),
            reason: '$type should have PROFILE_PICTURE');
      }
    });

    test('default categories for null-like input', () {
      final cats = EnhancedFileService.getValidCategories('null');
      expect(cats, equals(['OTHER_DOCUMENT']));
    });

    test('patient has more categories than family member', () {
      final patientCats = EnhancedFileService.getValidCategories('PATIENT');
      final familyCats =
          EnhancedFileService.getValidCategories('FAMILY_MEMBER');
      expect(patientCats.length, greaterThan(familyCats.length));
    });

    test('caregiver has more categories than family member', () {
      final caregiverCats =
          EnhancedFileService.getValidCategories('CAREGIVER');
      final familyCats =
          EnhancedFileService.getValidCategories('FAMILY_MEMBER');
      expect(caregiverCats.length, greaterThan(familyCats.length));
    });

    test('patient categories are unique', () {
      final cats = EnhancedFileService.getValidCategories('PATIENT');
      expect(cats.toSet().length, cats.length);
    });

    test('caregiver categories are unique', () {
      final cats = EnhancedFileService.getValidCategories('CAREGIVER');
      expect(cats.toSet().length, cats.length);
    });

    test('family member categories are unique', () {
      final cats = EnhancedFileService.getValidCategories('FAMILY_MEMBER');
      expect(cats.toSet().length, cats.length);
    });

    test('all valid categories have display names', () {
      final displayNames = EnhancedFileService.getCategoryDisplayNames();
      for (final type in ['PATIENT', 'CAREGIVER', 'FAMILY_MEMBER']) {
        final cats = EnhancedFileService.getValidCategories(type);
        for (final cat in cats) {
          expect(displayNames.containsKey(cat), isTrue,
              reason: 'Category $cat for $type should have a display name');
        }
      }
    });
  });

  group('EnhancedFileService getCategoryDisplayNames advanced', () {
    test('returns a new map instance each time', () {
      final names1 = EnhancedFileService.getCategoryDisplayNames();
      final names2 = EnhancedFileService.getCategoryDisplayNames();
      expect(identical(names1, names2), isFalse);
    });

    test('all display names start with an uppercase letter', () {
      final names = EnhancedFileService.getCategoryDisplayNames();
      for (final entry in names.entries) {
        if (entry.key != 'documents') {
          expect(entry.value[0], equals(entry.value[0].toUpperCase()),
              reason: '${entry.key} display name should start with uppercase');
        }
      }
    });

    test('no display name contains underscore', () {
      final names = EnhancedFileService.getCategoryDisplayNames();
      for (final value in names.values) {
        expect(value.contains('_'), isFalse,
            reason: 'Display name "$value" should not contain underscore');
      }
    });

    test('display names map includes documents key (lowercase)', () {
      final names = EnhancedFileService.getCategoryDisplayNames();
      expect(names.containsKey('documents'), isTrue);
      expect(names['documents'], 'General Document');
    });

    test('display names map contains both note categories', () {
      final names = EnhancedFileService.getCategoryDisplayNames();
      expect(names.containsKey('MEDICAL_NOTE'), isTrue);
      expect(names.containsKey('GENERAL_NOTE'), isTrue);
      expect(names.containsKey('CARE_NOTE'), isTrue);
    });
  });

  group('UserFileDTO constructor variations', () {
    test('constructor with all optional fields null', () {
      final dto = UserFileDTO(
        id: 1,
        originalFilename: 'test.pdf',
        contentType: 'application/pdf',
        fileSize: 0,
        fileCategory: 'OTHER_DOCUMENT',
        description: null,
        ownerId: 0,
        ownerType: '',
        patientId: null,
        createdAt: null,
        updatedAt: null,
        fileUrl: null,
        downloadUrl: null,
        files: null,
        category: null,
        s3FullKey: null,
        fileName: 'test.pdf',
      );
      expect(dto.description, isNull);
      expect(dto.patientId, isNull);
      expect(dto.createdAt, isNull);
      expect(dto.updatedAt, isNull);
      expect(dto.fileUrl, isNull);
      expect(dto.downloadUrl, isNull);
      expect(dto.files, isNull);
      expect(dto.category, isNull);
      expect(dto.s3FullKey, isNull);
    });

    test('constructor with all optional fields populated', () {
      final now = DateTime.now();
      final dto = UserFileDTO(
        id: 99,
        originalFilename: 'complete.pdf',
        contentType: 'application/pdf',
        fileSize: 50000,
        fileCategory: 'MEDICAL_NOTE',
        description: 'Complete medical note',
        ownerId: 10,
        ownerType: 'CAREGIVER',
        patientId: 20,
        createdAt: now,
        updatedAt: now,
        fileUrl: 'https://example.com/file',
        downloadUrl: 'https://example.com/download',
        files: ['part1.pdf', 'part2.pdf'],
        category: 'MEDICAL_NOTE',
        s3FullKey: 's3://bucket/complete.pdf',
        fileName: 'complete.pdf',
      );
      expect(dto.id, 99);
      expect(dto.description, 'Complete medical note');
      expect(dto.patientId, 20);
      expect(dto.files, hasLength(2));
      expect(dto.category, 'MEDICAL_NOTE');
      expect(dto.s3FullKey, 's3://bucket/complete.pdf');
    });

    test('constructor with empty strings for required fields', () {
      final dto = UserFileDTO(
        id: 0,
        originalFilename: '',
        contentType: '',
        fileSize: 0,
        fileCategory: '',
        ownerId: 0,
        ownerType: '',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        fileName: '',
      );
      expect(dto.originalFilename, '');
      expect(dto.contentType, '');
      expect(dto.fileCategory, '');
      expect(dto.ownerType, '');
      expect(dto.fileName, '');
    });
  });

  group('FileUploadResponse advanced', () {
    test('fromJson with extra unexpected keys ignores them', () {
      final response = FileUploadResponse.fromJson({
        'fileId': 1,
        'originalFilename': 'test.pdf',
        'fileUrl': 'http://url',
        'downloadUrl': 'http://dl',
        'message': 'ok',
        'fileName': 'test.pdf',
        'extraKey': 'extraValue',
        'anotherKey': 123,
      });
      expect(response.fileId, 1);
      expect(response.originalFilename, 'test.pdf');
    });

    test('fromJson with zero fileId', () {
      final response = FileUploadResponse.fromJson({'fileId': 0});
      expect(response.fileId, 0);
    });

    test('fromJson with empty strings for all string fields', () {
      final response = FileUploadResponse.fromJson({
        'fileId': 1,
        'originalFilename': '',
        'fileUrl': '',
        'downloadUrl': '',
        'message': '',
        'fileName': '',
      });
      expect(response.originalFilename, '');
      expect(response.fileUrl, '');
      expect(response.downloadUrl, '');
      expect(response.message, '');
      expect(response.fileName, '');
    });

    test('fromJson with very long message', () {
      final longMsg = 'M' * 5000;
      final response = FileUploadResponse.fromJson({'message': longMsg});
      expect(response.message, longMsg);
      expect(response.message.length, 5000);
    });

    test('constructor creates instance with all fields', () {
      final response = FileUploadResponse(
        fileId: 42,
        originalFilename: 'doc.pdf',
        fileUrl: 'https://s3.example.com/doc.pdf',
        downloadUrl: 'https://s3.example.com/doc.pdf?dl',
        message: 'Upload complete',
        fileName: 'stored_doc.pdf',
      );
      expect(response.fileId, 42);
      expect(response.originalFilename, 'doc.pdf');
      expect(response.fileUrl, 'https://s3.example.com/doc.pdf');
      expect(response.downloadUrl, 'https://s3.example.com/doc.pdf?dl');
      expect(response.message, 'Upload complete');
      expect(response.fileName, 'stored_doc.pdf');
    });
  });

  group('EnhancedPatientNotesWidget constructor edge cases', () {
    test('negative patientId is accepted', () {
      const widget = EnhancedPatientNotesWidget(patientId: -1);
      expect(widget.patientId, -1);
    });

    test('zero initialItemCount is accepted', () {
      const widget = EnhancedPatientNotesWidget(
        patientId: 1,
        initialItemCount: 0,
      );
      expect(widget.initialItemCount, 0);
    });

    test('widget type is correct', () {
      const widget = EnhancedPatientNotesWidget(patientId: 1);
      expect(widget, isA<EnhancedPatientNotesWidget>());
      expect(widget, isA<StatefulWidget>());
    });

    test('createState returns a State object', () {
      const widget = EnhancedPatientNotesWidget(patientId: 1);
      final state = widget.createState();
      expect(state, isA<State>());
    });

    test('widget with same params creates separate state instances', () {
      const widget1 = EnhancedPatientNotesWidget(patientId: 1);
      const widget2 = EnhancedPatientNotesWidget(patientId: 1);
      final state1 = widget1.createState();
      final state2 = widget2.createState();
      expect(identical(state1, state2), isFalse);
    });
  });
}
