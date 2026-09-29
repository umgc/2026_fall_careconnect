// KI-05 cases for the frontend MedicationType (Test Plan section 3.9).
//
// TC-MED-TYPE-001..004 are PR #153's author's, in
// medication_tracker/models/medication_model_test.dart and
// health/models/medication_model_test.dart. The rest live here:
//   005..013       Testing Lead, PR #153 (HERBAL and EMERGENCY added)
//   014..017       PR #207's author (OTC renamed to OVER_THE_COUNTER)
//   018, 020, 021  Testing Lead, PR #207; 019 is the backend case in
//                  MedicationTypeWireContractTest.java
//   022            inherited case in medication_tracker_test.dart (an inactive
//                  OVER_THE_COUNTER medication has no delete control)
//
// Between them they cover the wire round-trip, the payload the add form
// actually posts, the add-medication dropdown (which renders
// MedicationType.values), the MedicationCard remove rule (which keys off
// MedicationType.PRESCRIPTION), the caregiver card, and parity with the
// backend enum.

import 'dart:convert';
import 'dart:io';

import 'package:care_connect_app/features/health/caregiver-patient-list/widgets/current_medications_card.dart';
import 'package:care_connect_app/features/health/medication-tracker/models/medication-model.dart';
import 'package:care_connect_app/features/health/medication-tracker/widgets/medication-add-input-form.dart';
import 'package:care_connect_app/features/health/medication-tracker/widgets/medication-card.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../mock_user_provider.dart';

const _backendEnumPath =
    '../backend/core/src/main/java/com/careconnect/model/Medication.java';

Map<String, dynamic> _wire(String type) => {
      'id': 7,
      'medicationName': 'Synthetic Med',
      'dosage': '1 unit',
      'frequency': 'As needed',
      'route': 'Oral',
      'medicationType': type,
      'isActive': true,
    };

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

Set<String> _backendConstants() {
  final src = File(_backendEnumPath).readAsStringSync();
  final body = RegExp(r'enum MedicationType\s*\{([^;]*);').firstMatch(src)!;
  return RegExp(r'([A-Z_]+)\s*\(')
      .allMatches(body.group(1)!)
      .map((m) => m.group(1)!)
      .toSet();
}

