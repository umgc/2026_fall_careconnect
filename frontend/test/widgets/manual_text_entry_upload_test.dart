// Tests for ManualTextEntryCard
// (lib/widgets/manual_text_entry_upload.dart).
//
// Pure form widget — no Provider usage in build, no API calls in initState.
// Tests cover initial render and form field presence.

import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/widgets/manual_text_entry_upload.dart';
import 'package:care_connect_app/services/comprehensive_file_service.dart';

Widget _wrap({int? patientId}) =>
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: ManualTextEntryCard(
          patientId: patientId,
        ),
      ),
    );

void main() {
  group('ManualTextEntryCard – initial render', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(ManualTextEntryCard), findsOneWidget);
    });

    testWidgets('shows "Manual Text Entry" heading', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Manual Text Entry'), findsOneWidget);
    });

    testWidgets('shows text_fields icon', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byIcon(Icons.text_fields), findsOneWidget);
    });

    testWidgets('shows multiple form fields (category + filename + content)',
        (tester) async {
      await tester.pumpWidget(_wrap());
      // At least 2 TextFormFields: file name + content.
      expect(find.byType(TextFormField), findsWidgets);
    });

    testWidgets('shows "File Name" label text', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('File Name'), findsOneWidget);
    });

    testWidgets('shows "File Content" label text', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('File Content'), findsOneWidget);
    });

    testWidgets('shows file name hint text', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Enter file name (no extension)'), findsOneWidget);
    });

    testWidgets('shows file content hint text', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Enter file content...'), findsOneWidget);
    });

    testWidgets('shows "Save to File" button', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Save to File'), findsOneWidget);
    });

    testWidgets('shows ElevatedButton for save', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(ElevatedButton), findsOneWidget);
    });

    testWidgets('shows category dropdown with hint', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Select Category'), findsOneWidget);
    });

    testWidgets('shows DropdownButtonFormField for category', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(DropdownButtonFormField<FileCategory>), findsOneWidget);
    });

    testWidgets('shows a Column as root', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(Column), findsWidgets);
    });
  });

  group('ManualTextEntryCard – form interaction', () {
    testWidgets('can enter file name', (tester) async {
      await tester.pumpWidget(_wrap());
      final fileNameField = find.byType(TextFormField).first;
      await tester.enterText(fileNameField, 'my_document');
      expect(find.text('my_document'), findsOneWidget);
    });

    testWidgets('can enter file content', (tester) async {
      await tester.pumpWidget(_wrap());
      final contentField = find.byType(TextFormField).last;
      await tester.enterText(contentField, 'Hello world content');
      expect(find.text('Hello world content'), findsOneWidget);
    });

    testWidgets('renders with patientId', (tester) async {
      await tester.pumpWidget(_wrap(patientId: 42));
      expect(find.byType(ManualTextEntryCard), findsOneWidget);
    });

    testWidgets('tapping Save without category shows snackbar', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.tap(find.text('Save to File'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      // With no category selected, _selectCategory() shows a SnackBar
      expect(
        find.text('Please select a file category first'),
        findsOneWidget,
      );
    });
  });

  group('ManualTextEntryCard – with allowed categories', () {
    testWidgets('renders with restricted categories', (tester) async {
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ManualTextEntryCard(
            allowedCategories: [FileCategory.medicalReport, FileCategory.labResult],
          ),
        ),
      ));
      expect(find.byType(ManualTextEntryCard), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<FileCategory>), findsOneWidget);
    });

    testWidgets('renders with all default categories when none specified', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(DropdownButtonFormField<FileCategory>), findsOneWidget);
    });
  });
}
