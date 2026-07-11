import 'package:care_connect_app/features/homecare_documents/models/home_care_document_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HomeCareExtractedField.fromJson', () {
    test('parses machine-generated field', () {
      final field = HomeCareExtractedField.fromJson({
        'key': 'fullName',
        'label': 'Full Name',
        'value': 'Jane Doe',
        'machineGenerated': true,
        'editable': true,
      });

      expect(field.key, 'fullName');
      expect(field.label, 'Full Name');
      expect(field.value, 'Jane Doe');
      expect(field.machineGenerated, isTrue);
      expect(field.editable, isTrue);
    });

    test('defaults to editable and not machine-generated when flags missing',
        () {
      final field = HomeCareExtractedField.fromJson({
        'key': 'phone',
        'label': 'Phone Number',
        'value': '',
      });

      expect(field.machineGenerated, isFalse);
      expect(field.editable, isTrue);
    });
  });

  group('HomeCareExtractionResult.fromJson', () {
    test('parses a prefilled backend response', () {
      final result = HomeCareExtractionResult.fromJson({
        'documentType': 'EMPLOYMENT_APPLICATION',
        'documentTypeDisplayName': 'Employment Application',
        'status': 'PREFILLED',
        'message': '2 of 8 fields were prefilled by AI.',
        'documentLink': 'homecare-documents/abc.pdf',
        'fields': [
          {
            'key': 'fullName',
            'label': 'Full Name',
            'value': 'Jane Doe',
            'machineGenerated': true,
          },
          {
            'key': 'email',
            'label': 'Email Address',
            'value': '',
            'machineGenerated': false,
          },
        ],
      });

      expect(result.manualEntryRequired, isFalse);
      expect(result.documentLink, 'homecare-documents/abc.pdf');
      expect(result.fields, hasLength(2));
      expect(result.fields.first.machineGenerated, isTrue);
      expect(result.fields.last.machineGenerated, isFalse);
    });

    test('missing status is treated as manual entry required', () {
      final result = HomeCareExtractionResult.fromJson({
        'documentType': 'TAX_FORM',
        'documentTypeDisplayName': 'Tax Form (W-4)',
        'fields': [],
      });

      expect(result.manualEntryRequired, isTrue);
    });
  });

  group('HomeCareExtractionResult.manualFallback', () {
    test('returns full schema with blank, human, editable fields', () {
      final type = defaultHomeCareDocumentTypes
          .firstWhere((t) => t.type == 'EMPLOYMENT_APPLICATION');

      final result = HomeCareExtractionResult.manualFallback(
        type,
        message: 'OCR failed',
      );

      expect(result.manualEntryRequired, isTrue);
      expect(result.message, 'OCR failed');
      expect(result.fields, hasLength(type.fields.length));
      for (final field in result.fields) {
        expect(field.value, isEmpty);
        expect(field.machineGenerated, isFalse);
        expect(field.editable, isTrue);
      }
    });

    test('fallback fields match the selected document schema exactly', () {
      final certification = defaultHomeCareDocumentTypes
          .firstWhere((t) => t.type == 'CERTIFICATION');

      final result = HomeCareExtractionResult.manualFallback(certification);

      final keys = result.fields.map((f) => f.key).toList();
      expect(keys, certification.fields.map((f) => f.key).toList());
      // No employment-application fields leak into a certification form.
      expect(keys, isNot(contains('positionAppliedFor')));
      expect(keys, isNot(contains('fullName')));
    });
  });

  group('defaultHomeCareDocumentTypes', () {
    test('mirrors the four backend document types', () {
      expect(
        defaultHomeCareDocumentTypes.map((t) => t.type),
        containsAll([
          'EMPLOYMENT_APPLICATION',
          'CERTIFICATION',
          'TAX_FORM',
          'WORK_AUTHORIZATION',
        ]),
      );
    });

    test('every type has a display name and unique non-empty field keys', () {
      for (final type in defaultHomeCareDocumentTypes) {
        expect(type.displayName, isNotEmpty);
        expect(type.fields, isNotEmpty);
        final keys = type.fields.map((f) => f.key).toList();
        expect(keys.toSet().length, keys.length,
            reason: '${type.type} has duplicate field keys');
      }
    });
  });
}
