import 'package:flutter/material.dart';

import '../../notifications/models/scheduled_notification_model.dart';

class Template {
  final int id;
  final String name;
  final String description;
  final String? frequency;
  final int? interval; // e.g., every 2 days, every 3 weeks
  final int? count;
  final List<bool>? daysOfWeek;
  final TimeOfDay? timeOfDay;
  final int iconCode; // <-- store codePoint, not Icon
  final List<ScheduledNotification>? notifications;

  Template({
    required this.id,
    required this.name,
    required this.description,
    this.frequency,
    this.interval,
    this.count,
    this.daysOfWeek,
    this.timeOfDay,
    this.iconCode = 0xe057, // default: Icons.task
    this.notifications,
  });

  factory Template.fromJson(Map<String, dynamic> json) {
    String? timeOfDayStr =
        (json['timeOfDay'] != null ? json['timeOfDay'] as String : null);
    final timeParts = timeOfDayStr?.split(':');
    TimeOfDay? recTime;
    if (timeParts != null && timeParts.length == 2) {
      recTime = TimeOfDay(
        hour: int.parse(timeParts[0]),
        minute: int.parse(timeParts[1]),
      );
    }
    return Template(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      frequency: json['frequency'],
      interval: json['taskInterval'],
      count: json['doCount'],
      daysOfWeek: json['daysOfWeek'] != null
          ? (json['daysOfWeek'] as List).map((e) => e as bool).toList()
          : null,
      timeOfDay: recTime,
      iconCode: json['icon'] ?? 0xe057, // <-- store codePoint
      notifications: (json['notifications'] != null
          ? (json['notifications'] as List)
              .map((n) => ScheduledNotification.fromJson(n))
              .toList()
          : null),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'frequency': frequency,
      'taskInterval': interval,
      'doCount': count,
      'daysOfWeek': daysOfWeek,
      'timeOfDay':
          timeOfDay != null ? '${timeOfDay!.hour}:${timeOfDay!.minute}' : null,
      'icon': iconCode, // <-- store codePoint
      'notifications': notifications?.map((n) => n.toJson()).toList(),
    };
  }
}
