// SpeechToTextCard happy path: pick a category, dictate through the mocked
// speech_to_text channel, then save the text as a file (MockClient upload).

import 'dart:convert';

import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/comprehensive_file_service.dart';
import 'package:care_connect_app/services/enhanced_file_service.dart';
import 'package:care_connect_app/widgets/speech_to_text_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import '../mock_user_provider.dart';

const _speech = MethodChannel('plugin.csdcorp.com/speech_to_text');
const _secureStorage =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

void main() {
  setUp(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_secureStorage, (call) async => null);
    messenger.setMockMethodCallHandler(_speech, (call) async {
      switch (call.method) {
        case 'has_permission':
        case 'initialize':
        case 'listen':
          return true;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_secureStorage, null);
    messenger.setMockMethodCallHandler(_speech, null);
  });

  testWidgets('dictated text is saved as a file', (tester) async {
    final t = lookupAppLocalizations(const Locale('en'));
    final uploads = <FileUploadResponse>[];
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
                child: SpeechToTextCard(
                  patientId: 4,
                  onUploadSuccess: uploads.add,
                ),
              ),
            ),
          ),
        ),
      );

      // Without a category the card asks for one first.
      await tester.tap(find.text(t.speechtextwidget_startListening));
      await tester.pump();
      expect(find.text(t.manualentrywidget_selectCatFirst), findsOneWidget);

      await tester.tap(find.byType(DropdownButtonFormField<FileCategory>));
      await tester.pumpAndSettle();
      await tester
          .tap(find.textContaining(FileCategory.clinicalNotes.icon).last);
      await tester.pumpAndSettle();

      await tester.tap(find.text(t.speechtextwidget_startListening));
      await tester.pump();
      await tester.pump();
      expect(find.text(t.speechtextwidget_stopListening), findsOneWidget);

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        _speech.name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall(
            'textRecognition',
            jsonEncode({
              'resultType': 2,
              'alternates': [
                {'recognizedWords': 'patient slept well', 'confidence': 0.9},
              ],
            }),
          ),
        ),
        (ByteData? _) {},
      );
      await tester.pump();
      expect(find.textContaining('patient slept well'), findsOneWidget);

      await tester.tap(find.text(t.speechtextwidget_stopListening));
      await tester.pump();

      await tester.enterText(find.byType(TextFormField), 'sleep_note');
      await tester.tap(find.text(t.manualentrywidget_saveToFile));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Let the recogniser's listen timeout lapse after the card is removed.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 31));
    },
        () => MockClient((request) async {
              return http.Response(
                jsonEncode({'fileId': 9, 'fileName': 'sleep_note.txt'}),
                200,
              );
            }));

    expect(uploads.single.fileName, 'sleep_note.txt');
  });
}
