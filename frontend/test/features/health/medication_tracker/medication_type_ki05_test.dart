// Testing Lead cases for PR #153 (KI-05: HERBAL and EMERGENCY added to the
// frontend MedicationType). The author's cases are TC-MED-TYPE-001..004 in
// models/medication_model_test.dart and medication_tracker/medication_model_test.dart.
//
// These cover what the PR changes but does not test: the wire round-trip,
// the add-medication dropdown (which renders MedicationType.values), the
// MedicationCard remove rule (which keys off MedicationType.PRESCRIPTION),
// and parity with the backend enum.

import 'dart:io';

import 'package:care_connect_app/features/health/medication-tracker/models/medication-model.dart';
import 'package:care_connect_app/features/health/medication-tracker/widgets/medication-add-input-form.dart';
import 'package:care_connect_app/features/health/medication-tracker/widgets/medication-card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
        'TC-MED-TYPE-014: a backend OVER_THE_COUNTER row parses as '
        'OVER_THE_COUNTER, not PRESCRIPTION', () {
      final m = Medication.fromJson(_wire('OVER_THE_COUNTER'));
      expect(m.medicationType, MedicationType.OVER_THE_COUNTER);
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
