import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/services/comprehensive_file_service.dart';
import 'package:care_connect_app/services/enhanced_file_service.dart' show FileUploadResponse;

/// Tests for the Home-Care Document Intake Workflow on the frontend:
/// typed category alignment, the hiring/onboarding document-type selector,
/// and client-side validation of the intake upload.
void main() {
  group('Frontend-to-backend category mapping', () {
    // Confirms comprehensive_file_service.dart sends backend-compatible values
    // (UserFile.FileCategory tokens), not the old mismatched strings.
    test('core category values match backend canonical tokens', () {
      expect(FileCategory.medicalReport.value, 'MEDICAL_RECORD');
      expect(FileCategory.clinicalNotes.value, 'CLINICAL_NOTE');
      expect(FileCategory.profilePicture.value, 'PROFILE_IMAGE');
      expect(FileCategory.insuranceDoc.value, 'INSURANCE_DOCUMENT');
      expect(FileCategory.labResult.value, 'LAB_RESULT');
      expect(FileCategory.prescription.value, 'PRESCRIPTION');
      expect(FileCategory.generalDocument.value, 'OTHER_DOCUMENT');
    });

    test('employment intake category values match backend tokens', () {
      expect(FileCategory.employmentApplication.value, 'EMPLOYMENT_APPLICATION');
      expect(FileCategory.onboardingForm.value, 'ONBOARDING_FORM');
      expect(FileCategory.backgroundCheck.value, 'BACKGROUND_CHECK');
      expect(FileCategory.certification.value, 'CERTIFICATION');
      expect(FileCategory.reference.value, 'REFERENCE');
      expect(FileCategory.employmentContract.value, 'EMPLOYMENT_CONTRACT');
      expect(FileCategory.taxForm.value, 'TAX_FORM');
      expect(FileCategory.workAuthorization.value, 'WORK_AUTHORIZATION');
    });

    test('category values are UPPER_SNAKE_CASE (backend enum-compatible)', () {
      final valid = RegExp(r'^[A-Z][A-Z_]*[A-Z]$');
      for (final c in FileCategory.values) {
        expect(valid.hasMatch(c.value), isTrue,
            reason: '${c.name} -> "${c.value}" is not a backend-compatible token');
      }
    });
  });

  group('Employment intake category set', () {
    test('exactly the 8 hiring/onboarding types are intake types', () {
      expect(FileCategory.employmentIntake.length, 8);
      for (final c in FileCategory.employmentIntake) {
        expect(c.isEmploymentIntake, isTrue);
      }
    });

    test('non-employment categories are not intake types', () {
      expect(FileCategory.medicalReport.isEmploymentIntake, isFalse);
      expect(FileCategory.profilePicture.isEmploymentIntake, isFalse);
      expect(FileCategory.generalDocument.isEmploymentIntake, isFalse);
    });
  });

  group('Category dropdown (upload UI)', () {
    testWidgets('shows hiring/onboarding document types', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: EmploymentDocumentTypeDropdown()),
      ));
      await tester.pumpAndSettle();

      // Default selection shows the first intake type in the field.
      expect(find.textContaining('Employment Application'), findsWidgets);

      // Opening the menu reveals all 8 hiring/onboarding types.
      await tester.tap(find.byType(DropdownButtonFormField<FileCategory>));
      await tester.pumpAndSettle();

      expect(find.textContaining('Onboarding Form'), findsWidgets);
      expect(find.textContaining('Background Check'), findsWidgets);
      expect(find.textContaining('Work Authorization'), findsWidgets);
    });

    testWidgets('required document type: a valid intake type is always selected',
        (tester) async {
      FileCategory? selected;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: EmploymentDocumentTypeDropdown(
            onChanged: (value) => selected = value,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Pick a type from the menu (context/type selection before upload).
      await tester.tap(find.byType(DropdownButtonFormField<FileCategory>));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Onboarding Form').last);
      await tester.pumpAndSettle();

      expect(selected, isNotNull);
      expect(selected!.isEmploymentIntake, isTrue);
      expect(selected, FileCategory.onboardingForm);
    });
  });

  group('Invalid category UI guard', () {
    // Confirms users get a clear, early rejection when a non-intake type is
    // submitted to the intake flow — the call returns null without a network
    // round-trip, so the UI can surface an error.
    test('uploadEmploymentDocument rejects a non-intake category', () async {
      final result = await ComprehensiveFileService.uploadEmploymentDocument(
        documentFile: File('unused-in-this-path.txt'),
        documentType: FileCategory.medicalReport, // not an intake type
      );
      expect(result, isNull);
    });

    test('uploadEmploymentDocument accepts context params for intake types', () {
      // The API surface lets the caller choose owner/patient/care-circle context
      // before upload (patientId / careCircleId). This guards the signature so a
      // refactor cannot silently drop context wiring.
      Future<FileUploadResponse?> call() =>
          ComprehensiveFileService.uploadEmploymentDocument(
            documentFile: File('unused.txt'),
            documentType: FileCategory.onboardingForm,
            patientId: 1,
            careCircleId: 1,
            description: 'onboarding packet',
          );
      expect(call, isA<Function>());
    });
  });
}
