import 'package:care_connect_app/features/dashboard/patient_dashboard/models/medication_reminder_item.dart';
import 'package:care_connect_app/features/dashboard/patient_dashboard/services/patient_medication_reminder_service.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

MedicationReminderItem _reminder({
  required int id,
  required DateTime nextDueAt,
  String frequency = 'Once daily',
}) {
  return MedicationReminderItem(
    medicationId: id,
    medicationName: 'Medication $id',
    dosage: '10 mg',
    frequency: frequency,
    nextDueAt: nextDueAt,
    isTakenForCurrentWindow: false,
  );
}

void main() {
  final t = lookupAppLocalizations(const Locale('en'));
  late PatientMedicationReminderService service;

  setUp(() {
    service = PatientMedicationReminderService();
  });

  group('PatientMedicationReminderService.applyLocalOverrides', () {
    test('returns an empty list for empty reminders', () {
      final result = service.applyLocalOverrides(
        reminders: const <MedicationReminderItem>[],
        t: t,
      );

      expect(result, isEmpty);
    });

    test('a missed override remains untaken', () {
      // Arrange
      final reminder = _reminder(
        id: 1,
        nextDueAt: DateTime.now().add(const Duration(hours: 1)),
      );
      service.markMissed(medicationId: reminder.medicationId);

      // Act
      final result = service.applyLocalOverrides(
        reminders: <MedicationReminderItem>[reminder],
        t: t,
      );

      // Assert
      expect(result.single.isTakenForCurrentWindow, isFalse);
    });

    test('every zero hours is clamped and remains taken', () {
      // Arrange
      final takenAt = DateTime.now();
      final reminder = _reminder(
        id: 1,
        nextDueAt: takenAt,
        frequency: 'Every 0 hours',
      );
      service.markTaken(
        medicationId: reminder.medicationId,
        takenAt: takenAt,
      );

      // Act
      final result = service.applyLocalOverrides(
        reminders: <MedicationReminderItem>[reminder],
        t: t,
      );

      // Assert
      expect(result.single.isTakenForCurrentWindow, isTrue);
      expect(
        result.single.nextDueAt.difference(takenAt).inMinutes,
        greaterThanOrEqualTo(59),
      );
    });

    test('sorts pending reminders before taken reminders', () {
      // Arrange
      final now = DateTime.now();
      final laterPending = _reminder(
        id: 1,
        nextDueAt: now.add(const Duration(hours: 2)),
      );
      final earlierPending = _reminder(
        id: 2,
        nextDueAt: now.add(const Duration(hours: 1)),
      );
      final taken = _reminder(
        id: 3,
        nextDueAt: now,
      );
      service.markTaken(medicationId: taken.medicationId, takenAt: now);

      // Act
      final result = service.applyLocalOverrides(
        reminders: <MedicationReminderItem>[
          laterPending,
          taken,
          earlierPending,
        ],
        t: t,
      );

      // Assert
      expect(
        result.map((reminder) => reminder.medicationId),
        <int>[2, 1, 3],
      );
      expect(result.last.isTakenForCurrentWindow, isTrue);
    });
  });
}