void main() {
  group('KI-05 wire round-trip', () {
    for (final type in ['HERBAL', 'EMERGENCY']) {
      test('TC-MED-TYPE-005/006: $type survives fromJson -> toJson unchanged',
          () {
        final m = Medication.fromJson(_wire(type));
        expect(m.toJson()['medicationType'], type);
      });
    }
  });

  group('KI-05 backend parity', () {
    final backendPresent = File(_backendEnumPath).existsSync();

    test(
        'TC-MED-TYPE-007: the frontend MedicationType names and the backend '
        'Medication.MedicationType constants are the same set', () {
      final backend = _backendConstants();
      final frontend = MedicationType.values.map((e) => e.name).toSet();
      // Updated by the KI-05 follow-up (OTC renamed to OVER_THE_COUNTER):
      // both differences are now empty, as this case required.
      expect(frontend.difference(backend), isEmpty);
      expect(backend.difference(frontend), isEmpty);
    }, skip: backendPresent ? false : 'backend tree not present');
  });

  group('KI-05 follow-up: OVER_THE_COUNTER wire name', () {
    test(
        'TC-MED-TYPE-014: a complete backend OVER_THE_COUNTER row parses with '
        'every field intact and the type as OVER_THE_COUNTER, not PRESCRIPTION',
        () {
      // One value for every MedicationDTO field. lastTaken is sent by the
      // backend but not modelled on the frontend.
      final m = Medication.fromJson({
        'id': 7,
        'patientId': 10,
        'medicationName': 'Synthetic Med',
        'dosage': '200mg',
        'frequency': 'As needed',
        'route': 'Oral',
        'medicationType': 'OVER_THE_COUNTER',
        'prescribedBy': 'Dr. Synthetic',
        'prescribedDate': '2026-01-01',
        'startDate': '2026-01-05',
        'endDate': '2026-12-31',
        'notes': 'Synthetic note',
        'isActive': true,
        'lastTaken': '2026-09-28T08:00:00Z',
      });
      expect(m.id, 7);
      expect(m.patientId, 10);
      expect(m.medicationName, 'Synthetic Med');
      expect(m.dosage, '200mg');
      expect(m.frequency, 'As needed');
      expect(m.route, 'Oral');
      expect(m.medicationType, MedicationType.OVER_THE_COUNTER);
      expect(m.prescribedBy, 'Dr. Synthetic');
      expect(m.prescribedDate, '2026-01-01');
      expect(m.startDate, '2026-01-05');
      expect(m.endDate, '2026-12-31');
      expect(m.notes, 'Synthetic note');
      expect(m.isActive, isTrue);
    });

    test(
        'TC-MED-TYPE-015: OVER_THE_COUNTER survives fromJson -> toJson '
        'unchanged, so saving an OTC medication sends a name the backend accepts',
        () {
      final m = Medication.fromJson(_wire('OVER_THE_COUNTER'));
      expect(m.toJson()['medicationType'], 'OVER_THE_COUNTER');
    });

    test(
        'TC-MED-TYPE-016: a legacy OTC value still reads as OVER_THE_COUNTER '
        'and is written back with the backend name', () {
      final m = Medication.fromJson(_wire('OTC'));
      expect(m.medicationType, MedicationType.OVER_THE_COUNTER);
      expect(m.toJson()['medicationType'], 'OVER_THE_COUNTER');
    });

    testWidgets(
        'TC-MED-TYPE-017: an active OVER_THE_COUNTER row from the backend '
        'shows the remove button (it no longer falls back to PRESCRIPTION)',
        (tester) async {
      await tester.pumpWidget(_wrap(MedicationCard(
        medication: Medication.fromJson(_wire('OVER_THE_COUNTER')),
        onStatusChanged: (_) {},
      )));
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    });
  });

  group('KI-05 follow-up: the add form posts the backend wire name', () {
    const secureStorage =
        MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

    setUp(() {
      // Telemetry opted out so the only POST the mock sees is the medication.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'telemetry_opted_out': true,
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(secureStorage, (call) async => null);
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(secureStorage, null);
      ApiService.debugResetHttpClient();
    });

    testWidgets(
        'TC-MED-TYPE-018: choosing OVER_THE_COUNTER in the add form posts '
        '"OVER_THE_COUNTER", never "OTC" (DEF-MED-01 at the failing path)',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final posted = <Map<String, dynamic>>[];
      final mock = MockClient((req) async {
        if (req.method == 'POST' && req.url.path.endsWith('/medications')) {
          posted.add(jsonDecode(req.body) as Map<String, dynamic>);
          return http.Response(
            jsonEncode(_wire('OVER_THE_COUNTER')),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('', 204);
      });
      ApiService.debugSetHttpClient(mock);

      await http.runWithClient(() async {
        await tester.pumpWidget(ChangeNotifierProvider<UserProvider>.value(
          value: MockUserProvider(
            mockUser: MockUser(id: 1, role: 'PATIENT', patientId: 1),
          ),
          child: _wrap(AddMedicationModal(onMedicationAdded: (_) {})),
        ));

        await tester.enterText(find.byType(TextFormField).at(0), 'Synthetic Med');
        await tester.enterText(find.byType(TextFormField).at(1), '1 unit');

        final dropdown = find.byType(DropdownButtonFormField<MedicationType>);
        await tester.ensureVisible(dropdown);
        await tester.tap(dropdown);
        await tester.pumpAndSettle();
        await tester.tap(find.text('OVER_THE_COUNTER').last);
        await tester.pumpAndSettle();

        final submit = find.text('Add Medication');
        await tester.ensureVisible(submit.last);
        await tester.pump();
        await tester.tap(submit.last, warnIfMissed: false);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(seconds: 3));
      }, () => mock);

      expect(posted, hasLength(1));
      expect(posted.single['medicationType'], 'OVER_THE_COUNTER');
      expect(posted.single['medicationType'], isNot('OTC'));
    });
  });

  group('KI-05 follow-up: caregiver card', () {
    testWidgets(
        'TC-MED-TYPE-020: a backend OVER_THE_COUNTER row shows as '
        'OVER_THE_COUNTER, not PRESCRIPTION, on the caregiver card',
        (tester) async {
      await tester.pumpWidget(_wrap(CurrentMedicationsSection(
        entries: [Medication.fromJson(_wire('OVER_THE_COUNTER'))],
      )));
      expect(find.text('OVER_THE_COUNTER'), findsOneWidget);
      expect(find.text('PRESCRIPTION'), findsNothing);
    });
  });

  group('KI-05 follow-up: Medication Type dropdown at 320dp', () {
    // WCAG 2.1 SC 1.4.10 (reflow, 320 CSS px) and 1.4.4 (resize text to
    // 200%). The dropdown renders each type's raw name, and OVER_THE_COUNTER
    // is the longest. Other rows of this form overflow at 320dp too (header,
    // frequency, route and date rows); those are pre-existing and outside
    // KI-05, so only overflows attributed to the Medication Type dropdown are
    // asserted here. Written over MedicationType.values so the same case also
    // runs on the pre-rename base.
    for (final scale in [1.0, 2.0]) {
      testWidgets(
          'TC-MED-TYPE-021: every Medication Type option can be selected at '
          '320x640, text at ${(scale * 100).round()}%, without the dropdown '
          'overflowing', (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1.0;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        final dropdownOverflows = <String>[];
        final original = FlutterError.onError;
        FlutterError.onError = (details) {
          final text = details.toString();
          if (!text.contains('overflowed')) return original?.call(details);
          if (text.contains('DropdownButton<MedicationType>') ||
              text.contains('DropdownButtonFormField<MedicationType>')) {
            dropdownOverflows.add(details.exceptionAsString());
          }
        };
        try {
          await tester.pumpWidget(
              _wrap(AddMedicationModal(onMedicationAdded: (_) {})));
          for (final t in MedicationType.values) {
            final dropdown =
                find.byType(DropdownButtonFormField<MedicationType>);
            await tester.ensureVisible(dropdown);
            await tester.tap(dropdown);
            await tester.pumpAndSettle();
            await tester.tap(find.text(t.name).last);
            await tester.pumpAndSettle();
          }
        } finally {
          FlutterError.onError = original;
        }
        expect(dropdownOverflows, isEmpty);
      });
    }
  });

  group('KI-05 add-medication dropdown', () {
    testWidgets(
        'TC-MED-TYPE-008: dropdown offers all five types and HERBAL can be '
        'selected', (tester) async {
      await tester.pumpWidget(
          _wrap(AddMedicationModal(onMedicationAdded: (_) {})));

      final dropdown = find.byType(DropdownButtonFormField<MedicationType>);
      await tester.ensureVisible(dropdown);
      await tester.tap(dropdown);
      await tester.pumpAndSettle();

      for (final t in MedicationType.values) {
        expect(find.text(t.name), findsWidgets, reason: '${t.name} missing');
      }

      await tester.tap(find.text('HERBAL').last);
      await tester.pumpAndSettle();

      final field = tester.widget<DropdownButton<MedicationType>>(
          find.byType(DropdownButton<MedicationType>));
      expect(field.value, MedicationType.HERBAL);
    });
  });

  group('KI-05 MedicationCard remove rule', () {
    // Before this PR, a backend HERBAL/EMERGENCY row fell back to
    // PRESCRIPTION in fromJson and the card hid the remove button. After it,
    // both parse to their own value and the remove button appears, because
    // the card protects only PRESCRIPTION. These cases pin the new behavior.
    for (final type in ['HERBAL', 'EMERGENCY']) {
      testWidgets(
          'TC-MED-TYPE-009/010: active $type row from the backend shows the '
          'remove button', (tester) async {
        await tester.pumpWidget(_wrap(MedicationCard(
          medication: Medication.fromJson(_wire(type)),
          onStatusChanged: (_) {},
        )));
        expect(find.byIcon(Icons.delete_outline), findsOneWidget);
      });
    }
  });
}
