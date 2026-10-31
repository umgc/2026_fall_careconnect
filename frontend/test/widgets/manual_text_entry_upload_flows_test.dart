// ManualTextEntryCard happy path: choose a category from the full list,
// enter a file name and content, and save it (MockClient upload), then a
// second save that the backend rejects.

import 'dart:convert';

import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/comprehensive_file_service.dart';
import 'package:care_connect_app/services/enhanced_file_service.dart';
import 'package:care_connect_app/widgets/manual_text_entry_upload.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import '../mock_user_provider.dart';

const _secureStorage =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorage, (call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorage, null);
  });

  testWidgets('typed notes are uploaded as a text file', (tester) async {
    final t = lookupAppLocalizations(const Locale('en'));
    final uploads = <FileUploadResponse>[];
    final errors = <String>[];
    var status = 200;
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await http.runWithClient(() async {
      await tester.pumpWidget(
        ChangeNotifierProvider<UserProvider>.value(
          value: MockUserProvider(),
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SingleChildScrollView(
                child: ManualTextEntryCard(
                  patientId: 4,
                  onUploadSuccess: uploads.add,
                  onUploadError: errors.add,
                ),
              ),
            ),
          ),
        ),
      );

      Future<void> fillAndSave() async {
        await tester.tap(find.byType(DropdownButtonFormField<FileCategory>));
        await tester.pumpAndSettle();
        await tester
            .tap(find.textContaining(FileCategory.clinicalNotes.icon).last);
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextFormField).at(0), 'visit_note');
        await tester.enterText(find.byType(TextFormField).at(1), 'All good.');
        await tester.tap(find.text(t.manualentrywidget_saveToFile));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
      }

      await fillAndSave();
      status = 500;
      await fillAndSave();
    },
        () => MockClient((request) async {
              return status == 200
                  ? http.Response(
                      jsonEncode({'fileId': 3, 'fileName': 'visit_note.txt'}),
                      200,
                    )
                  : http.Response(jsonEncode({'error': 'nope'}), 500);
            }));

    expect(uploads.single.fileName, 'visit_note.txt');
    expect(errors, hasLength(1));
  });
}
