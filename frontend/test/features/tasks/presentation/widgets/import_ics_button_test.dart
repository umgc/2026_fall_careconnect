// Tests for ImportIcsButton widget
// (lib/features/tasks/presentation/widgets/import_ics_button.dart).
//
// ImportIcsButton is a StatefulWidget whose build method only checks
// MediaQuery screen width.  API calls and file picking only happen inside
// _pickAndImportFile(), which is invoked from the dialog — not during render.
// Render-only tests are safe to run without network or platform channels.
//
// Wide screen (≥ 500 px) → ElevatedButton.icon with "Import ICS" label.
// Compact screen (< 500 px) → IconButton with tooltip "Import ICS".

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/tasks/presentation/widgets/import_ics_button.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';

Widget _wrap(Widget child, {double width = 800}) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, 800)),
        child: Scaffold(
          body: SizedBox(width: width, child: child),
        ),
      ),
    );

const _patients = {1: 'Alice', 2: 'Bob'};

// ── Helpers from calendar_assistant/import_ics_button_test.dart (merged) ──

class FakeFilePicker {
  FilePickerResult? result;

  FakeFilePicker({this.result});

  Future<FilePickerResult?> pickFiles({
    FileType type = FileType.any,
    List<String>? allowedExtensions,
  }) async {
    return result;
  }
}

