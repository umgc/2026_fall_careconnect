import 'package:care_connect_app/features/homecare_documents/models/home_care_document_models.dart';
import 'package:care_connect_app/features/homecare_documents/pages/home_care_document_review_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  HomeCareExtractionResult prefilledResult() {
    return const HomeCareExtractionResult(
      documentType: 'EMPLOYMENT_APPLICATION',
      documentTypeDisplayName: 'Employment Application',
      status: HomeCareExtractionStatus.prefilled,
      message: '2 of 3 fields were prefilled by AI. Review and edit before saving.',
      documentLink: 'homecare-documents/abc.pdf',
      fields: [
        HomeCareExtractedField(
          key: 'fullName',
          label: 'Full Name',
          value: 'Jane Doe',
          machineGenerated: true,
        ),
        HomeCareExtractedField(
          key: 'phone',
          label: 'Phone Number',
          value: '555-0100',
          machineGenerated: true,
        ),
        HomeCareExtractedField(
          key: 'email',
          label: 'Email Address',
          value: '',
          machineGenerated: false,
        ),
      ],
    );
  }

  Widget wrap(HomeCareExtractionResult result) {
    return MaterialApp(
      home: HomeCareDocumentReviewPage(result: result, patientId: 1),
    );
  }

  group('prefilled review', () {
    testWidgets('displays extracted field values after processing',
        (tester) async {
      await tester.pumpWidget(wrap(prefilledResult()));

      expect(find.text('Review: Employment Application'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Jane Doe'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '555-0100'), findsOneWidget);
      expect(find.text('Full Name'), findsOneWidget);
      expect(find.text('Email Address'), findsOneWidget);
    });

    testWidgets('shows machine-generated indicator beside prefilled values',
        (tester) async {
      await tester.pumpWidget(wrap(prefilledResult()));

      // Two prefilled fields carry the badge + helper text; the blank
      // human field does not.
      expect(
        find.text('Machine-generated — please verify before saving'),
        findsNWidgets(2),
      );
      // Field suffix badges (the banner also uses the icon, hence >= 2).
      expect(
        find.byIcon(Icons.auto_awesome),
        findsNWidgets(3), // 1 banner + 2 field badges
      );
    });

    testWidgets('prefilled values remain editable', (tester) async {
      await tester.pumpWidget(wrap(prefilledResult()));

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Jane Doe'),
        'Jane A. Doe',
      );
      await tester.pump();

      expect(find.widgetWithText(TextFormField, 'Jane A. Doe'), findsOneWidget);
      // Editing reclassifies the field as human-edited.
      expect(find.text('Edited by you'), findsOneWidget);
      expect(
        find.text('Machine-generated — please verify before saving'),
        findsOneWidget,
      );
    });

    testWidgets('user can clear a machine-generated value', (tester) async {
      await tester.pumpWidget(wrap(prefilledResult()));

      await tester.enterText(
        find.widgetWithText(TextFormField, '555-0100'),
        '',
      );
      await tester.pump();

      expect(find.widgetWithText(TextFormField, '555-0100'), findsNothing);
      expect(find.text('Edited by you'), findsOneWidget);
    });

    testWidgets('does not display fields outside the document schema',
        (tester) async {
      await tester.pumpWidget(wrap(prefilledResult()));

      // Only the fields carried by the result are rendered — nothing
      // invoice-shaped or from other document types.
      expect(find.byType(TextFormField), findsNWidgets(3));
      expect(find.text('Invoice Total'), findsNothing);
      expect(find.text('Certification / License Number'), findsNothing);
    });
  });

  group('manual-entry fallback', () {
    HomeCareExtractionResult manualResult({String? message}) {
      final type = defaultHomeCareDocumentTypes
          .firstWhere((t) => t.type == 'CERTIFICATION');
      return HomeCareExtractionResult.manualFallback(type, message: message);
    }

    testWidgets('shows manual-entry form when OCR fails', (tester) async {
      await tester.pumpWidget(wrap(manualResult(
          message:
              'Automatic text extraction failed. Please enter the fields manually.')));

      expect(
        find.text(
            'Automatic text extraction failed. Please enter the fields manually.'),
        findsOneWidget,
      );
      // The certification schema opens blank for manual entry (the ListView
      // builds lazily, so check presence rather than an exact count).
      expect(find.byType(TextFormField), findsWidgets);
      expect(find.text('Certificate Holder Name'), findsOneWidget);
      // No machine-generated badges anywhere.
      expect(
        find.text('Machine-generated — please verify before saving'),
        findsNothing,
      );
      expect(find.byIcon(Icons.auto_awesome), findsNothing);
    });

    testWidgets('shows manual-entry form when LLM extraction fails',
        (tester) async {
      await tester.pumpWidget(wrap(manualResult(
          message: 'AI extraction failed. Please enter the fields manually.')));

      expect(
        find.text('AI extraction failed. Please enter the fields manually.'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.edit_note), findsOneWidget);
      expect(find.byType(TextFormField), findsWidgets);
    });

    testWidgets('error message does not block manual entry', (tester) async {
      await tester.pumpWidget(wrap(manualResult(
          message: 'AI extraction failed. Please enter the fields manually.')));

      // Despite the failure banner, the user can type into the form.
      await tester.enterText(find.byType(TextFormField).first, 'Jane Doe');
      await tester.pump();

      expect(find.widgetWithText(TextFormField, 'Jane Doe'), findsOneWidget);
      // Save remains available (scroll down to it — the form is long).
      await tester.dragUntilVisible(
        find.text('Confirm & Save'),
        find.byType(ListView),
        const Offset(0, -200),
      );
      expect(find.text('Confirm & Save'), findsOneWidget);
    });

    testWidgets('manual form only shows selected document schema fields',
        (tester) async {
      await tester.pumpWidget(wrap(manualResult()));

      // Certification fields present…
      expect(find.text('Certificate Holder Name'), findsOneWidget);
      await tester.dragUntilVisible(
        find.text('Expiration Date'),
        find.byType(ListView),
        const Offset(0, -100),
      );
      expect(find.text('Expiration Date'), findsOneWidget);
      // …employment/tax fields absent.
      expect(find.text('Position Applied For'), findsNothing);
      expect(find.text('Filing Status'), findsNothing);
    });
  });
}
