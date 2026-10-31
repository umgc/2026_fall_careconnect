// Coverage tests for FileManagementPage (lib/pages/file_management_page.dart):
// the upload tab's child widget callbacks (file upload, manual text entry,
// speech-to-text and home-care digitization) show error snackbars and
// refresh the file list on success.

import 'dart:convert';

import 'package:care_connect_app/features/homecare_documents/widgets/home_care_digitization_card.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/pages/file_management_page.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/enhanced_file_service.dart';
import 'package:care_connect_app/widgets/file_upload_widget.dart';
import 'package:care_connect_app/widgets/manual_text_entry_upload.dart';
import 'package:care_connect_app/widgets/speech_to_text_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../mock_user_provider.dart';

final _response = FileUploadResponse(
  fileId: 1,
  originalFilename: 'a.txt',
  fileUrl: '',
  downloadUrl: '',
  message: '',
  fileName: 'a.txt',
);

void main() {
  late int listCalls;

  setUp(() {
    listCalls = 0;
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        if (call.method == 'readAll') return <String, String>{};
        if (call.method == 'containsKey') return false;
        return null;
      },
    );
  });

  MockClient client() => MockClient((req) async {
        if (req.url.path.endsWith('/list')) {
          listCalls++;
          return http.Response(jsonEncode({'files': []}), 200);
        }
        return http.Response('{}', 404);
      });

  Future<void> pumpUploadTab(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 6000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => ChangeNotifierProvider<UserProvider>.value(
          value: MockUserProvider(),
          child: const FileManagementPage(),
        ),
      ),
    ]);
    await tester.pumpWidget(MaterialApp.router(
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final t = lookupAppLocalizations(const Locale('en'));
    await tester.tap(find.text(t.filemanage_upload));
    await tester.pumpAndSettle();
  }

  Future<void> expectSnack(WidgetTester tester, String text) async {
    await tester.pump();
    expect(find.text(text), findsOneWidget);
    ScaffoldMessenger.of(tester.element(find.byType(TabBar)))
        .removeCurrentSnackBar();
    await tester.pumpAndSettle();
  }

  testWidgets('upload tab callbacks report errors and refresh on success',
      (tester) async {
    await http.runWithClient(() async {
      await pumpUploadTab(tester);
      final initialLoads = listCalls;

      final upload =
          tester.widget<FileUploadWidget>(find.byType(FileUploadWidget));
      upload.onUploadError!('upload failed');
      await expectSnack(tester, 'upload failed');
      upload.onUploadSuccess!(_response);
      await tester.pump(const Duration(milliseconds: 100));

      final manual =
          tester.widget<ManualTextEntryCard>(find.byType(ManualTextEntryCard));
      manual.onUploadError!('manual failed');
      await expectSnack(tester, 'manual failed');
      manual.onUploadSuccess!(_response);
      await tester.pump(const Duration(milliseconds: 100));

      final speech =
          tester.widget<SpeechToTextCard>(find.byType(SpeechToTextCard));
      speech.onUploadError!('speech failed');
      await expectSnack(tester, 'speech failed');
      speech.onUploadSuccess!(_response);
      await tester.pump(const Duration(milliseconds: 100));

      tester
          .widget<HomeCareDigitizationCard>(
              find.byType(HomeCareDigitizationCard))
          .onSaved!();
      await tester.pump(const Duration(milliseconds: 100));

      // Each success callback reloaded the file list.
      expect(listCalls - initialLoads, 4);
    }, client);
  });
}