void main() {
  group('ImportIcsButton – wide screen (≥ 500 px)', () {
    testWidgets('renders without crashing', (tester) async {
      // Verifies the widget builds without error on a wide screen.
      await tester
          .pumpWidget(_wrap(const ImportIcsButton(patientNames: _patients)));
      expect(find.byType(ImportIcsButton), findsOneWidget);
    });

    testWidgets('shows "Import ICS" label on wide screen', (tester) async {
      // Wide screens should show the full labelled ElevatedButton.icon.
      await tester
          .pumpWidget(_wrap(const ImportIcsButton(patientNames: _patients)));
      expect(find.text('Import ICS'), findsOneWidget);
    });

    testWidgets('shows ElevatedButton on wide screen', (tester) async {
      // Wide screens use ElevatedButton (not a plain IconButton).
      await tester
          .pumpWidget(_wrap(const ImportIcsButton(patientNames: _patients)));
      expect(find.byType(ElevatedButton), findsOneWidget);
    });

    testWidgets('shows file_upload icon on wide screen', (tester) async {
      // The ElevatedButton.icon includes Icons.file_upload.
      await tester
          .pumpWidget(_wrap(const ImportIcsButton(patientNames: _patients)));
      expect(find.byIcon(Icons.file_upload), findsOneWidget);
    });

    testWidgets('does NOT show IconButton on wide screen', (tester) async {
      // On wide screens the compact icon-only variant must not appear.
      await tester
          .pumpWidget(_wrap(const ImportIcsButton(patientNames: _patients)));
      expect(find.byType(IconButton), findsNothing);
    });
  });

  group('ImportIcsButton – compact screen (< 500 px)', () {
    testWidgets('renders without crashing on compact screen', (tester) async {
      // Verifies the widget builds on a phone-width screen.
      await tester.pumpWidget(
          _wrap(const ImportIcsButton(patientNames: _patients), width: 400));
      expect(find.byType(ImportIcsButton), findsOneWidget);
    });

    testWidgets('shows IconButton on compact screen', (tester) async {
      // Compact screens should show only an icon button to save space.
      await tester.pumpWidget(
          _wrap(const ImportIcsButton(patientNames: _patients), width: 400));
      expect(find.byType(IconButton), findsOneWidget);
    });

    testWidgets('does NOT show "Import ICS" label on compact screen',
        (tester) async {
      // The text label must not appear on compact screens.
      await tester.pumpWidget(
          _wrap(const ImportIcsButton(patientNames: _patients), width: 400));
      expect(find.text('Import ICS'), findsNothing);
    });

    testWidgets('shows file_upload icon on compact screen', (tester) async {
      // The icon-only variant still shows Icons.file_upload.
      await tester.pumpWidget(
          _wrap(const ImportIcsButton(patientNames: _patients), width: 400));
      expect(find.byIcon(Icons.file_upload), findsOneWidget);
    });

    testWidgets('does NOT show ElevatedButton on compact screen',
        (tester) async {
      // On compact screens the wide labelled variant must not appear.
      await tester.pumpWidget(
          _wrap(const ImportIcsButton(patientNames: _patients), width: 400));
      expect(find.byType(ElevatedButton), findsNothing);
    });

    testWidgets('shows "Import ICS" tooltip on compact screen', (tester) async {
      await tester.pumpWidget(
          _wrap(const ImportIcsButton(patientNames: _patients), width: 400));
      expect(find.byTooltip('Import ICS'), findsOneWidget);
    });
  });

  group('ImportIcsButton – dialog', () {
    testWidgets('tapping wide button opens import dialog', (tester) async {
      await tester
          .pumpWidget(_wrap(const ImportIcsButton(patientNames: _patients)));
      await tester.tap(find.text('Import ICS'));
      await tester.pumpAndSettle();
      expect(find.text('Import ICS'), findsAtLeastNWidgets(1));
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Choose File'), findsOneWidget);
    });

    testWidgets('tapping compact icon opens import dialog', (tester) async {
      await tester.pumpWidget(
          _wrap(const ImportIcsButton(patientNames: _patients), width: 400));
      await tester.tap(find.byIcon(Icons.file_upload));
      await tester.pumpAndSettle();
      expect(find.text('Choose File'), findsOneWidget);
    });

    testWidgets('dialog shows patient dropdown', (tester) async {
      await tester
          .pumpWidget(_wrap(const ImportIcsButton(patientNames: _patients)));
      await tester.tap(find.text('Import ICS'));
      await tester.pumpAndSettle();
      expect(find.text('Assign to patient'), findsOneWidget);
    });

    testWidgets('Cancel dismisses dialog', (tester) async {
      await tester
          .pumpWidget(_wrap(const ImportIcsButton(patientNames: _patients)));
      await tester.tap(find.text('Import ICS'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Choose File'), findsNothing);
    });

    testWidgets('Choose File without selecting patient shows snackbar',
        (tester) async {
      await tester
          .pumpWidget(_wrap(const ImportIcsButton(patientNames: _patients)));
      await tester.tap(find.text('Import ICS'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose File'));
      await tester.pumpAndSettle();
      expect(find.text('Please select a patient before importing.'),
          findsOneWidget);
    });
  });

  group('ImportIcsButton – boundary width', () {
    testWidgets('at exactly 500px shows wide button', (tester) async {
      await tester.pumpWidget(
          _wrap(const ImportIcsButton(patientNames: _patients), width: 500));
      expect(find.text('Import ICS'), findsOneWidget);
      expect(find.byType(ElevatedButton), findsOneWidget);
    });

    testWidgets('at 499px shows compact icon button', (tester) async {
      await tester.pumpWidget(
          _wrap(const ImportIcsButton(patientNames: _patients), width: 499));
      expect(find.byType(IconButton), findsOneWidget);
      expect(find.text('Import ICS'), findsNothing);
    });

    testWidgets('renders with empty patient map', (tester) async {
      await tester.pumpWidget(_wrap(const ImportIcsButton(patientNames: {})));
      expect(find.byType(ImportIcsButton), findsOneWidget);
    });
  });

  // Cases merged from calendar_assistant/import_ics_button_test.dart.
  group('merged from calendar_assistant/import_ics_button_test.dart', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    late FakeFilePicker fakePicker;

    setUp(() {
      fakePicker = FakeFilePicker();
    });

    Widget buildWidget(Map<int, String> patients) {
      return MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ImportIcsButton(
            patientNames: patients,
            onTasksImported: () {},
            filePicker: fakePicker, // inject fake picker
          ),
        ),
      );
    }

    testWidgets('shows snackbar when no patient selected', (tester) async {
      await tester.pumpWidget(buildWidget({1: 'John'}));

      await tester.tap(find.text('Import ICS'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Choose File'));
      await tester.pumpAndSettle();

      expect(
        find.text('Please select a patient before importing.'),
        findsOneWidget,
      );
    });

    testWidgets('imports valid ICS file successfully', (tester) async {
      const icsContent = '''
  BEGIN:VEVENT
  SUMMARY:Morning Medication
  DESCRIPTION:Take your meds
  DTSTART:20251019T080000
  DTEND:20251019T083000
  RRULE:FREQ=DAILY;INTERVAL=1;COUNT=2
  END:VEVENT
  ''';

      final bytes = Uint8List.fromList(utf8.encode(icsContent));
      fakePicker.result = FilePickerResult([
        PlatformFile(name: 'test.ics', bytes: bytes, size: bytes.length),
      ]);

      await tester.pumpWidget(buildWidget({1: 'John Doe'}));

      // Open import dialog
      await tester.tap(find.text('Import ICS'));
      await tester.pumpAndSettle();

      // Select a patient
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('John Doe').last);
      await tester.pumpAndSettle();

      // Trigger import
      await tester.tap(find.text('Choose File'));
      await tester.pumpAndSettle();

      // Verify UI didn't crash
      expect(find.text('Import ICS'), findsOneWidget);
    });

    testWidgets('renders Import ICS button text', (tester) async {
      await tester.pumpWidget(buildWidget({1: 'John'}));
      expect(find.text('Import ICS'), findsOneWidget);
    });

    testWidgets('renders ElevatedButton', (tester) async {
      await tester.pumpWidget(buildWidget({1: 'John'}));
      expect(find.byType(ElevatedButton), findsWidgets);
    });

    testWidgets('tapping Import ICS opens dialog', (tester) async {
      await tester.pumpWidget(buildWidget({1: 'John', 2: 'Jane'}));
      await tester.tap(find.text('Import ICS'));
      await tester.pumpAndSettle();
      // The dialog should show Choose File button
      expect(find.text('Choose File'), findsOneWidget);
    });

    testWidgets('dialog shows patient dropdown', (tester) async {
      await tester.pumpWidget(buildWidget({1: 'John', 2: 'Jane'}));
      await tester.tap(find.text('Import ICS'));
      await tester.pumpAndSettle();
      expect(find.byType(DropdownButtonFormField<int>), findsOneWidget);
    });
  });
}
