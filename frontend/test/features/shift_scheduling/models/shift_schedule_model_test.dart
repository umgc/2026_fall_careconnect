// Tests for ShiftSchedule model
// (lib/features/shift_scheduling/models/shift_schedule_model.dart).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/shift_scheduling/models/shift_schedule_model.dart';

void main() {
  group('ShiftSchedule', () {
    test('constructor stores all fields', () {
      final schedule = ShiftSchedule(
        id: 1,
        caretakerId: 'ct-42',
        title: 'Morning Shift',
        description: 'Regular morning care visit',
        recurring: true,
        daysOfWeek: [true, false, true, false, true, false, false],
        startDate: DateTime(2024, 6, 1),
        startTime: const TimeOfDay(hour: 8, minute: 0),
        endTime: const TimeOfDay(hour: 12, minute: 30),
      );

      expect(schedule.id, 1);
      expect(schedule.caretakerId, 'ct-42');
      expect(schedule.title, 'Morning Shift');
      expect(schedule.description, 'Regular morning care visit');
      expect(schedule.recurring, isTrue);
      expect(schedule.daysOfWeek, [true, false, true, false, true, false, false]);
      expect(schedule.startDate, DateTime(2024, 6, 1));
      expect(schedule.startTime, const TimeOfDay(hour: 8, minute: 0));
      expect(schedule.endTime, const TimeOfDay(hour: 12, minute: 30));
    });

    test('recurring defaults to false', () {
      final schedule = ShiftSchedule(
        id: 2,
        caretakerId: 'ct-1',
        title: 'One-time visit',
        description: 'Temporary shift',
        daysOfWeek: [false, false, false, false, false, false, false],
        startDate: DateTime(2024, 7, 4),
        startTime: const TimeOfDay(hour: 9, minute: 0),
        endTime: const TimeOfDay(hour: 11, minute: 0),
      );
      expect(schedule.recurring, isFalse);
    });

    group('fromJson', () {
      test('parses all fields correctly', () {
        final schedule = ShiftSchedule.fromJson({
          'id': 5,
          'caretakerId': 'ct-99',
          'title': 'Evening Shift',
          'description': 'Evening care',
          'recurring': true,
          'daysOfWeek': [false, true, true, true, true, true, false],
          'startDate': '2024-09-01T00:00:00.000Z',
          'startTime': {'hour': 17, 'minute': 0},
          'endTime': {'hour': 21, 'minute': 30},
        });

        expect(schedule.id, 5);
        expect(schedule.caretakerId, 'ct-99');
        expect(schedule.title, 'Evening Shift');
        expect(schedule.description, 'Evening care');
        expect(schedule.recurring, isTrue);
        expect(schedule.daysOfWeek, [false, true, true, true, true, true, false]);
        expect(schedule.startDate, DateTime.parse('2024-09-01T00:00:00.000Z'));
        expect(schedule.startTime, const TimeOfDay(hour: 17, minute: 0));
        expect(schedule.endTime, const TimeOfDay(hour: 21, minute: 30));
      });

      test('recurring defaults to false when absent from json', () {
        final schedule = ShiftSchedule.fromJson({
          'id': 10,
          'caretakerId': 'ct-5',
          'title': 'Test',
          'description': 'Test shift',
          'daysOfWeek': [true, true, true, true, true, false, false],
          'startDate': '2024-01-01T00:00:00Z',
          'startTime': {'hour': 8, 'minute': 0},
          'endTime': {'hour': 16, 'minute': 0},
        });
        expect(schedule.recurring, isFalse);
      });

      test('empty daysOfWeek defaults to empty list', () {
        final schedule = ShiftSchedule.fromJson({
          'id': 11,
          'caretakerId': 'ct-6',
          'title': 'Test',
          'description': 'Test',
          'startDate': '2024-01-01T00:00:00Z',
          'startTime': {'hour': 8, 'minute': 0},
          'endTime': {'hour': 16, 'minute': 0},
        });
        expect(schedule.daysOfWeek, isEmpty);
      });

      test('parses midnight start and end times', () {
        final schedule = ShiftSchedule.fromJson({
          'id': 12,
          'caretakerId': 'ct-7',
          'title': 'Overnight',
          'description': 'Night shift',
          'startDate': '2026-03-17T00:00:00Z',
          'startTime': {'hour': 0, 'minute': 0},
          'endTime': {'hour': 23, 'minute': 59},
        });
        expect(schedule.startTime, const TimeOfDay(hour: 0, minute: 0));
        expect(schedule.endTime, const TimeOfDay(hour: 23, minute: 59));
      });

      test('parses date-only ISO string', () {
        final schedule = ShiftSchedule.fromJson({
          'id': 13,
          'caretakerId': 'ct-8',
          'title': 'Test',
          'description': 'Test',
          'startDate': '2026-06-15',
          'startTime': {'hour': 9, 'minute': 30},
          'endTime': {'hour': 17, 'minute': 0},
        });
        expect(schedule.startDate.year, 2026);
        expect(schedule.startDate.month, 6);
        expect(schedule.startDate.day, 15);
      });

      test('all days true for 7-day schedule', () {
        final schedule = ShiftSchedule.fromJson({
          'id': 14,
          'caretakerId': 'ct-9',
          'title': 'Every Day',
          'description': '7-day coverage',
          'recurring': true,
          'daysOfWeek': [true, true, true, true, true, true, true],
          'startDate': '2026-01-01T00:00:00Z',
          'startTime': {'hour': 6, 'minute': 0},
          'endTime': {'hour': 14, 'minute': 0},
        });
        expect(schedule.daysOfWeek.every((d) => d), isTrue);
        expect(schedule.daysOfWeek.length, 7);
      });
    });

    test('constructor with all weekdays selected', () {
      final schedule = ShiftSchedule(
        id: 20,
        caretakerId: 'ct-20',
        title: 'Weekday Shift',
        description: 'Mon-Fri',
        recurring: true,
        daysOfWeek: [true, true, true, true, true, false, false],
        startDate: DateTime(2026, 1, 5),
        startTime: const TimeOfDay(hour: 7, minute: 0),
        endTime: const TimeOfDay(hour: 15, minute: 0),
      );
      expect(schedule.daysOfWeek.where((d) => d).length, 5);
    });

    test('constructor with weekend-only schedule', () {
      final schedule = ShiftSchedule(
        id: 21,
        caretakerId: 'ct-21',
        title: 'Weekend Shift',
        description: 'Sat-Sun only',
        recurring: true,
        daysOfWeek: [false, false, false, false, false, true, true],
        startDate: DateTime(2026, 1, 3),
        startTime: const TimeOfDay(hour: 8, minute: 0),
        endTime: const TimeOfDay(hour: 20, minute: 0),
      );
      expect(schedule.daysOfWeek.where((d) => d).length, 2);
    });

    test('short duration shift (1 hour)', () {
      final schedule = ShiftSchedule(
        id: 22,
        caretakerId: 'ct-22',
        title: 'Quick Check',
        description: 'Brief visit',
        daysOfWeek: [true, false, false, false, false, false, false],
        startDate: DateTime(2026, 3, 2),
        startTime: const TimeOfDay(hour: 10, minute: 0),
        endTime: const TimeOfDay(hour: 11, minute: 0),
      );
      expect(schedule.title, 'Quick Check');
      expect(schedule.startTime.hour, 10);
      expect(schedule.endTime.hour, 11);
    });
  });
}
