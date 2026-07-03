import 'dart:async';
import 'dart:typed_data';

import 'package:care_connect_app/features/homecare_documents/models/home_care_document_models.dart';
import 'package:care_connect_app/features/homecare_documents/pages/home_care_document_review_page.dart';
import 'package:care_connect_app/features/homecare_documents/services/home_care_document_api.dart';
import 'package:care_connect_app/features/homecare_documents/widgets/home_care_digitization_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final pickedFile = PickedHomeCareFile(
    bytes: Uint8List.fromList([1, 2, 3]),
    name: 'employment_application.pdf',
  );

  HomeCareDocumentTypeInfo employmentType() => defaultHomeCareDocumentTypes
      .firstWhere((t) => t.type == 'EMPLOYMENT_APPLICATION');

  HomeCareExtractionResult prefilledResult() {
    return const HomeCareExtractionResult(
      documentType: 'EMPLOYMENT_APPLICATION',
      documentTypeDisplayName: 'Employment Application',
      status: HomeCareExtractionStatus.prefilled,
      message: '1 of 8 fields were prefilled by AI. Review and edit before saving.',
      fields: [
        HomeCareExtractedField(
          key: 'fullName',
          label: 'Full Name',
          value: 'Jane Doe',
          machineGenerated: true,
        ),
      ],
    );
  }

  Widget wrap({
    HomeCareExtractor? extractor,
    List<PickedHomeCareFile>? initialFiles,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: HomeCareDigitizationCard(
            patientId: 1,
            typesLoader: () async => defaultHomeCareDocumentTypes,
            extractor: extractor,
            initialFiles: initialFiles,
          ),
        ),
      ),
    );
  }

  // ElevatedButton.icon builds a private ElevatedButton subclass, so match by
  // predicate instead of exact type.
  Finder digitizeButton() => find.ancestor(
        of: find.text('Digitize & Review'),
        matching: find.byWidgetPredicate((w) => w is ElevatedButton),
      );

  Future<void> selectDocumentType(WidgetTester tester, String name) async {
    await tester.tap(find.text('Select document type'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(name).last);
    await tester.pumpAndSettle();
  }

  group('document-type selection', () {
    testWidgets('shows document-type dropdown before processing',
        (tester) async {
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      expect(find.text('Home Care Document Digitization'), findsOneWidget);
      expect(find.text('Select document type'), findsOneWidget);
      expect(find.text('Digitize & Review'), findsOneWidget);
    });

    testWidgets('digitize is disabled until a type and files are selected',
        (tester) async {
      await tester.pumpWidget(wrap(initialFiles: [pickedFile]));
      await tester.pumpAndSettle();

      final button = tester.widget<ElevatedButton>(digitizeButton());
      expect(button.onPressed, isNull, reason: 'no type selected yet');

      await selectDocumentType(tester, 'Employment Application');

      final enabledButton = tester.widget<ElevatedButton>(digitizeButton());
      expect(enabledButton.onPressed, isNotNull);
    });

    testWidgets('dropdown lists all supported hiring document types',
        (tester) async {
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Select document type'));
      await tester.pumpAndSettle();

      expect(find.text('Employment Application'), findsWidgets);
      expect(find.text('Certification / License'), findsWidgets);
      expect(find.text('Tax Form (W-4)'), findsWidgets);
      expect(find.text('Work Authorization (I-9)'), findsWidgets);
    });
  });

  group('extraction flow', () {
    testWidgets('shows loading state during extraction', (tester) async {
      final completer = Completer<HomeCareExtractionResult>();

      await tester.pumpWidget(wrap(
        initialFiles: [pickedFile],
        extractor: ({required documentType, required files}) =>
            completer.future,
      ));
      await tester.pumpAndSettle();
      await selectDocumentType(tester, 'Employment Application');

      await tester.tap(find.text('Digitize & Review'));
      await tester.pump();

      expect(find.text('Processing...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      completer.complete(prefilledResult());
      await tester.pumpAndSettle();

      expect(find.text('Processing...'), findsNothing);
    });

    testWidgets('successful extraction opens review with prefilled fields',
        (tester) async {
      await tester.pumpWidget(wrap(
        initialFiles: [pickedFile],
        extractor: ({required documentType, required files}) async =>
            prefilledResult(),
      ));
      await tester.pumpAndSettle();
      await selectDocumentType(tester, 'Employment Application');

      await tester.tap(find.text('Digitize & Review'));
      await tester.pumpAndSettle();

      expect(find.byType(HomeCareDocumentReviewPage), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Jane Doe'), findsOneWidget);
      expect(
        find.text('Machine-generated — please verify before saving'),
        findsOneWidget,
      );
    });

    testWidgets('extraction failure falls back to manual-entry form',
        (tester) async {
      await tester.pumpWidget(wrap(
        initialFiles: [pickedFile],
        extractor: ({required documentType, required files}) async =>
            HomeCareExtractionResult.manualFallback(
          documentType,
          message:
              'Automatic extraction failed. Please enter the fields manually.',
        ),
      ));
      await tester.pumpAndSettle();
      await selectDocumentType(tester, 'Employment Application');

      await tester.tap(find.text('Digitize & Review'));
      await tester.pumpAndSettle();

      // Review page opened in manual mode with the failure message visible…
      expect(find.byType(HomeCareDocumentReviewPage), findsOneWidget);
      expect(
        find.text(
            'Automatic extraction failed. Please enter the fields manually.'),
        findsWidgets,
      );
      // …with the blank schema fields (the review ListView builds lazily, so
      // check presence rather than an exact count) and no AI badges.
      expect(find.byType(TextFormField), findsWidgets);
      expect(find.text(employmentType().fields.first.label), findsOneWidget);
      expect(find.byIcon(Icons.auto_awesome), findsNothing);

      // Manual entry is not blocked.
      await tester.enterText(find.byType(TextFormField).first, 'Jane Doe');
      await tester.pump();
      expect(find.widgetWithText(TextFormField, 'Jane Doe'), findsOneWidget);
    });

    testWidgets('extraction result only contains selected schema fields',
        (tester) async {
      await tester.pumpWidget(wrap(
        initialFiles: [pickedFile],
        extractor: ({required documentType, required files}) async =>
            HomeCareExtractionResult.manualFallback(documentType),
      ));
      await tester.pumpAndSettle();
      await selectDocumentType(tester, 'Certification / License');

      await tester.tap(find.text('Digitize & Review'));
      await tester.pumpAndSettle();

      expect(find.text('Certificate Holder Name'), findsOneWidget);
      expect(find.text('Position Applied For'), findsNothing);
      expect(find.text('Filing Status'), findsNothing);
    });
  });

  group('manual entry shortcut', () {
    testWidgets('"Enter manually" opens a blank schema form without files',
        (tester) async {
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();
      await selectDocumentType(tester, 'Tax Form (W-4)');

      await tester.tap(find.text('Enter manually'));
      await tester.pumpAndSettle();

      expect(find.byType(HomeCareDocumentReviewPage), findsOneWidget);
      expect(find.text('Filing Status'), findsOneWidget);
      expect(find.byIcon(Icons.auto_awesome), findsNothing);
    });
  });
}
