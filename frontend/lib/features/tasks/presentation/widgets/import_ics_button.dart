import 'dart:convert';

import 'package:care_connect_app/features/tasks/models/task_model.dart';
import 'package:care_connect_app/features/tasks/utils/recurrence_utils.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

/// A button to import tasks from an .ics file
/// - Opens a dialog with a patient dropdown
/// - Lets the user choose a .ics file
/// - Parses VEVENT blocks and sends tasks to the backend
/// - Uses RecurrenceUtils to handle UNTIL → count conversions
class ImportIcsButton extends StatefulWidget {
  final Map<int, String> patientNames; // patientId → name
  final VoidCallback? onTasksImported; // callback after import finishes
  final dynamic filePicker; // instead of FilePicker

  const ImportIcsButton({
    super.key,
    required this.patientNames,
    this.onTasksImported,
    this.filePicker,
  });

  @override
  State<ImportIcsButton> createState() => _ImportIcsButtonState();
}

class _ImportIcsButtonState extends State<ImportIcsButton> {
  int? _selectedPatientId;

  Future<void> _pickAndImportFile() async {
    final t = AppLocalizations.of(context)!;
    if (_selectedPatientId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.calendarSelectPatientBeforeImport)),
      );
      return;
    }

    final picker = widget.filePicker ?? FilePicker.platform;
    final result = await picker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['ics'],
    );
    if (result == null || result.files.isEmpty) return;

    final fileBytes = result.files.first.bytes;
    if (fileBytes == null) return;

    final content = utf8.decode(fileBytes);
    final events = _parseIcs(content);
    int createdCount = 0;
    int queuedCount = 0;

    for (final ev in events) {
      final freq = ev['FREQ'] as String?;
      final interval = ev['INTERVAL'] as int?;
      final until = ev['UNTIL'] as DateTime?;
      final count = ev['COUNT'] as int?;
      final daysOfWeek =
          (ev['DAYS_OF_WEEK'] as List<bool>?) ?? List.filled(7, false);

      // Compute count if UNTIL provided but no explicit COUNT
      int? computedCount = count;
      if (freq != null &&
          until != null &&
          computedCount == null &&
          ev['DTSTART'] != null) {
        computedCount = RecurrenceUtils.calculateCount(
          startDate: ev['DTSTART'],
          endDate: until,
          frequency: freq,
          interval: interval ?? 1,
          daysOfWeek: daysOfWeek,
        );
      }

      // Build base Task
      final baseTask = Task(
        name: ev['SUMMARY'] ?? "Untitled",
        description: ev['DESCRIPTION'] ?? "",
        date: ev['DTSTART'] ?? DateTime.now(),
        timeOfDay: ev['DTEND'] != null
            ? TimeOfDay(hour: ev['DTEND']!.hour, minute: ev['DTEND']!.minute)
            : null,
        assignedPatientId: _selectedPatientId,
        isComplete: false,
        taskType: _inferTaskType(ev['SUMMARY'] ?? "").toLowerCase(),
      );

      final effectiveFreq = (freq ?? '').toLowerCase();
      final effectiveInterval = interval ?? 1;
      final effectiveCount = computedCount ?? ev['COUNT'];
      final normalizedUntil = until ?? ev['UNTIL'] ?? ev['DTEND'];

      final finalTask = RecurrenceUtils.buildTask(
        baseTask: baseTask,
        isRecurring: effectiveFreq.isNotEmpty,
        recurrenceType: effectiveFreq,
        interval: effectiveInterval,
        count: effectiveCount,
        daysOfWeek: daysOfWeek,
        startDate: ev['DTSTART'],
        endDate: effectiveCount == null ? normalizedUntil : null,
      );

      try {
        final response = await ApiService.createTaskV2(
          finalTask.assignedPatientId!,
          jsonEncode(finalTask.toJson()),
        );

        if (response.statusCode >= 200 && response.statusCode < 300) {
          createdCount++;
          if (response.headers['x-offline-queued'] == 'true') {
            queuedCount++;
          }
        } else {
          debugPrint(
            "Failed to import event ${ev['SUMMARY']}: ${response.statusCode}",
          );
        }
      } catch (e) {
        debugPrint("Error creating task: $e");
      }
    }

    if (mounted) {
      final message = queuedCount == 0
          ? "Imported $createdCount task${createdCount == 1 ? '' : 's'}"
          : (queuedCount == createdCount
              ? "Imported tasks queued for sync when internet is restored"
              : "Imported $createdCount task${createdCount == 1 ? '' : 's'} ($queuedCount queued for sync)");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
        ),
      );
    }

    widget.onTasksImported?.call();
  }

  /// Simple ICS parser supporting DTSTART, DTEND, RRULE, SUMMARY, DESCRIPTION.
  List<Map<String, dynamic>> _parseIcs(String ics) {
    final lines = ics.split(RegExp(r'\r?\n'));
    final events = <Map<String, dynamic>>[];
    Map<String, dynamic>? current;

    for (var line in lines) {
      line = line.trim();
      if (line.startsWith('BEGIN:VEVENT')) {
        current = {};
      } else if (line.startsWith('END:VEVENT')) {
        if (current != null) events.add(current);
        current = null;
      } else if (current != null) {
        final parts = line.split(':');
        if (parts.length < 2) continue;
        final key = parts[0].split(';')[0];
        final value = parts.sublist(1).join(':');

        switch (key) {
          case 'SUMMARY':
            current['SUMMARY'] = value;
            break;
          case 'DESCRIPTION':
            current['DESCRIPTION'] = value;
            break;
          case 'DTSTART':
            current['DTSTART'] = _parseDate(value);
            break;
          case 'DTEND':
            current['DTEND'] = _parseDate(value);
            break;
          case 'RRULE':
            // Parse RRULE details into the event
            _parseRrule(value, current);

            // Compute COUNT if missing, using UNTIL and DTSTART
            final freq = current['FREQ'] ?? current['freq'];
            final until = current['UNTIL'];
            final start = current['DTSTART'];
            final days = current['DAYS_OF_WEEK'] ?? List.filled(7, false);

            if (current['COUNT'] == null &&
                freq != null &&
                until != null &&
                start != null) {
              final computedCount = RecurrenceUtils.calculateCount(
                startDate: start,
                endDate: until,
                frequency: freq,
                interval: current['INTERVAL'] ?? 1,
                daysOfWeek: days,
              );
              current['COUNT'] = computedCount;
            }
            break;
        }
      }
    }
    return events;
  }

  void _parseRrule(String rrule, Map<String, dynamic> event) {
    final parts = rrule.split(';');
    List<bool> daysOfWeek = List.filled(7, false);

    for (final part in parts) {
      final kv = part.split('=');
      if (kv.length != 2) continue;
      final key = kv[0].toUpperCase();
      final val = kv[1];

      switch (key) {
        case 'FREQ':
          event['FREQ'] = val.toLowerCase();
          break;
        case 'INTERVAL':
          event['INTERVAL'] = int.tryParse(val);
          break;
        case 'COUNT':
          event['COUNT'] = int.tryParse(val);
          break;
        case 'UNTIL':
          event['UNTIL'] = _parseDate(val);
          break;
        case 'BYDAY':
          final dayMap = {
            'SU': 0,
            'MO': 1,
            'TU': 2,
            'WE': 3,
            'TH': 4,
            'FR': 5,
            'SA': 6,
          };
          for (final day in val.split(',')) {
            final idx = dayMap[day.trim().toUpperCase()];
            if (idx != null) daysOfWeek[idx] = true;
          }
          break;
      }
    }

    // Always attach a full 7-length array
    event['DAYS_OF_WEEK'] = daysOfWeek;
  }

  DateTime? _parseDate(String raw) {
    try {
      if (raw.contains('T')) {
        return DateTime.parse(raw.replaceAll('Z', ''));
      } else {
        return DateTime.parse(
          '${raw.substring(0, 4)}-${raw.substring(4, 6)}-${raw.substring(6, 8)}',
        );
      }
    } catch (_) {
      return null;
    }
  }

  void _openDialog() {
    final t = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.calendarImportIcs),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<int>(
              decoration: InputDecoration(labelText: t.calendarAssignToPatient),
              initialValue: _selectedPatientId,
              items: widget.patientNames.entries
                  .map(
                    (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
                  )
                  .toList(),
              onChanged: (val) => setState(() => _selectedPatientId = val),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t.cancel),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _pickAndImportFile();
            },
            child: Text(t.calendarChooseFile),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final label = AppLocalizations.of(context)!.calendarImportIcs;
    final isCompact = MediaQuery.of(context).size.width < 500;

    if (isCompact) {
      // Compact version: icon-only
      return IconButton(
        tooltip: label,
        icon: const Icon(Icons.file_upload),
        onPressed: _openDialog,
      );
    }

    // Default (wide) version: full labeled button
    return ElevatedButton.icon(
      onPressed: _openDialog,
      icon: const Icon(Icons.file_upload),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        textStyle: const TextStyle(fontSize: 14),
      ),
    );
  }

  String _inferTaskType(String summary) {
    final lower = summary.toLowerCase();
    if (lower.contains("appointment")) return "Appointment";
    if (lower.contains("lab")) return "Lab";
    if (lower.contains("medication") || lower.contains("meds")) {
      return "Medication";
    }
    if (lower.contains("exercise") || lower.contains("workout")) {
      return "Exercise";
    }
    return "Imported";
  }
}
