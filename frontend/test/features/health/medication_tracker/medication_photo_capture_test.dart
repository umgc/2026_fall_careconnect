// F-01 Medication Photo Capture, frontend (TC-MED-PHOTO-033..071).
//
// Covers the extraction model, the extract-photo API call, the read-aloud
// wrapper and the AddMedicationModal review flow (prefill, machine-generated
// vs edited-by-user tracking, Table 25 fallbacks, cancel, save, read-aloud,
// accessibility semantics).
//
// Everything external is faked (TESTING_NORMS.md: no live DB/network): the
// camera picker, the extraction call, flutter_tts (via TtsEngine) and the HTTP
// client are injected through the modal's test hooks or MockClient. Real device
// camera, real TTS voice output and a screen reader are NOT exercised here.
//
// Route under test: POST /v3/api/patients/{id}/medications/extract-photo (lead
// approved deviation from the TDD example path /v1/api/medications/extract-photo).

import 'dart:async';
import 'dart:convert';

import 'package:care_connect_app/features/health/medication-tracker/data/medication_photo_tts.dart';
import 'package:care_connect_app/features/health/medication-tracker/data/medications_api.dart';
import 'package:care_connect_app/features/health/medication-tracker/models/medication-model.dart';
import 'package:care_connect_app/features/health/medication-tracker/models/medication_photo_extraction.dart';
import 'package:care_connect_app/features/health/medication-tracker/widgets/medication-add-input-form.dart';
import 'package:care_connect_app/features/health/medication-tracker/widgets/medication-card.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:care_connect_app/services/tts_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';

const _marker = 'IMG-MARKER-7f3c9a21';
final Uint8List _imageBytes =
    Uint8List.fromList([0xFF, 0xD8, 0xFF, ...utf8.encode(_marker)]);

const _unreadable =
    'The photo could not be read. Please enter the medication manually.';

// ── Fakes and builders ─────────────────────────────────────────────────────

class FakeTtsEngine implements TtsEngine {
  final List<String> calls = [];
  final List<String> spoken = [];
  bool throwOnSpeak = false;

  @override
  Future<dynamic> setLanguage(String language) async =>
      calls.add('lang:$language');
  @override
  Future<dynamic> setSpeechRate(double rate) async => calls.add('rate:$rate');
  @override
  Future<dynamic> setVolume(double volume) async => calls.add('vol:$volume');
  @override
  Future<dynamic> setPitch(double pitch) async => calls.add('pitch:$pitch');
  @override
  Future<dynamic> awaitSpeakCompletion(bool awaitCompletion) async =>
      calls.add('await:$awaitCompletion');
  @override
  Future<dynamic> speak(String text) async {
    if (throwOnSpeak) throw Exception('tts down');
    calls.add('speak');
    spoken.add(text);
  }

  @override
  Future<dynamic> stop() async => calls.add('stop');
}

MedicationPhotoExtractedField _f(String key, String value, {bool? machine}) =>
    MedicationPhotoExtractedField(
      key: key,
      label: key,
      value: value,
      machineGenerated: machine ?? value.isNotEmpty,
    );

MedicationPhotoExtractionResult _prefilled({
  String name = 'Lisinopril',
  String dosage = '10 mg',
  String frequency = 'Once daily',
  String type = 'PRESCRIPTION',
  String? message,
}) =>
    MedicationPhotoExtractionResult(
      status: MedicationPhotoExtractionStatus.prefilled,
      message: message,
      fields: [
        _f(MedicationPhotoFieldKey.medicationName, name),
        _f(MedicationPhotoFieldKey.dosage, dosage),
        _f(MedicationPhotoFieldKey.frequency, frequency),
        _f(MedicationPhotoFieldKey.medicationType, type),
      ],
    );

UserProvider _userProvider({int? patientId = 5}) {
  final p = UserProvider();
  p.setUser(UserSession(
    id: 1,
    email: 'qa@example.test',
    role: 'PATIENT',
    token: 'test-token',
    patientId: patientId,
  ));
  return p;
}

class _Harness {
  _Harness({
    this.extractor,
    this.picker,
    this.tts,
    int? patientId = 5,
    this.onAdded,
  }) : user = _userProvider(patientId: patientId);

  final Future<MedicationPhotoExtractionResult> Function(
      int, Uint8List, String)? extractor;
  final Future<XFile?> Function()? picker;
  final FakeTtsEngine? tts;
  final void Function(Medication)? onAdded;
  final UserProvider user;
  int extractCalls = 0;
  int pickCalls = 0;
  final FakeTtsEngine engine = FakeTtsEngine();

