// Unit tests for PatientMedicationReminderService
// (lib/features/dashboard/patient_dashboard/services/patient_medication_reminder_service.dart).

import 'dart:convert';

import 'package:care_connect_app/features/dashboard/patient_dashboard/services/patient_medication_reminder_service.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

late http.Response Function() _response;
final _client = MockClient((_) async => _response());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final t = lookupAppLocalizations(const Locale('en'));

  setUpAll(() => ApiService.debugSetHttpClient(_client));

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => call.method == 'readAll' ? <String, String>{} : null,
    );
  });

  void respondWith(List<dynamic> rows) =>
      _response = () => http.Response(jsonEncode(rows), 200);

  test('returns empty list without patient id', () async {
    final service = PatientMedicationReminderService();
    expect(await service.loadReminders(patientId: null, t: t), isEmpty);
  });

  test('returns empty list for non-200 and non-list bodies', () async {
    final service = PatientMedicationReminderService();
    _response = () => http.Response('[]', 500);
    expect(await service.loadReminders(patientId: 1, t: t), isEmpty);
    _response = () => http.Response('{"a":1}', 200);
    expect(await service.loadReminders(patientId: 1, t: t), isEmpty);
  });

  test('parses ids, skips inactive or unnamed rows and sorts taken last',
      () async {
    final now = DateTime.now();
    respondWith([
      'not-a-map',
      {'id': 1, 'medicationName': 'Inactive', 'isActive': false},
      {'id': 2, 'medicationName': '  '},
      {
        'id': 3.0,
        'medicationName': 'Weekly Pill',
        'frequency': 'Once a week',
        'lastTaken': now.toUtc().toIso8601String(),
      },
      {
        'id': '4',
        'medicationName': 'Monthly Shot',
        'frequency': 'Monthly',
        'startDate': now.add(const Duration(days: 3)).toIso8601String(),
      },
      {
        'medicationName': 'No Id Every 6 Hours',
        'frequency': 'Every 6 hours',
        'lastTaken': '   ',
      },
      {'id': 'bad', 'medicationName': 'Bad Id', 'frequency': 'Three times'},
      {'id': 7, 'medicationName': 'Twice', 'frequency': 'twice daily'},
      {'id': 8, 'medicationName': 'Plain', 'frequency': 'whenever'},
      {'id': 9, 'medicationName': 'Daily', 'frequency': 'daily'},
      {'id': 10, 'medicationName': 'Hourly', 'frequency': 'every hour'},
    ]);

    final service = PatientMedicationReminderService();
    final reminders = await service.loadReminders(patientId: 1, t: t);
    final names = reminders.map((r) => r.medicationName).toList();

    expect(names, isNot(contains('Inactive')));
    expect(names.length, 8);
    // Taken (weekly, taken just now) sorts last.
    expect(reminders.last.medicationName, 'Weekly Pill');
    expect(reminders.last.isTakenForCurrentWindow, isTrue);
    expect(reminders.last.medicationId, 3);
    // Synthetic negative ids for rows without a parsable id.
    expect(
      reminders.where((r) => r.medicationId < 0).map((r) => r.medicationName),
      containsAll(['No Id Every 6 Hours', 'Bad Id']),
    );
    expect(reminders.firstWhere((r) => r.medicationId == 4).dosage,
        t.ptmedreminderservice_doseNotSet);
    expect(service.hasPendingUntaken(reminders), isTrue);
  });

  test('local overrides apply until the server catches up', () async {
    final service = PatientMedicationReminderService();
    final takenAt = DateTime.now().toUtc();

    // Local "taken" override while server has no lastTaken.
    respondWith([
      {'id': 5, 'medicationName': 'Med', 'frequency': 'daily'},
    ]);
    service.markTaken(medicationId: 5, takenAt: takenAt);
    var items = await service.loadReminders(patientId: 1, t: t);
    expect(items.single.isTakenForCurrentWindow, isTrue);

    // Server catches up with an equal timestamp, override is dropped.
    respondWith([
      {
        'id': 5,
        'medicationName': 'Med',
        'frequency': 'daily',
        'lastTaken': takenAt.toIso8601String(),
      },
    ]);
    items = await service.loadReminders(patientId: 1, t: t);
    expect(items.single.isTakenForCurrentWindow, isTrue);

    // A "missed" override with no server value is cleared.
    respondWith([
      {'id': 5, 'medicationName': 'Med', 'frequency': 'daily'},
    ]);
    service.markMissed(medicationId: 5);
    items = await service.loadReminders(patientId: 1, t: t);
    expect(items.single.isTakenForCurrentWindow, isFalse);

    // Newer local override than server keeps the override.
    respondWith([
      {
        'id': 5,
        'medicationName': 'Med',
        'frequency': 'daily',
        'lastTaken': takenAt
            .subtract(const Duration(days: 3))
            .toIso8601String(),
      },
    ]);
    service.markTaken(medicationId: 5);
    items = await service.loadReminders(patientId: 1, t: t);
    expect(items.single.isTakenForCurrentWindow, isTrue);

    service.clearLocalOverride(medicationId: 5);
    items = await service.loadReminders(patientId: 1, t: t);
    expect(items.single.isTakenForCurrentWindow, isFalse);
  });
}
