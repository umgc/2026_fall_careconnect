// AddMedicationModal (medication-add-input-form.dart): the label-photo entry
// point added by FEAT-32 (#215), at the modal level. The full review flow
// (prefill tracking, Table 25 fallbacks, read-aloud, accessibility) is
// test/features/health/medication_tracker/medication_photo_capture_test.dart;
// this file checks the modal's own branching: manual form by default, a scan
// that prefills switches to review, a scan that can't be read stays manual,
// and a cancelled photo pick sends nothing.
//
// Everything external is faked: the picker, the extraction call and TTS.

import 'dart:convert';

import 'package:care_connect_app/features/health/medication-tracker/data/medication_photo_tts.dart';
import 'package:care_connect_app/features/health/medication-tracker/models/medication_photo_extraction.dart';
import 'package:care_connect_app/features/health/medication-tracker/widgets/medication-add-input-form.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/tts_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

final Uint8List _imageBytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, ...utf8.encode('label')]);

class _SilentTts implements TtsEngine {
  @override
  Future<dynamic> setLanguage(String language) async {}
  @override
  Future<dynamic> setSpeechRate(double rate) async {}
  @override
  Future<dynamic> setVolume(double volume) async {}
  @override
  Future<dynamic> setPitch(double pitch) async {}
  @override
  Future<dynamic> awaitSpeakCompletion(bool awaitCompletion) async {}
  @override
  Future<dynamic> speak(String text) async {}
  @override
  Future<dynamic> stop() async {}
}

MedicationPhotoExtractedField _field(String key, String value) =>
    MedicationPhotoExtractedField(key: key, label: key, value: value, machineGenerated: value.isNotEmpty);

final _prefilled = MedicationPhotoExtractionResult(
  status: MedicationPhotoExtractionStatus.prefilled,
  fields: [
    _field(MedicationPhotoFieldKey.medicationName, 'Metformin'),
    _field(MedicationPhotoFieldKey.dosage, '500 mg'),
    _field(MedicationPhotoFieldKey.frequency, 'Twice daily'),
    _field(MedicationPhotoFieldKey.medicationType, 'PRESCRIPTION'),
  ],
);

final _unreadable = MedicationPhotoExtractionResult(
  status: MedicationPhotoExtractionStatus.manualEntryRequired,
  message: 'The photo could not be read. Please enter the medication manually.',
  fields: const [],
);

UserProvider _patient() {
  final p = UserProvider();
  p.setUser(UserSession(id: 1, email: 'qa@example.test', role: 'PATIENT', token: 't', patientId: 5));
  return p;
}

class _Calls {
  int picks = 0;
  int extracts = 0;
}

Future<_Calls> _pump(
  WidgetTester tester, {
  MedicationPhotoExtractionResult? result,
  bool cancelPick = false,
}) async {
  tester.view.physicalSize = const Size(900, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final calls = _Calls();
  await tester.pumpWidget(ChangeNotifierProvider<UserProvider>.value(
    value: _patient(),
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: AddMedicationModal(
          onMedicationAdded: (_) {},
          pickLabelPhoto: () async {
            calls.picks++;
            return cancelPick ? null : XFile.fromData(_imageBytes, name: 'label.jpg', mimeType: 'image/jpeg');
          },
          extractLabelPhoto: (_, __, ___) async {
            calls.extracts++;
            return result!;
          },
          readAloud: MedicationPhotoTts(engine: _SilentTts()),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return calls;
}

Future<void> _scan(WidgetTester tester) async {
  final button = find.byKey(const Key('medication-photo-capture-button'));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

String _text(WidgetTester tester, String key) =>
    tester.widget<TextFormField>(find.byKey(Key(key))).controller!.text;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    final messenger = TestWidgetsFlutterBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('dev.fluttercommunity.plus/connectivity'),
        (call) async => call.method == 'check' ? ['wifi'] : null);
    messenger.setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/connectivity_status'), (call) async => null);
    messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (call) async => null);
  });

  testWidgets('opens as the manual form, with Scan Label offered and no review controls', (tester) async {
    await _pump(tester, result: _prefilled);

    expect(find.text('Add New Medication'), findsOneWidget);
    expect(find.byKey(const Key('medication-photo-capture-button')), findsOneWidget);
    expect(find.byKey(const Key('medication-photo-read-aloud-button')), findsNothing);
    expect(_text(tester, 'medication-name-field'), isEmpty);
  });

  testWidgets('a label that reads switches to review with the fields prefilled', (tester) async {
    final calls = await _pump(tester, result: _prefilled);

    await _scan(tester);

    expect(calls.picks, 1);
    expect(calls.extracts, 1);
    expect(find.text('Review Medication'), findsOneWidget);
    expect(_text(tester, 'medication-name-field'), 'Metformin');
    expect(_text(tester, 'medication-dosage-field'), '500 mg');
  });

  testWidgets('a label that cannot be read stays on the manual form with nothing filled in', (tester) async {
    await _pump(tester, result: _unreadable);

    await _scan(tester);

    expect(find.text('Review Medication'), findsNothing);
    expect(_text(tester, 'medication-name-field'), isEmpty);
    expect(find.textContaining('enter the medication manually'), findsWidgets);
  });

  testWidgets('cancelling the photo pick sends nothing for extraction', (tester) async {
    final calls = await _pump(tester, cancelPick: true);

    await _scan(tester);

    expect(calls.picks, 1);
    expect(calls.extracts, 0);
    expect(find.text('Add New Medication'), findsOneWidget);
  });
}