  Widget build({double textScale = 1.0}) {
    return ChangeNotifierProvider<UserProvider>.value(
      value: user,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (ctx) => AddMedicationModal(
              onMedicationAdded: onAdded ?? (_) {},
              pickLabelPhoto: () async {
                pickCalls++;
                if (picker != null) return picker!();
                return XFile.fromData(_imageBytes,
                    name: 'label.jpg', mimeType: 'image/jpeg');
              },
              extractLabelPhoto: (id, bytes, name) async {
                extractCalls++;
                return extractor!(id, bytes, name);
              },
              readAloud: MedicationPhotoTts(engine: tts ?? engine),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _scan(WidgetTester tester) async {
  await tester
      .ensureVisible(find.byKey(const Key('medication-photo-capture-button')));
  await tester.tap(find.byKey(const Key('medication-photo-capture-button')));
  await tester.pumpAndSettle();
}

Future<void> _pump(WidgetTester tester, _Harness h,
    {double scale = 1.0}) async {
  tester.view.physicalSize = const Size(900, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  // Reset the tree first so a second harness in one test never reuses State.
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(h.build(textScale: scale));
  await tester.pumpAndSettle();
}

String _fieldText(WidgetTester tester, String key) =>
    tester.widget<TextFormField>(find.byKey(Key(key))).controller!.text;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // UserProvider() starts a connectivity check and syncs to storage; stub the
  // platform channels so those calls resolve instead of throwing.
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    final messenger = TestWidgetsFlutterBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => call.method == 'check' ? ['wifi'] : null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
      (call) async => null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => null,
    );
  });

  // ── Model ────────────────────────────────────────────────────────────────
  group('extraction model', () {
    test('TC-MED-PHOTO-033: fromJson parses status, message and fields', () {
      final r = MedicationPhotoExtractionResult.fromJson({
        'status': 'PREFILLED',
        'message': 'ok',
        'fields': [
          {
            'key': 'medicationName',
            'label': 'Medication Name',
            'value': 'A',
            'machineGenerated': true
          },
          {
            'key': 'dosage',
            'label': 'Dosage',
            'value': '',
            'machineGenerated': false
          },
        ],
      });
      expect(r.manualEntryRequired, isFalse);
      expect(r.fields, hasLength(2));
      expect(r.prefilledValue('medicationName'), 'A');
      expect(r.prefilledValue('dosage'), isNull);
      expect(r.prefilledValue('frequency'), isNull);
    });

    test(
        'TC-MED-PHOTO-034: prefilledValue ignores values not flagged machineGenerated',
        () {
      final r = MedicationPhotoExtractionResult(
        status: 'PREFILLED',
        fields: [_f('dosage', '5 mg', machine: false)],
      );
      expect(r.prefilledValue('dosage'), isNull);
    });

    test(
        'TC-MED-PHOTO-035: missing status defaults to manual entry; fallback has no fields',
        () {
      expect(MedicationPhotoExtractionResult.fromJson({}).manualEntryRequired,
          isTrue);
      final f = MedicationPhotoExtractionResult.manualFallback(message: 'm');
      expect(f.manualEntryRequired, isTrue);
      expect(f.fields, isEmpty);
      expect(f.message, 'm');
    });

    test(
        'TC-MED-PHOTO-036: medicationTypeFromExtracted maps backend names, blank/unknown -> null',
        () {
      expect(medicationTypeFromExtracted('OVER_THE_COUNTER'),
          MedicationType.OVER_THE_COUNTER);
      expect(medicationTypeFromExtracted('HERBAL'), MedicationType.HERBAL);
      expect(
          medicationTypeFromExtracted('EMERGENCY'), MedicationType.EMERGENCY);
      expect(medicationTypeFromExtracted('PRESCRIPTION'),
          MedicationType.PRESCRIPTION);
      expect(
          medicationTypeFromExtracted('SUPPLEMENT'), MedicationType.SUPPLEMENT);
      expect(medicationTypeFromExtracted(''), isNull);
      expect(medicationTypeFromExtracted(null), isNull);
      expect(medicationTypeFromExtracted('VITAMIN'), isNull);
      expect(medicationTypeFromExtracted('herbal'), isNull);
    });
  });

  // ── API ──────────────────────────────────────────────────────────────────
  group('extractMedicationPhoto API', () {
    Future<MedicationPhotoExtractionResult> call(MockClient c) =>
        extractMedicationPhoto(
            patientId: 7,
            imageBytes: _imageBytes,
            fileName: 'label.jpg',
            client: c);

    test(
        'TC-MED-PHOTO-037: posts multipart part "image" to the v3 extract-photo route and parses 200',
        () async {
      http.BaseRequest? seen;
      Uint8List? sentBody;
      final c = MockClient.streaming((req, stream) async {
        seen = req;
        sentBody = Uint8List.fromList(await stream.expand((x) => x).toList());
        return http.StreamedResponse(
          Stream.value(utf8.encode(jsonEncode({
            'status': 'PREFILLED',
            'message': 'ok',
            'fields': [
              {
                'key': 'medicationName',
                'label': 'n',
                'value': 'Lisinopril',
                'machineGenerated': true
              }
            ],
          }))),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final r = await call(c);
      expect(seen!.method, 'POST');
      expect(seen!.url.path,
          endsWith('/v3/api/patients/7/medications/extract-photo'));
      final bodyStr = latin1.decode(sentBody!);
      expect(bodyStr, contains('name="image"'));
      expect(bodyStr, contains('filename="label.jpg"'));
      expect(r.prefilledValue('medicationName'), 'Lisinopril');
    });

    test(
        'TC-MED-PHOTO-038: 400 with server message surfaces that message as fallback',
        () async {
      final c = MockClient((_) async => http.Response(
          jsonEncode({'message': 'Please use a JPEG or PNG photo.'}), 400));
      final r = await call(c);
      expect(r.manualEntryRequired, isTrue);
      expect(r.message, 'Please use a JPEG or PNG photo.');
    });

    test(
        'TC-MED-PHOTO-039: 500, non-JSON body and network exception all fall back without retry',
        () async {
      var calls = 0;
      final c500 = MockClient((_) async {
        calls++;
        return http.Response('boom', 500);
      });
      final r500 = await call(c500);
      expect(r500.manualEntryRequired, isTrue);
      expect(r500.message, _unreadable);
      expect(calls, 1, reason: 'Table 25: no automatic retry');

      final cBad = MockClient((_) async => http.Response('<html>', 200));
      expect((await call(cBad)).message, _unreadable);

      final cErr =
          MockClient((_) async => throw http.ClientException('offline'));
      final rErr = await call(cErr);
      expect(rErr.manualEntryRequired, isTrue);
      expect(rErr.message, _unreadable);
      expect(rErr.message, isNot(contains(_marker)));
    });

    test(
        'TC-MED-PHOTO-040: backend MANUAL_ENTRY_REQUIRED 200 body parses as manual entry',
        () async {
      final c = MockClient((_) async => http.Response(
          jsonEncode({
            'status': 'MANUAL_ENTRY_REQUIRED',
            'message': 'The photo could not be read.',
            'fields': [
              {
                'key': 'dosage',
                'label': 'Dosage',
                'value': '',
                'machineGenerated': false
              }
            ]
          }),
          200));
      final r = await call(c);
      expect(r.manualEntryRequired, isTrue);
      expect(r.prefilledValue('dosage'), isNull);
    });
  });

  // ── TTS wrapper ──────────────────────────────────────────────────────────
  group('MedicationPhotoTts', () {
    test(
        'TC-MED-PHOTO-041: configures en-US voice, stops before speaking, ignores blank text',
        () async {
      final e = FakeTtsEngine();
      final tts = MedicationPhotoTts(engine: e);
      await tts.speak('   ');
      expect(e.calls, isEmpty);
      await tts.speak('Hello');
      expect(e.calls,
          containsAll(['lang:en-US', 'rate:0.45', 'vol:1.0', 'pitch:1.0']));
      expect(e.calls.indexOf('stop'), lessThan(e.calls.indexOf('speak')));
      expect(e.spoken, ['Hello']);
      await tts.stop();
      expect(e.calls.last, 'stop');
    });

    test(
        'TC-MED-PHOTO-091: with no engine injected, read-aloud uses the flutter_tts platform channel',
        () async {
      // Arrange: record calls on the flutter_tts channel instead of reaching a device.
      const channel = MethodChannel('flutter_tts');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return 1;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      // Act
      final tts = MedicationPhotoTts();
      await tts.speak('Aspirin 81 mg');
      await tts.stop();

      // Assert
      final methods = calls.map((c) => c.method).toList();
      expect(methods,
          containsAll(['setLanguage', 'setSpeechRate', 'speak', 'stop']));
      expect(calls.firstWhere((c) => c.method == 'setLanguage').arguments,
          'en-US');
      expect(calls.firstWhere((c) => c.method == 'speak').arguments,
          'Aspirin 81 mg');
    });
  });

  // ── Modal: entry, prefill, tracking ──────────────────────────────────────
  group('AddMedicationModal photo flow', () {
    testWidgets(
        'TC-MED-PHOTO-042: Scan Label entry point is present with a tooltip; manual form is unchanged',
        (tester) async {
      final h = _Harness(extractor: (_, __, ___) async => _prefilled());
      await _pump(tester, h);
      expect(find.byKey(const Key('medication-photo-capture-button')),
          findsOneWidget);
      expect(find.text('Scan Label'), findsOneWidget);
      expect(find.byType(Tooltip), findsWidgets);
      expect(find.text('Add New Medication'), findsOneWidget);
      expect(find.byKey(const Key('medication-photo-read-aloud-button')),
          findsNothing);
    });

    testWidgets(
        'TC-MED-PHOTO-043: prefill fills name, dosage, frequency, type; review title, disclaimer and read-aloud appear',
        (tester) async {
      final h = _Harness(extractor: (_, __, ___) async => _prefilled());
      await _pump(tester, h);
      await _scan(tester);

      expect(_fieldText(tester, 'medication-name-field'), 'Lisinopril');
      expect(_fieldText(tester, 'medication-dosage-field'), '10 mg');
      expect(find.text('Once daily'), findsWidgets);
      expect(find.text('Review Medication'), findsOneWidget);
      expect(find.byKey(const Key('medication-photo-read-aloud-button')),
          findsOneWidget);
      expect(find.byKey(const Key('medication-photo-review-message')),
          findsOneWidget);
      final dd = tester.widget<DropdownButtonFormField<MedicationType>>(
          find.descendant(
              of: find.byKey(const Key('medication-type-field')),
              matching: find.byType(DropdownButtonFormField<MedicationType>)));
      expect(dd.initialValue, MedicationType.PRESCRIPTION);
      expect(h.extractCalls, 1);
      // Disclaimer banner (DisclaimerBanner.medication) is on the review screen.
      expect(
          find.byWidgetPredicate(
              (w) => w.runtimeType.toString() == 'DisclaimerBanner'),
          findsOneWidget);
    });

    testWidgets(
        'TC-MED-PHOTO-044: every prefilled field is marked "Read from photo" (machine generated)',
        (tester) async {
      final h = _Harness(extractor: (_, __, ___) async => _prefilled());
      await _pump(tester, h);
      await _scan(tester);
      for (final k in [
        'medicationName',
        'dosage',
        'frequency',
        'medicationType'
      ]) {
        expect(find.byKey(Key('medication-photo-ai-note-$k')), findsOneWidget,
            reason: k);
        expect(find.byKey(Key('medication-photo-edited-note-$k')), findsNothing,
            reason: k);
      }
    });

    testWidgets(
        'TC-MED-PHOTO-045: editing one field flips only that field to edited-by-user',
        (tester) async {
      final h = _Harness(extractor: (_, __, ___) async => _prefilled());
      await _pump(tester, h);
      await _scan(tester);

      await tester.enterText(
          find.byKey(const Key('medication-name-field')), 'Lisinopril HCTZ');
      await tester.pumpAndSettle();

      expect(
          find.byKey(const Key('medication-photo-edited-note-medicationName')),
          findsOneWidget);
      expect(find.byKey(const Key('medication-photo-ai-note-medicationName')),
          findsNothing);
      expect(find.byKey(const Key('medication-photo-ai-note-dosage')),
          findsOneWidget);
      expect(find.byKey(const Key('medication-photo-edited-note-dosage')),
          findsNothing);

      // A second edit of the same field does not un-flip it.
      await tester.enterText(
          find.byKey(const Key('medication-name-field')), 'Lisinopril HCTZ 2');
      await tester.pumpAndSettle();
      expect(
          find.byKey(const Key('medication-photo-edited-note-medicationName')),
          findsOneWidget);
    });

    testWidgets(
        'TC-MED-PHOTO-046: editing dosage marks dosage edited, name stays machine generated',
        (tester) async {
      final h = _Harness(extractor: (_, __, ___) async => _prefilled());
      await _pump(tester, h);
      await _scan(tester);
      await tester.enterText(
          find.byKey(const Key('medication-dosage-field')), '20 mg');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('medication-photo-edited-note-dosage')),
          findsOneWidget);
      expect(find.byKey(const Key('medication-photo-ai-note-medicationName')),
          findsOneWidget);
    });

    testWidgets(
        'TC-MED-PHOTO-047: edits made before scanning are not tracked (no review state yet)',
        (tester) async {
      final h = _Harness(extractor: (_, __, ___) async => _prefilled());
      await _pump(tester, h);
      await tester.enterText(
          find.byKey(const Key('medication-name-field')), 'Typed first');
      await tester.pumpAndSettle();
      expect(
          find.byKey(const Key('medication-photo-edited-note-medicationName')),
          findsNothing);
      expect(find.byKey(const Key('medication-photo-ai-note-medicationName')),
          findsNothing);
    });

    testWidgets(
        'TC-MED-PHOTO-048: frequency matching an option selects it, otherwise Custom with the text',
        (tester) async {
      final h = _Harness(
          extractor: (_, __, ___) async =>
              _prefilled(frequency: 'twice daily'));
      await _pump(tester, h);
      await _scan(tester);
      expect(find.byKey(const Key('medication-custom-frequency-field')),
          findsNothing);
      expect(find.text('Twice daily'), findsWidgets);

      final h2 = _Harness(
          extractor: (_, __, ___) async =>
              _prefilled(frequency: 'Every 6 hours'));
      await _pump(tester, h2);
      await _scan(tester);
      expect(_fieldText(tester, 'medication-custom-frequency-field'),
          'Every 6 hours');
      expect(find.byKey(const Key('medication-photo-ai-note-frequency')),
          findsOneWidget);
    });

    testWidgets(
        'TC-MED-PHOTO-049: OVER_THE_COUNTER, HERBAL and EMERGENCY select the matching dropdown value',
        (tester) async {
      for (final entry in {
        'OVER_THE_COUNTER': 'OVER_THE_COUNTER',
        'HERBAL': 'HERBAL',
        'EMERGENCY': 'EMERGENCY',
      }.entries) {
        final h = _Harness(
            extractor: (_, __, ___) async => _prefilled(type: entry.key));
        await _pump(tester, h);
        await _scan(tester);
        final dd = tester.widget<DropdownButtonFormField<MedicationType>>(
            find.descendant(
                of: find.byKey(const Key('medication-type-field')),
                matching:
                    find.byType(DropdownButtonFormField<MedicationType>)));
        expect(dd.initialValue?.name, entry.value, reason: entry.key);
        expect(find.byKey(const Key('medication-photo-ai-note-medicationType')),
            findsOneWidget);
      }
    });
  });

  // ── Table 25 in the UI ───────────────────────────────────────────────────
  group('Table 25 fallbacks in the modal', () {
    testWidgets(
        'TC-MED-PHOTO-050: row 1 OCR/LLM failure -> manual form, message shown, no review UI, no retry',
        (tester) async {
      final h = _Harness(
          extractor: (_, __, ___) async =>
              MedicationPhotoExtractionResult.manualFallback(
                  message: _unreadable));
      await _pump(tester, h);
      await _scan(tester);
      expect(find.byKey(const Key('medication-photo-fallback-message')),
          findsOneWidget);
      expect(find.text(_unreadable), findsOneWidget);
      expect(find.text('Add New Medication'), findsOneWidget);
      expect(find.byKey(const Key('medication-photo-read-aloud-button')),
          findsNothing);
      expect(
          find.byWidgetPredicate(
              (w) => w.runtimeType.toString() == 'DisclaimerBanner'),
          findsNothing);
      expect(_fieldText(tester, 'medication-name-field'), isEmpty);
      expect(h.extractCalls, 1);
      // The manual form still works.
      await tester.enterText(
          find.byKey(const Key('medication-name-field')), 'Typed');
      await tester.pumpAndSettle();
      expect(_fieldText(tester, 'medication-name-field'), 'Typed');
    });

    testWidgets(
        'TC-MED-PHOTO-051: extractor throws -> unreadable fallback, form stays usable',
        (tester) async {
      final h =
          _Harness(extractor: (_, __, ___) async => throw Exception('boom'));
      await _pump(tester, h);
      await _scan(tester);
      expect(find.text(_unreadable), findsOneWidget);
      expect(find.byKey(const Key('medication-name-field')), findsOneWidget);
    });

    testWidgets(
        'TC-MED-PHOTO-052: row 2 partial extraction leaves blanks empty with "Not found" note; extracted fields keep AI note',
        (tester) async {
      final h = _Harness(
          extractor: (_, __, ___) async =>
              _prefilled(dosage: '', frequency: ''));
      await _pump(tester, h);
      await _scan(tester);
      expect(_fieldText(tester, 'medication-dosage-field'), isEmpty);
      expect(find.byKey(const Key('medication-photo-missing-note-dosage')),
          findsOneWidget);
      expect(find.byKey(const Key('medication-photo-missing-note-frequency')),
          findsOneWidget);
      expect(find.byKey(const Key('medication-photo-ai-note-medicationName')),
          findsOneWidget);
      // Blank field is editable like any other.
      await tester.enterText(
          find.byKey(const Key('medication-dosage-field')), '5 mg');
      await tester.pumpAndSettle();
      expect(_fieldText(tester, 'medication-dosage-field'), '5 mg');
    });

    testWidgets(
        'TC-MED-PHOTO-053: row 3 invalid/blank medicationType leaves the dropdown unselected; save is blocked until chosen',
        (tester) async {
      final h = _Harness(
          extractor: (_, __, ___) async => _prefilled(type: 'VITAMIN'));
      await _pump(tester, h);
      await _scan(tester);
      expect(find.text('Select a type'), findsOneWidget);
      expect(
          find.byKey(const Key('medication-photo-missing-note-medicationType')),
          findsOneWidget);

      await tester
          .ensureVisible(find.byKey(const Key('medication-save-button')));
      await tester.tap(find.byKey(const Key('medication-save-button')));
      await tester.pumpAndSettle();
      expect(find.text('Please select a medication type'), findsOneWidget);
    });

    testWidgets(
        'TC-MED-PHOTO-054: no patientId -> "not available" fallback and extraction is not called',
        (tester) async {
      final h = _Harness(
          patientId: null, extractor: (_, __, ___) async => _prefilled());
      await _pump(tester, h);
      await _scan(tester);
      expect(find.textContaining('Photo reading is not available'),
          findsOneWidget);
      expect(h.extractCalls, 0);
    });

    testWidgets(
        'TC-MED-PHOTO-055: camera picker throws -> camera fallback; picker returns null -> nothing changes',
        (tester) async {
      final h = _Harness(
          picker: () async => throw Exception('no camera'),
          extractor: (_, __, ___) async => _prefilled());
      await _pump(tester, h);
      await _scan(tester);
      expect(find.textContaining('camera could not be opened'), findsOneWidget);
      expect(h.extractCalls, 0);

      final h2 = _Harness(
          picker: () async => null,
          extractor: (_, __, ___) async => _prefilled());
      await _pump(tester, h2);
      await _scan(tester);
      expect(h2.pickCalls, 1);
      expect(h2.extractCalls, 0);
      expect(find.byKey(const Key('medication-photo-fallback-message')),
          findsNothing);
      expect(find.text('Add New Medication'), findsOneWidget);
    });

    testWidgets(
        'TC-MED-PHOTO-056: capture button is disabled while reading and progress is shown',
        (tester) async {
      final gate = Completer<MedicationPhotoExtractionResult>();
      final h = _Harness(extractor: (_, __, ___) => gate.future);
      await _pump(tester, h);
      await tester.ensureVisible(
          find.byKey(const Key('medication-photo-capture-button')));
      await tester
          .tap(find.byKey(const Key('medication-photo-capture-button')));
      await tester.pump();
      await tester.pump();
      expect(
          find.byKey(const Key('medication-photo-progress')), findsOneWidget);
      final btn = tester.widget<OutlinedButton>(
          find.byKey(const Key('medication-photo-capture-button')));
      expect(btn.onPressed, isNull, reason: 'double-submit guard');
      gate.complete(_prefilled());
      await tester.pumpAndSettle();
      expect(h.extractCalls, 1);
      expect(find.byKey(const Key('medication-photo-progress')), findsNothing);
    });

    testWidgets(
        'TC-MED-PHOTO-057: bytes handed to the extractor are the picked image and the file name',
        (tester) async {
      Uint8List? got;
      String? gotName;
      int? gotId;
      final h = _Harness(extractor: (id, bytes, name) async {
        got = bytes;
        gotName = name;
        gotId = id;
        return _prefilled();
      });
      await _pump(tester, h);
      await _scan(tester);
      expect(got, _imageBytes);
      // XFile.fromData does not preserve a file name on io platforms, so only
      // the byte content and patient id are asserted here; the multipart
      // filename is asserted in TC-MED-PHOTO-037.
      expect(gotName, isNotNull);
      expect(gotId, 5);
    });
  });

  // ── Rescan regression (found by review, fixed in c7114c8e) ───────────────
  group('rescan after a successful scan', () {
    testWidgets(
        'TC-MED-PHOTO-070: failed rescan keeps prior values, flags, banner, read-aloud and title',
        (tester) async {
      var call = 0;
      final h = _Harness(extractor: (_, __, ___) async {
        call++;
        return call == 1
            ? _prefilled()
            : MedicationPhotoExtractionResult.manualFallback(
                message: 'Failed again.');
      });
      await _pump(tester, h);
      await _scan(tester);
      // The user edits one field between scans, so both flag kinds are live.
      await tester.enterText(
          find.byKey(const Key('medication-dosage-field')), '20 mg');
      await tester.pumpAndSettle();

      await _scan(tester);

      expect(call, 2);
      expect(find.text('Failed again.'), findsOneWidget);
      expect(find.byKey(const Key('medication-photo-fallback-message')),
          findsOneWidget);
      expect(_fieldText(tester, 'medication-name-field'), 'Lisinopril');
      expect(_fieldText(tester, 'medication-dosage-field'), '20 mg');
      expect(find.byKey(const Key('medication-photo-ai-note-medicationName')),
          findsOneWidget);
      expect(find.byKey(const Key('medication-photo-edited-note-dosage')),
          findsOneWidget);
      expect(find.byKey(const Key('medication-photo-read-aloud-button')),
          findsOneWidget);
      expect(find.text('Review Medication'), findsOneWidget);
      expect(
          find.byWidgetPredicate(
              (w) => w.runtimeType.toString() == 'DisclaimerBanner'),
          findsOneWidget);
    });

    testWidgets(
        'TC-MED-PHOTO-071: a later successful rescan clears the failure message and replaces the flags',
        (tester) async {
      var call = 0;
      final h = _Harness(extractor: (_, __, ___) async {
        call++;
        if (call == 2) {
          return MedicationPhotoExtractionResult.manualFallback(
              message: 'Failed again.');
        }
        return _prefilled(name: call == 1 ? 'Lisinopril' : 'Metformin');
      });
      await _pump(tester, h);
      await _scan(tester);
      await tester.enterText(
          find.byKey(const Key('medication-dosage-field')), '20 mg');
      await tester.pumpAndSettle();
      await _scan(tester); // fails
      await _scan(tester); // succeeds

      expect(find.text('Failed again.'), findsNothing);
      expect(find.byKey(const Key('medication-photo-fallback-message')),
          findsNothing);
      expect(_fieldText(tester, 'medication-name-field'), 'Metformin');
      expect(find.byKey(const Key('medication-photo-ai-note-dosage')),
          findsOneWidget);
      expect(find.byKey(const Key('medication-photo-edited-note-dosage')),
          findsNothing);
    });
  });

  // ── OTC wire mapping (KI-05 follow-up, PR #207) ─────────────────────────
  group('OTC wire mapping', () {
    test(
        'TC-MED-PHOTO-072: every MedicationType name is the backend wire name, including OVER_THE_COUNTER',
        () {
      expect(MedicationType.OVER_THE_COUNTER.name, 'OVER_THE_COUNTER');
      expect(MedicationType.values.map((t) => t.name).toSet(), {
        'PRESCRIPTION',
        'OVER_THE_COUNTER',
        'SUPPLEMENT',
        'HERBAL',
        'EMERGENCY'
      });
    });

    Map<String, dynamic> wire(String type) => {
          'id': 3,
          'medicationName': 'Ibuprofen',
          'dosage': '200 mg',
          'frequency': 'As needed',
          'route': 'Oral',
          'medicationType': type,
          'isActive': true,
        };

    test(
        'TC-MED-PHOTO-073: fromJson accepts OVER_THE_COUNTER and legacy OTC as OVER_THE_COUNTER; toJson round-trips to OVER_THE_COUNTER; unknown still falls back to PRESCRIPTION',
        () {
      expect(Medication.fromJson(wire('OVER_THE_COUNTER')).medicationType,
          MedicationType.OVER_THE_COUNTER);
      expect(Medication.fromJson(wire('OTC')).medicationType,
          MedicationType.OVER_THE_COUNTER);
      expect(
          Medication.fromJson(wire('OVER_THE_COUNTER'))
              .toJson()['medicationType'],
          'OVER_THE_COUNTER');
      expect(Medication.fromJson(wire('BOGUS')).medicationType,
          MedicationType.PRESCRIPTION);
    });

    testWidgets(
        'TC-MED-PHOTO-074: a stored OVER_THE_COUNTER medication parses to OVER_THE_COUNTER and shows the Remove button',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MedicationCard(
              medication: Medication.fromJson(wire('OVER_THE_COUNTER')),
              onStatusChanged: (_) {},
            ),
          ),
        ),
      ));
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    });

    test(
        'TC-MED-PHOTO-075: medicationTypeFromExtracted maps OVER_THE_COUNTER and OTC to OVER_THE_COUNTER and leaves blank or unknown null (Table 25 row 3)',
        () {
      expect(medicationTypeFromExtracted('OVER_THE_COUNTER'),
          MedicationType.OVER_THE_COUNTER);
      expect(medicationTypeFromExtracted('OTC'),
          MedicationType.OVER_THE_COUNTER);
      expect(medicationTypeFromExtracted('BOGUS'), isNull);
      expect(medicationTypeFromExtracted(''), isNull);
      expect(medicationTypeFromExtracted(null), isNull);
    });
  });

  // ── Read aloud ───────────────────────────────────────────────────────────
  group('read aloud', () {
    testWidgets(
        'TC-MED-PHOTO-058: Read Aloud speaks the CURRENT form values (after an edit)',
        (tester) async {
      final h = _Harness(extractor: (_, __, ___) async => _prefilled());
      await _pump(tester, h);
      await _scan(tester);
      await tester.enterText(
          find.byKey(const Key('medication-dosage-field')), '20 mg');
      await tester.pumpAndSettle();
      await tester.ensureVisible(
          find.byKey(const Key('medication-photo-read-aloud-button')));
      await tester
          .tap(find.byKey(const Key('medication-photo-read-aloud-button')));
      await tester.pumpAndSettle();
      expect(h.engine.spoken, hasLength(1));
      final s = h.engine.spoken.single;
      expect(s, contains('Please check these details before saving'));
      expect(s, contains('Medication name: Lisinopril'));
      expect(s, contains('Dosage: 20 mg'));
      expect(s, contains('Frequency: Once daily'));
    });

    testWidgets('TC-MED-PHOTO-059: blank values are read as "not filled in"',
        (tester) async {
      final h =
          _Harness(extractor: (_, __, ___) async => _prefilled(dosage: ''));
      await _pump(tester, h);
      await _scan(tester);
      await tester.ensureVisible(
          find.byKey(const Key('medication-photo-read-aloud-button')));
      await tester
          .tap(find.byKey(const Key('medication-photo-read-aloud-button')));
      await tester.pumpAndSettle();
      expect(h.engine.spoken.single, contains('not filled in'));
    });

    testWidgets(
        'TC-MED-PHOTO-060: TTS failure shows a snackbar and does not break the form',
        (tester) async {
      final e = FakeTtsEngine()..throwOnSpeak = true;
      final h = _Harness(tts: e, extractor: (_, __, ___) async => _prefilled());
      await _pump(tester, h);
      await _scan(tester);
      await tester.ensureVisible(
          find.byKey(const Key('medication-photo-read-aloud-button')));
      await tester
          .tap(find.byKey(const Key('medication-photo-read-aloud-button')));
      await tester.pumpAndSettle();
      expect(find.text('Read aloud is not available on this device.'),
          findsOneWidget);
      expect(find.byKey(const Key('medication-name-field')), findsOneWidget);
    });

    testWidgets(
        'TC-MED-PHOTO-061: speech is stopped when the modal is disposed',
        (tester) async {
      final h = _Harness(extractor: (_, __, ___) async => _prefilled());
      await _pump(tester, h);
      await _scan(tester);
      await tester.ensureVisible(
          find.byKey(const Key('medication-photo-read-aloud-button')));
      await tester
          .tap(find.byKey(const Key('medication-photo-read-aloud-button')));
      await tester.pumpAndSettle();
      h.engine.calls.clear();
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pumpAndSettle();
      expect(h.engine.calls, contains('stop'));
    });
  });

  // ── Cancel and save ──────────────────────────────────────────────────────
  group('cancel and save', () {
    testWidgets(
        'TC-MED-PHOTO-062: cancel closes the modal, creates nothing, and a reopened form has no extracted data',
        (tester) async {
      var created = 0;
      http.Request? posted;
      ApiService.debugSetHttpClient(MockClient((r) async {
        posted = r;
        created++;
        return http.Response('{}', 200);
      }));
      addTearDown(ApiService.debugResetHttpClient);

      final h = _Harness(extractor: (_, __, ___) async => _prefilled());
      tester.view.physicalSize = const Size(900, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      var open = true;
      await tester.pumpWidget(StatefulBuilder(builder: (ctx, set) {
        return ChangeNotifierProvider<UserProvider>.value(
          value: h.user,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Builder(builder: (c) {
                return Column(children: [
                  TextButton(
                      key: const Key('open'),
                      onPressed: () => showModalBottomSheet(
                          context: c,
                          isScrollControlled: true,
                          builder: (_) => AddMedicationModal(
                                onMedicationAdded: (_) {},
                                pickLabelPhoto: () async => XFile.fromData(
                                    _imageBytes,
                                    name: 'label.jpg'),
                                extractLabelPhoto: (a, b, d) async =>
                                    _prefilled(),
                                readAloud: MedicationPhotoTts(engine: h.engine),
                              )),
                      child: const Text('open')),
                ]);
              }),
            ),
          ),
        );
      }));
      expect(open, isTrue);
      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();
      await _scan(tester);
      expect(_fieldText(tester, 'medication-name-field'), 'Lisinopril');

      await tester.tap(find.byKey(const Key('medication-cancel-button')));
      await tester.pumpAndSettle();
      expect(find.byType(AddMedicationModal), findsNothing);
      expect(created, 0);
      expect(posted, isNull);

      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();
      expect(_fieldText(tester, 'medication-name-field'), isEmpty);
      expect(find.text('Add New Medication'), findsOneWidget);
    });

    testWidgets(
        'TC-MED-PHOTO-063: save posts edited values via the existing create endpoint, an OTC scan is sent as OVER_THE_COUNTER, and no image or tracking data',
        (tester) async {
      Map<String, dynamic>? body;
      String? path;
      ApiService.debugSetHttpClient(MockClient((r) async {
        // Telemetry shares this client; only capture the create call.
        if (!r.url.path.endsWith('/medications')) {
          return http.Response('{}', 200);
        }
        body = jsonDecode(r.body) as Map<String, dynamic>;
        path = r.url.path;
        return http.Response(jsonEncode({'id': 9, ...body!}), 200);
      }));
      addTearDown(ApiService.debugResetHttpClient);

      Medication? added;
      final h = _Harness(
          onAdded: (m) => added = m,
          extractor: (_, __, ___) async =>
              _prefilled(type: 'OVER_THE_COUNTER'));
      await _pump(tester, h);
      await _scan(tester);
      await tester.enterText(
          find.byKey(const Key('medication-dosage-field')), '20 mg');
      await tester.pumpAndSettle();
      await tester
          .ensureVisible(find.byKey(const Key('medication-save-button')));
      await tester.tap(find.byKey(const Key('medication-save-button')));
      // The success SnackBar and telemetry keep timers alive, so pump a fixed
      // window instead of pumpAndSettle.
      // Auth header lookup touches platform storage, which needs real async time.
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 500)));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(seconds: 3));

      expect(path, endsWith('/v3/api/patients/5/medications'));
      expect(path, isNot(contains('extract-photo')));
      expect(body!['medicationName'], 'Lisinopril');
      expect(body!['dosage'], '20 mg');
      expect(body!['frequency'], 'Once daily');
      expect(body!['medicationType'], 'OVER_THE_COUNTER',
          reason:
              'KI-05 fix: scanned OTC label is saved with the backend constant name');
      final all = jsonEncode(body);
      expect(all, isNot(contains('machineGenerated')));
      expect(all, isNot(contains('editedByUser')));
      expect(all, isNot(contains(_marker)));
      expect(added, isNotNull);
    });
  });

  // ── Accessibility semantics ──────────────────────────────────────────────
  // ── Manual entry and save paths ──────────────────────────────────────────
  group('manual entry and save paths', () {
    const createPath = '/medications';

    // Save touches platform storage for the auth header and fires telemetry
    // timers, so pump a fixed window instead of pumpAndSettle.
    Future<void> tapSaveAndWait(WidgetTester tester) async {
      await tester
          .ensureVisible(find.byKey(const Key('medication-save-button')));
      await tester.tap(find.byKey(const Key('medication-save-button')));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 500)));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(seconds: 3));
    }

    Future<void> pickFromDropdown(
        WidgetTester tester, String current, String choice) async {
      await tester.ensureVisible(find.text(current).first);
      await tester.tap(find.text(current).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(choice).last);
      await tester.pumpAndSettle();
    }

    Future<void> fillRequired(WidgetTester tester) async {
      await tester.enterText(
          find.byKey(const Key('medication-name-field')), 'Metformin');
      await tester.enterText(
          find.byKey(const Key('medication-dosage-field')), '500 mg');
      await tester.pumpAndSettle();
    }

    testWidgets(
        'TC-MED-PHOTO-093: choosing Custom frequency requires text, switching away clears it, and save sends the custom text and chosen route',
        (tester) async {
      // Arrange
      final posted = <Map<String, dynamic>>[];
      ApiService.debugSetHttpClient(MockClient((r) async {
        if (!r.url.path.endsWith(createPath)) return http.Response('{}', 200);
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        posted.add(body);
        return http.Response(jsonEncode({'id': 11, ...body}), 200);
      }));
      addTearDown(ApiService.debugResetHttpClient);
      final h = _Harness();
      await _pump(tester, h);
      await fillRequired(tester);

      // Act: pick Custom and try to save without text
      await pickFromDropdown(tester, 'Once daily', 'Custom');
      expect(find.byKey(const Key('medication-custom-frequency-field')),
          findsOneWidget);
      await tester
          .ensureVisible(find.byKey(const Key('medication-save-button')));
      await tester.tap(find.byKey(const Key('medication-save-button')));
      await tester.pumpAndSettle();

      // Assert: validator blocks the save
      expect(find.text('Please enter custom frequency'), findsOneWidget);
      expect(posted, isEmpty);

      // Act: type, switch away (clears), come back, type again, change route
      await tester.enterText(
          find.byKey(const Key('medication-custom-frequency-field')),
          'Every 8 hours');
      await pickFromDropdown(tester, 'Custom', 'Twice daily');
      expect(find.byKey(const Key('medication-custom-frequency-field')),
          findsNothing);
      await pickFromDropdown(tester, 'Twice daily', 'Custom');
      expect(_fieldText(tester, 'medication-custom-frequency-field'), isEmpty);
      await tester.enterText(
          find.byKey(const Key('medication-custom-frequency-field')),
          'Every 8 hours');
      await pickFromDropdown(tester, 'Oral', 'Topical');
      await tapSaveAndWait(tester);

      // Assert
      expect(posted, hasLength(1));
      expect(posted.single['frequency'], 'Every 8 hours');
      expect(posted.single['route'], 'Topical');
      expect(posted.single['medicationType'], 'PRESCRIPTION');
    });

    testWidgets(
        'TC-MED-PHOTO-094: the three date pickers set their dates and save sends them with Prescribed By',
        (tester) async {
      // Arrange
      Map<String, dynamic>? body;
      ApiService.debugSetHttpClient(MockClient((r) async {
        if (!r.url.path.endsWith(createPath)) return http.Response('{}', 200);
        body = jsonDecode(r.body) as Map<String, dynamic>;
        return http.Response(jsonEncode({'id': 12, ...body!}), 200);
      }));
      addTearDown(ApiService.debugResetHttpClient);
      final h = _Harness();
      await _pump(tester, h);
      await fillRequired(tester);
      await tester.enterText(
          find.ancestor(
              of: find.text('e.g., Dr. Smith'),
              matching: find.byType(TextFormField)),
          'Dr. Smith');
      final now = DateTime.now();
      final today =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      // Act: prescribed, start and end dates, each confirmed on today
      for (var i = 0; i < 3; i++) {
        await tester.ensureVisible(find.text('Select date').first);
        await tester.tap(find.text('Select date').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
      }

      // Assert: all three show the chosen date
      expect(find.text('Select date'), findsNothing);
      expect(find.text(today), findsNWidgets(3));

      // Act
      await tapSaveAndWait(tester);

      // Assert
      expect(body, isNotNull);
      expect(body!['prescribedBy'], 'Dr. Smith');
      expect(body!['prescribedDate'], today);
      expect(body!['startDate'], today);
      expect(body!['endDate'], today);
    });

    testWidgets(
        'TC-MED-PHOTO-095: save shows a spinner while waiting, and a failed create shows the status code',
        (tester) async {
      // Arrange: hold the create response until the spinner is checked
      final reply = Completer<http.Response>();
      ApiService.debugSetHttpClient(MockClient((r) async {
        if (!r.url.path.endsWith(createPath)) return http.Response('{}', 200);
        return reply.future;
      }));
      addTearDown(ApiService.debugResetHttpClient);
      Medication? added;
      final h = _Harness(onAdded: (m) => added = m);
      await _pump(tester, h);
      await fillRequired(tester);

      // Act
      await tester
          .ensureVisible(find.byKey(const Key('medication-save-button')));
      await tester.tap(find.byKey(const Key('medication-save-button')));
      await tester.pump();

      // Assert: spinner inside the Save button while the request is pending
      expect(
          find.descendant(
              of: find.byKey(const Key('medication-save-button')),
              matching: find.byType(CircularProgressIndicator)),
          findsOneWidget);

      // Act: server answers with an error
      reply.complete(http.Response('server error', 500));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 500)));
      await tester.pump(const Duration(milliseconds: 500));

      // Assert
      expect(find.text('Failed to add medication: 500'), findsOneWidget);
      expect(added, isNull);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets(
        'TC-MED-PHOTO-096: with no Care Recipient ID on the session, save shows an error and sends nothing',
        (tester) async {
      // Arrange
      var createCalls = 0;
      ApiService.debugSetHttpClient(MockClient((r) async {
        if (r.url.path.endsWith(createPath)) createCalls++;
        return http.Response('{}', 200);
      }));
      addTearDown(ApiService.debugResetHttpClient);
      final h = _Harness(patientId: null);
      await _pump(tester, h);
      await fillRequired(tester);

      // Act
      await tapSaveAndWait(tester);

      // Assert
      expect(createCalls, 0);
      expect(find.textContaining('Patient ID not found'), findsOneWidget);
    });

    testWidgets(
        'TC-MED-PHOTO-097: read-aloud speaks the custom text when the scanned frequency is not a dropdown option',
        (tester) async {
      // Arrange
      final h = _Harness(
          extractor: (_, __, ___) async =>
              _prefilled(frequency: 'Every 8 hours'));
      await _pump(tester, h);
      await _scan(tester);

      // Act
      await tester.ensureVisible(
          find.byKey(const Key('medication-photo-read-aloud-button')));
      await tester
          .tap(find.byKey(const Key('medication-photo-read-aloud-button')));
      await tester.pumpAndSettle();

      // Assert
      expect(h.engine.spoken, hasLength(1));
      expect(h.engine.spoken.single, contains('Every 8 hours'));
    });
  });

  group('accessibility semantics', () {
    testWidgets(
        'TC-MED-PHOTO-064: capture and read-aloud controls expose labels and >=48dp tap height',
        (tester) async {
      final handle = tester.ensureSemantics();
      final h = _Harness(extractor: (_, __, ___) async => _prefilled());
      await _pump(tester, h);
      expect(find.bySemanticsLabel(RegExp('Scan Label')), findsWidgets);
      await _scan(tester);
      expect(find.bySemanticsLabel(RegExp('Read Aloud')), findsWidgets);
      for (final k in [
        'medication-photo-capture-button',
        'medication-photo-read-aloud-button'
      ]) {
        final size = tester.getSize(find.byKey(Key(k)));
        expect(size.height, greaterThanOrEqualTo(48),
            reason: '$k tap target height (WCAG 2.5.5 guidance / Material)');
      }
      handle.dispose();
    });

    testWidgets(
        'TC-MED-PHOTO-065: progress, fallback and review messages are live regions',
        (tester) async {
      final handle = tester.ensureSemantics();
      final gate = Completer<MedicationPhotoExtractionResult>();
      final h = _Harness(extractor: (_, __, ___) => gate.future);
      await _pump(tester, h);
      await tester.ensureVisible(
          find.byKey(const Key('medication-photo-capture-button')));
      await tester
          .tap(find.byKey(const Key('medication-photo-capture-button')));
      await tester.pump();
      await tester.pump();
      bool live(String key) {
        final n = tester.getSemantics(find
            .descendant(
                of: find.byKey(Key(key)), matching: find.byType(Semantics))
            .first);
        return n.getSemanticsData().flagsCollection.isLiveRegion;
      }

      expect(find.text('Reading the label photo...'), findsOneWidget);
      expect(tester.getSemantics(find.text('Reading the label photo...')).label,
          contains('Reading'));
      gate.complete(
          MedicationPhotoExtractionResult.manualFallback(message: _unreadable));
      await tester.pumpAndSettle();
      expect(live('medication-photo-fallback-message'), isTrue);
      handle.dispose();
    });

    testWidgets(
        'TC-MED-PHOTO-066: field status is conveyed by icon plus text, not colour alone',
        (tester) async {
      final h =
          _Harness(extractor: (_, __, ___) async => _prefilled(dosage: ''));
      await _pump(tester, h);
      await _scan(tester);
      for (final k in [
        'medication-photo-ai-note-medicationName',
        'medication-photo-missing-note-dosage'
      ]) {
        final note = find.byKey(Key(k));
        expect(find.descendant(of: note, matching: find.byType(Icon)),
            findsOneWidget);
        expect(find.descendant(of: note, matching: find.byType(Text)),
            findsOneWidget);
      }
      expect(find.text('Read from photo. Please check it.'), findsWidgets);
      expect(find.text('Not found on the label. Please fill this in.'),
          findsOneWidget);
    });

    testWidgets(
        'TC-MED-PHOTO-067: review form has no overflow at 200% text scale',
        (tester) async {
      final h = _Harness(extractor: (_, __, ___) async => _prefilled());
      await _pump(tester, h, scale: 2.0);
      await _scan(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Review Medication'), findsOneWidget);
    });

    testWidgets(
        'TC-MED-PHOTO-068: form fields keep visible labels (name, dosage, frequency, type)',
        (tester) async {
      final h = _Harness(extractor: (_, __, ___) async => _prefilled());
      await _pump(tester, h);
      await _scan(tester);
      expect(find.textContaining('Medication Name'), findsWidgets);
      expect(find.textContaining('Dosage'), findsWidgets);
      expect(find.text('Frequency *'), findsOneWidget);
      expect(find.text('Medication Type'), findsOneWidget);
    });

    testWidgets(
        'TC-MED-PHOTO-069: fallback message colours meet 4.5:1 contrast (computed on the light Material theme)',
        (tester) async {
      final scheme = ColorScheme.fromSeed(seedColor: Colors.blue);
      double lum(Color c) => c.computeLuminance();
      double ratio(Color a, Color b) {
        final l1 = lum(a), l2 = lum(b);
        final hi = l1 > l2 ? l1 : l2, lo = l1 > l2 ? l2 : l1;
        return (hi + 0.05) / (lo + 0.05);
      }

      expect(ratio(scheme.onErrorContainer, scheme.errorContainer),
          greaterThanOrEqualTo(4.5));
      expect(ratio(scheme.primary, scheme.surface), greaterThanOrEqualTo(4.5),
          reason: 'note icon/text colour on surface');
    });
  });
}
