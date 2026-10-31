// Tests for RecurrenceUtils
// (lib/features/tasks/utils/recurrence_utils.dart)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/tasks/utils/recurrence_utils.dart';
import 'package:care_connect_app/features/tasks/models/task_model.dart';

Task _baseTask({DateTime? date}) => Task(
      name: 'Test Task',
      description: 'desc',
      date: date ?? DateTime(2024, 3, 1),
    );

void main() {
  group('RecurrenceUtils.calculateCount', () {
    test('daily every 1 day over 10 days = 11', () {
      final start = DateTime(2024, 1, 1);
      final end = DateTime(2024, 1, 11);
      expect(
        RecurrenceUtils.calculateCount(
          startDate: start,
          endDate: end,
          frequency: 'daily',
          interval: 1,
        ),
        11,
      );
    });

    test('daily every 2 days over 10 days = 6', () {
      final start = DateTime(2024, 1, 1);
      final end = DateTime(2024, 1, 11);
      expect(
        RecurrenceUtils.calculateCount(
          startDate: start,
          endDate: end,
          frequency: 'daily',
          interval: 2,
        ),
        6,
      );
    });

    test('weekly every 1 week over 4 weeks = 5', () {
      final start = DateTime(2024, 1, 1);
      final end = DateTime(2024, 1, 29);
      expect(
        RecurrenceUtils.calculateCount(
          startDate: start,
          endDate: end,
          frequency: 'weekly',
          interval: 1,
        ),
        5,
      );
    });

    test('monthly every 1 month over 3 months = 4', () {
      final start = DateTime(2024, 1, 1);
      final end = DateTime(2024, 4, 1);
      expect(
        RecurrenceUtils.calculateCount(
          startDate: start,
          endDate: end,
          frequency: 'monthly',
          interval: 1,
        ),
        4,
      );
    });

    test('yearly every 1 year over 3 years = 4', () {
      final start = DateTime(2024, 1, 1);
      final end = DateTime(2027, 1, 1);
      expect(
        RecurrenceUtils.calculateCount(
          startDate: start,
          endDate: end,
          frequency: 'yearly',
          interval: 1,
        ),
        4,
      );
    });

    test('unknown frequency returns 1', () {
      final start = DateTime(2024, 1, 1);
      final end = DateTime(2024, 12, 31);
      expect(
        RecurrenceUtils.calculateCount(
          startDate: start,
          endDate: end,
          frequency: 'hourly',
          interval: 1,
        ),
        1,
      );
    });

    test('weekly with daysOfWeek counts specific days', () {
      // Mon–Fri for one week (Mon Jan 1 to Sun Jan 7 2024)
      final start = DateTime(2024, 1, 1); // Monday
      final end = DateTime(2024, 1, 7);   // Sunday
      // daysOfWeek[0] = Sunday, [1] = Monday ... [5] = Saturday
      final dow = [false, true, true, true, true, true, false]; // Mon-Fri
      expect(
        RecurrenceUtils.calculateCount(
          startDate: start,
          endDate: end,
          frequency: 'weekly',
          interval: 1,
          daysOfWeek: dow,
        ),
        5,
      );
    });
  });

  group('RecurrenceUtils.calculateEndDate', () {
    test('daily interval=1 count=10 ends 9 days later', () {
      final start = DateTime(2024, 1, 1);
      final result = RecurrenceUtils.calculateEndDate(
        startDate: start,
        frequency: 'daily',
        interval: 1,
        count: 10,
      );
      expect(result, DateTime(2024, 1, 10));
    });

    test('weekly interval=1 count=4 ends 21 days later', () {
      final start = DateTime(2024, 1, 1);
      final result = RecurrenceUtils.calculateEndDate(
        startDate: start,
        frequency: 'weekly',
        interval: 1,
        count: 4,
      );
      expect(result, DateTime(2024, 1, 22));
    });

    test('monthly interval=1 count=3 ends 2 months later', () {
      final start = DateTime(2024, 1, 15);
      final result = RecurrenceUtils.calculateEndDate(
        startDate: start,
        frequency: 'monthly',
        interval: 1,
        count: 3,
      );
      expect(result, DateTime(2024, 3, 15));
    });

    test('yearly interval=1 count=3 ends 2 years later', () {
      final start = DateTime(2024, 6, 1);
      final result = RecurrenceUtils.calculateEndDate(
        startDate: start,
        frequency: 'yearly',
        interval: 1,
        count: 3,
      );
      expect(result, DateTime(2026, 6, 1));
    });

    test('unknown frequency returns startDate', () {
      final start = DateTime(2024, 1, 1);
      final result = RecurrenceUtils.calculateEndDate(
        startDate: start,
        frequency: 'hourly',
        interval: 1,
        count: 5,
      );
      expect(result, start);
    });
  });

  group('RecurrenceUtils.buildTask', () {
    test('non-recurring task returns base task unchanged (no frequency)', () {
      final base = _baseTask(date: DateTime(2024, 3, 1));
      final result = RecurrenceUtils.buildTask(
        baseTask: base,
        isRecurring: false,
      );
      expect(result.frequency, isNull);
    });

    test('daily recurring sets frequency to daily', () {
      final base = _baseTask(date: DateTime(2024, 3, 1));
      final result = RecurrenceUtils.buildTask(
        baseTask: base,
        isRecurring: true,
        recurrenceType: 'Daily',
        interval: 1,
        count: 5,
      );
      expect(result.frequency, 'daily');
    });

    test('daily recurring with endDate calculates count', () {
      final start = DateTime(2024, 3, 1);
      final end = DateTime(2024, 3, 5);
      final base = _baseTask(date: start);
      final result = RecurrenceUtils.buildTask(
        baseTask: base,
        isRecurring: true,
        recurrenceType: 'Daily',
        interval: 1,
        startDate: start,
        endDate: end,
      );
      expect(result.frequency, 'daily');
      expect(result.count, 5);
    });

    test('daily recurring with no endDate defaults to 30', () {
      final base = _baseTask(date: DateTime(2024, 3, 1));
      final result = RecurrenceUtils.buildTask(
        baseTask: base,
        isRecurring: true,
        recurrenceType: 'Daily',
        interval: 1,
      );
      expect(result.count, 30);
    });

    test('weekly recurring sets frequency to weekly', () {
      final base = _baseTask(date: DateTime(2024, 3, 4)); // Monday
      final result = RecurrenceUtils.buildTask(
        baseTask: base,
        isRecurring: true,
        recurrenceType: 'Weekly',
        interval: 1,
        count: 4,
      );
      expect(result.frequency, 'weekly');
    });

    test('monthly recurring sets frequency to monthly', () {
      final base = _baseTask(date: DateTime(2024, 3, 15));
      final result = RecurrenceUtils.buildTask(
        baseTask: base,
        isRecurring: true,
        recurrenceType: 'Monthly',
        interval: 1,
        count: 6,
      );
      expect(result.frequency, 'monthly');
    });

    test('yearly recurring sets frequency to yearly', () {
      final base = _baseTask(date: DateTime(2024, 6, 1));
      final result = RecurrenceUtils.buildTask(
        baseTask: base,
        isRecurring: true,
        recurrenceType: 'Yearly',
        interval: 1,
        count: 3,
      );
      expect(result.frequency, 'yearly');
    });

    test('yearly defaults to 5 occurrences when no endDate or count', () {
      final base = _baseTask(date: DateTime(2024, 1, 1));
      final result = RecurrenceUtils.buildTask(
        baseTask: base,
        isRecurring: true,
        recurrenceType: 'Yearly',
        interval: 1,
      );
      expect(result.count, 5);
    });

    test('null interval defaults to 1', () {
      final base = _baseTask(date: DateTime(2024, 3, 1));
      final result = RecurrenceUtils.buildTask(
        baseTask: base,
        isRecurring: true,
        recurrenceType: 'Daily',
        interval: null,
        count: 5,
      );
      expect(result.interval, 1);
    });

    test('weekly with an end date counts selected weekdays', () {
      final days = [true, false, true, false, false, false, false]; // Sun, Tue
      final result = RecurrenceUtils.buildTask(
        baseTask: _baseTask(date: DateTime(2024, 3, 1)), // Friday
        isRecurring: true,
        recurrenceType: 'Weekly',
        daysOfWeek: days,
        endDate: DateTime(2024, 3, 31),
      );
      expect(result.frequency, 'weekly');
      expect(result.count, 9);
      expect(result.date, DateTime(2024, 3, 3));
    });

    test('weekly timed task keeps the anchor when countStartDate is given',
        () {
      final result = RecurrenceUtils.buildTask(
        baseTask: Task(
          name: 'Timed',
          description: '',
          date: DateTime(2024, 3, 1),
          timeOfDay: const TimeOfDay(hour: 9, minute: 0),
        ),
        isRecurring: true,
        recurrenceType: 'Weekly',
        daysOfWeek: List<bool>.filled(7, true),
        interval: 2,
        countStartDate: DateTime(2024, 3, 1),
        endDate: DateTime(2024, 3, 20),
      );
      expect(result.date, DateTime(2024, 3, 1));
      expect(result.interval, 2);
    });

    test('monthly with an end date pushes a past day to next month', () {
      final result = RecurrenceUtils.buildTask(
        baseTask: _baseTask(date: DateTime(2024, 1, 20)),
        isRecurring: true,
        recurrenceType: 'Monthly',
        dayOfMonth: 31,
        endDate: DateTime(2024, 6, 30),
      );
      expect(result.frequency, 'monthly');
      expect(result.date, DateTime(2024, 1, 31));
      expect(result.count, 6);

      final pushed = RecurrenceUtils.buildTask(
        baseTask: _baseTask(date: DateTime(2024, 12, 20)),
        isRecurring: true,
        recurrenceType: 'Monthly',
        dayOfMonth: 5,
      );
      expect(pushed.date, DateTime(2025, 1, 5));
      expect(pushed.count, 12);
    });

    test('yearly with an end date counts the years', () {
      final result = RecurrenceUtils.buildTask(
        baseTask: _baseTask(date: DateTime(2024, 3, 1)),
        isRecurring: true,
        recurrenceType: 'Yearly',
        endDate: DateTime(2027, 3, 1),
      );
      expect(result.count, 4);
    });
  });

  group('RecurrenceUtils.calculateEndDate weekly with selected days', () {
    test('returns the date of the last selected occurrence', () {
      final days = [false, true, false, true, false, false, false]; // Mon, Wed
      final end = RecurrenceUtils.calculateEndDate(
        startDate: DateTime(2024, 3, 4), // Monday
        frequency: 'weekly',
        interval: 2,
        count: 3,
        daysOfWeek: days,
      );
      expect(end, DateTime(2024, 3, 18));
    });
  });
}
