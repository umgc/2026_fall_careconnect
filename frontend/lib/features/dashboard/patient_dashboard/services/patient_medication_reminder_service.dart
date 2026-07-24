import 'dart:convert';

import 'package:care_connect_app/features/dashboard/patient_dashboard/models/medication_reminder_item.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/services/api_service.dart';

class PatientMedicationReminderService {
  // Local optimistic overrides:
  // - key exists with DateTime value: locally marked as taken at that time.
  // - key exists with null value: locally marked as missed (clear taken status).
  final Map<int, DateTime?> _localLastTakenOverrideByMedicationId =
      <int, DateTime?>{};

  Future<List<MedicationReminderItem>> loadReminders({
    required int? patientId,
    required AppLocalizations t,
  }) async {
    if (patientId == null) {
      return const <MedicationReminderItem>[];
    }

    final response = await ApiService.getPatientMedicationsForPatient(patientId);
    if (response.statusCode != 200) {
      return const <MedicationReminderItem>[];
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      return const <MedicationReminderItem>[];
    }

    final now = DateTime.now();
    final List<MedicationReminderItem> reminders = <MedicationReminderItem>[];
    final activeMedicationIds = <int>{};
    var syntheticId = -1;

    for (final row in decoded) {
      if (row is! Map) {
        continue;
      }

      final isActive = row['isActive'] != false;
      if (!isActive) {
        continue;
      }

      final name = (row['medicationName'] ?? '').toString().trim();
      if (name.isEmpty) {
        continue;
      }

      final medicationId = _parseInt(row['id']) ?? syntheticId--;
      activeMedicationIds.add(medicationId);

      final dosage = (row['dosage'] ?? t.ptmedreminderservice_doseNotSet).toString();
      final frequency = (row['frequency'] ?? t.ptmedreminderservice_frequencyNotSet).toString();
      final startDate = DateTime.tryParse((row['startDate'] ?? '').toString());
      final frequencyInterval = _frequencyInterval(frequency, t);
      final serverLastTaken = _parseDateTime(row['lastTaken']);
      final hasLocalOverride =
          _localLastTakenOverrideByMedicationId.containsKey(medicationId);
      final localLastTaken = _localLastTakenOverrideByMedicationId[medicationId];

      final effectiveLastTaken =
          hasLocalOverride ? localLastTaken : serverLastTaken;
      final nextDueFromLastTaken =
          effectiveLastTaken?.toLocal().add(frequencyInterval);
      final isTakenForWindow =
          nextDueFromLastTaken != null && nextDueFromLastTaken.isAfter(now);
      final nextDueAt = nextDueFromLastTaken ??
          (startDate != null && startDate.isAfter(now) ? startDate : now);

      // Clear local optimistic override once backend state catches up.
      if (hasLocalOverride) {
        if (localLastTaken == null && serverLastTaken == null) {
          _localLastTakenOverrideByMedicationId.remove(medicationId);
        } else if (localLastTaken != null && serverLastTaken != null) {
          final serverUtc = serverLastTaken.toUtc();
          final localUtc = localLastTaken.toUtc();
          if (!serverUtc.isBefore(localUtc)) {
            _localLastTakenOverrideByMedicationId.remove(medicationId);
          }
        }
      }

      reminders.add(
        MedicationReminderItem(
          medicationId: medicationId,
          medicationName: name,
          dosage: dosage,
          frequency: frequency,
          nextDueAt: nextDueAt,
          isTakenForCurrentWindow: isTakenForWindow,
        ),
      );
    }

    reminders.sort((a, b) {
      if (a.isTakenForCurrentWindow != b.isTakenForCurrentWindow) {
        return a.isTakenForCurrentWindow ? 1 : -1;
      }
      return a.nextDueAt.compareTo(b.nextDueAt);
    });

    _localLastTakenOverrideByMedicationId.removeWhere(
      (medicationId, _) => !activeMedicationIds.contains(medicationId),
    );

    return reminders;
  }

  void markTaken({
    required int medicationId,
    DateTime? takenAt,
  }) {
    _localLastTakenOverrideByMedicationId[medicationId] =
        (takenAt ?? DateTime.now()).toUtc();
  }

  void markMissed({required int medicationId}) {
    _localLastTakenOverrideByMedicationId[medicationId] = null;
  }

  void clearLocalOverride({required int medicationId}) {
    _localLastTakenOverrideByMedicationId.remove(medicationId);
  }

  bool hasPendingUntaken(List<MedicationReminderItem> reminders) {
    return reminders.any((item) => !item.isTakenForCurrentWindow);
  }

  int? _parseInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  DateTime? _parseDateTime(dynamic value) {
    if (value is DateTime) {
      return value;
    }
    if (value is String && value.trim().isNotEmpty) {
      return DateTime.tryParse(value.trim());
    }
    return null;
  }

  Duration _frequencyInterval(String frequency, AppLocalizations t) {
    final text = frequency.toLowerCase();

    if (text.contains('twice') || text.contains(t.ptmedreminderservice_twice) || text.contains('2x') || text.contains('two') || text.contains(t.ptmedreminderservice_two)) {
      return const Duration(hours: 12);
    }
    if (text.contains('three') || text.contains(t.ptmedreminderservice_three) || text.contains('3x')) {
      return const Duration(hours: 8);
    }
    if ((text.contains('every') && text.contains('hour')) || (text.contains(t.ptmedreminderservice_every) && text.contains(t.ptmedreminderservice_hour))) {
      final match = RegExp(r'(\d+)').firstMatch(text);
      final hours = match == null ? 1 : int.tryParse(match.group(1)!) ?? 1;
      return Duration(hours: hours.clamp(1, 24));
    }
    if (text.contains('week') || text.contains(t.ptmedreminderservice_week)) {
      return const Duration(days: 7);
    }
    if (text.contains('month') || text.contains(t.ptmedreminderservice_month)) {
      return const Duration(days: 30);
    }
    if (text.contains('day') || text.contains(t.ptmedreminderservice_day) || text.contains('daily') || text.contains(t.ptmedreminderservice_daily)) {
      return const Duration(days: 1);
    }

    return const Duration(days: 1);
  }
}
