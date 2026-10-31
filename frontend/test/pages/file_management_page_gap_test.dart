// Gap tests for FileManagementPage (lib/pages/file_management_page.dart):
// the upload tab's manual text entry card reports success (the file list is
// reloaded) and failure (an error snackbar) back to the page.
//
// ComprehensiveFileService/EnhancedFileService use package:http, so the body
// runs inside http.runWithClient with a MockClient. No network is used.

import 'dart:convert';

import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/pages/file_management_page.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/comprehensive_file_service.dart';
import 'package:care_connect_app/widgets/manual_text_entry_upload.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../mock_user_provider.dart';

const _secureStorage =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

class _Backend {
  _Backend({this.uploadCode = 200});

  int uploadCode;
  final List<String> requests = <String>[];
  final List<String> uploadBodies = <String>[];

  MockClient client() => MockClient((req) async {
        requests.add('${req.method} ${req.url.path}');
        if (req.url.path.endsWith('/list')) {
          return http.Response(jsonEncode({'files': []}), 200);
        }
        if (req.url.path.endsWith('/upload')) {
          uploadBodies.add(req.body);
          return uploadCode == 200
              ? http.Response(
                  jsonEncode({'fileId': 9, 'fileName': 'visit_note.txt'}),
                  200,
                )
              : http.Response(jsonEncode({'error': 'rejected'}), uploadCode);
        }
        return http.Response('{}', 404);
      });
}

Future<void> _openUploadTab(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 3600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider<UserProvider>.value(
      value: MockUserProvider(),
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: FileManagementPage(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  final t = lookupAppLocalizations(const Locale('en'));
  await tester.tap(find.text(t.filemanage_upload));
  await tester.pumpAndSettle();
}

Future<void> _saveNote(WidgetTester tester) async {
  final t = lookupAppLocalizations(const Locale('en'));
  final card = find.byType(ManualTextEntryCard);
  await tester.ensureVisible(card);
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(
      of: card,
      matching: find.byType(DropdownButtonFormField<FileCategory>),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining(FileCategory.clinicalNotes.icon).last);
  await tester.pumpAndSettle();
  final fields =
      find.descendant(of: card, matching: find.byType(TextFormField));
  await tester.enterText(fields.at(0), 'visit_note');
  await tester.enterText(fields.at(1), 'Blood pressure was normal.');
  await tester.tap(
    find.descendant(
        of: card, matching: find.text(t.manualentrywidget_saveToFile)),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorage, (call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorage, null);
  });

  testWidgets('a saved text note is uploaded and the file list reloads',
      (tester) async {
    final backend = _Backend();
    await http.runWithClient(() async {
      await _openUploadTab(tester);
      final listsBefore =
          backend.requests.where((r) => r.endsWith('/list')).length;
      expect(listsBefore, 1);

      await _saveNote(tester);

      expect(backend.uploadBodies, hasLength(1));
      expect(backend.uploadBodies.single, contains('Blood pressure'));
      // The card resets itself after a successful save.
      expect(find.text('visit_note'), findsNothing);
      // The page refreshed its list after the upload succeeded.
      expect(
        backend.requests.where((r) => r.endsWith('/list')).length,
        greaterThan(listsBefore),
      );
    }, backend.client);
  });

  testWidgets('a rejected upload surfaces an error snackbar', (tester) async {
    final backend = _Backend(uploadCode: 500);
    await http.runWithClient(() async {
      await _openUploadTab(tester);
      await _saveNote(tester);

      final t = lookupAppLocalizations(const Locale('en'));
      expect(
        find.textContaining(t.manualentrywidget_uploadFailed),
        findsWidgets,
      );
      final bar = tester.widget<SnackBar>(find.byType(SnackBar).first);
      expect(bar.backgroundColor, isNotNull);
      // No refresh happened for a failed upload.
      expect(backend.requests.where((r) => r.endsWith('/list')), hasLength(1));
    }, backend.client);
  });
}
