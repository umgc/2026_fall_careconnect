import 'package:flutter/material.dart';

import '../../notifications/models/scheduled_notification_model.dart';

/// =============================
/// Task Model
/// =============================
/// Represents a scheduled task in CareConnect, which can:
/// - Belong to a patient (or be unassigned)
/// - Be one-time or recurring
/// - Contain reminders/notifications
/// - Track completion state
///
/// Supports recurrence (daily, weekly, monthly, yearly)
/// and series updates (via `parentTaskId` + `applyToSeries`).
class Task {
  int? id;
  int? assignedPatientId; // Optional, can be null if not assigned to a user
  String name;
  String description;
  int? createdAt;
  DateTime date;
  TimeOfDay? timeOfDay; // Optional, can be null if not set
  bool isComplete;
  List<ScheduledNotification>? notifications;

  //Recurrence fields
  DateTime? recurrenceAnchorDate;
  List<DateTime>? recurrenceExcludedDates;
  String? frequency; // e.g., daily, weekly, monthly, yearly
  int? interval; // number of days/weeks/months between recurrences
  int? count; // number of total occurrences
  List<bool>? daysOfWeek; // e.g., [false, true, false, true, ...] for Mon/Wed
  final String? taskType; // "General" | "Lab" | "Appointment" | "custom"
  bool applyToSeries;
  int? parentTaskId;

  Task({
    this.id,
    required this.name,
    this.description = "",
    this.createdAt,
    required this.date,
    this.timeOfDay,
    this.assignedPatientId,
    this.isComplete = false,
    this.notifications,
    this.frequency,
    this.recurrenceAnchorDate,
    this.recurrenceExcludedDates,
    this.interval,
    this.count,
    this.daysOfWeek,
    this.taskType,
    this.applyToSeries = false,
    this.parentTaskId,
  });

  /// Factory constructor: build a [Task] from JSON data.
  ///
  /// Handles:
  /// - Parsing `daysOfWeek` into `List<bool>`
  /// - Supporting timeOfDay as `"HH:mm"` string or map `{hour, minute}`
  /// - Mapping backend variations (`interval` vs `taskInterval`, `count` vs `doCount`)
  factory Task.fromJson(Map<String, dynamic> json) {
    final parsedDays =
        json['daysOfWeek'] != null ? List<bool>.from(json['daysOfWeek']) : null;

    return Task(
      id: json['id'],
      name: json['name'],
      description: json['description'] ?? "",
      createdAt: json['createdAt'],
      date: DateTime.parse(json['date']),
      timeOfDay: json['timeOfDay'] != null
          ? TimeOfDay(
              hour: json['timeOfDay'] is String
                  ? int.parse(json['timeOfDay'].split(':')[0])
                  : json['timeOfDay']['hour'],
              minute: json['timeOfDay'] is String
                  ? int.parse(json['timeOfDay'].split(':')[1])
                  : json['timeOfDay']['minute'],
            )
          : null,
      assignedPatientId: json['patientId'],
      isComplete: json['isComplete'] ?? false,
      notifications: json['notifications'] != null
          ? (json['notifications'] as List)
              .map((n) => ScheduledNotification.fromJson(n))
              .toList()
          : null,
      frequency: json['frequency'],
      recurrenceExcludedDates: (json['recurrenceExcludedDates'] as List?)
          ?.map((value) => DateTime.parse(value as String))
          .toList(),
      recurrenceAnchorDate: json['recurrenceAnchorDate'] != null
          ? DateTime.parse(json['recurrenceAnchorDate'])
          : null,
      interval: json['interval'] ?? json['taskInterval'],
      count: json['count'] ?? json['doCount'],
      daysOfWeek: parsedDays,
      taskType: json['taskType'],
      applyToSeries: json['applyToSeries'] ?? false,
      parentTaskId: json['parentTaskId'],
    );
  }

  /// Convert a [Task] to JSON for API serialization.
  ///
  /// Notes:
  /// - Converts [date] to ISO8601 string
  /// - Converts [timeOfDay] into `"HH:mm"` string
  /// - Uses `"isCompleted"` for completion state (matches backend)
  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'description': description,
      'date': date.toIso8601String(),
      'timeOfDay': timeOfDay != null
          ? "${timeOfDay!.hour.toString().padLeft(2, '0')}:${timeOfDay!.minute.toString().padLeft(2, '0')}"
          : null,
      'isCompleted': isComplete,
      'notifications': notifications?.map((n) => n.toJson()).toList(),
      'frequency': frequency,
      'interval': interval,
      'count': count,
      'daysOfWeek': daysOfWeek,
      'taskType': taskType ?? "general",
      'patientId': assignedPatientId,
      'applyToSeries': applyToSeries,
      'parentTaskId': parentTaskId,
    };
  }

  bool isValid() {
    return name.isNotEmpty && description.isNotEmpty;
  }
}

// =============================
// TaskCopyWith Extension
// =============================
/// Provides a `copyWith` method for immutability-style updates.
///
/// Example:
/// ```dart
/// final updated = task.copyWith(name: "New name", isComplete: true);
/// ```
extension TaskCopyWith on Task {
  Task copyWith({
    int? id,
    String? name,
    String? description,
    int? createdAt,
    DateTime? date,
    TimeOfDay? timeOfDay,
    int? assignedPatientId,
    bool? isComplete,
    String? frequency,
    DateTime? recurrenceAnchorDate,
    List<DateTime>? recurrenceExcludedDates,
    int? interval,
    int? count,
    List<bool>? daysOfWeek,
    String? taskType,
    bool? applyToSeries,
    int? parentTaskId,
  }) {
    return Task(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      date: date ?? this.date,
      timeOfDay: timeOfDay ?? this.timeOfDay,
      assignedPatientId: assignedPatientId ?? this.assignedPatientId,
      isComplete: isComplete ?? this.isComplete,
      notifications: notifications, // keep existing notifications
      frequency: frequency ?? this.frequency,
      recurrenceAnchorDate: recurrenceAnchorDate ?? this.recurrenceAnchorDate,
      recurrenceExcludedDates:
          recurrenceExcludedDates ?? this.recurrenceExcludedDates,
      interval: interval ?? this.interval,
      count: count ?? this.count,
      daysOfWeek: daysOfWeek ?? this.daysOfWeek,
      taskType: taskType ?? this.taskType,
      applyToSeries: applyToSeries ?? this.applyToSeries,
      parentTaskId: parentTaskId ?? this.parentTaskId,
    );
  }
}
