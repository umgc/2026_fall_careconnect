import 'package:flutter/material.dart';

import '../models/task_model.dart';
import 'task_utils.dart';

// =============================
// RecurrenceUtils
// =============================
/// Utility class for creating and managing recurring tasks.
///
/// Provides:
/// - [buildTask] → takes a base [Task] and recurrence options, and produces
///   a properly configured recurring task (with frequency, interval, count).
/// - [calculateCount] → determines how many occurrences fit between two dates.
/// - [calculateEndDate] → determines the end date given a start + count.
///
/// Supports recurrence types: `"Daily"`, `"Weekly"`, `"Monthly"`, `"Yearly"`.
class RecurrenceUtils {
  /// Build a recurring [Task] from a base task and recurrence details.
  ///
  /// Parameters:
  /// - [isRecurring]: whether this task repeats
  /// - [recurrenceType]: "Daily", "Weekly", "Monthly", "Yearly"
  /// - [daysOfWeek]: for weekly recurrences (7-length list, Sun→Sat)
  /// - [interval]: gap between recurrences (e.g., every 2 weeks)
  /// - [count]: total number of occurrences (calculated if missing)
  /// - [startDate]: first occurrence date
  /// - [countStartDate]: series anchor used when calculating [count] during edits
  /// - [endDate]: optional stop date, used to derive [count]
  /// - [dayOfMonth]: for monthly recurrences, which day of month
  ///
  /// Handles:
  /// - Normalizing task type
  /// - Ensuring valid interval defaults (e.g., 1 if missing)
  /// - Calculating `count` if an `endDate` is provided
  /// - Adjusting monthly/yearly boundaries for edge cases (e.g., Feb 30th)
  static Task buildTask({
    required Task baseTask,
    bool? isRecurring,
    String? recurrenceType, // "Daily", "Weekly", "Monthly", "Yearly"
    List<bool>? daysOfWeek,
    int? interval,
    int? count,
    DateTime? startDate,
    DateTime? countStartDate,
    DateTime? endDate,
    int? dayOfMonth,
  }) {
    String? frequency;
    int? intervalToSend = interval;
    int? countToSend = count;

    // Default effective start date
    DateTime effectiveDate = (startDate ?? baseTask.date).toLocal();
    final recurrenceStartDate = (countStartDate ?? effectiveDate).toLocal();
    // Normalize end date if provided
    DateTime? normalizedEndDate =
        endDate != null ? TaskUtils.normalizeDate(endDate) : null;

    if (isRecurring == true && recurrenceType != null) {
      switch (recurrenceType.toLowerCase()) {
        case "daily":
          frequency = "daily";
          intervalToSend = (intervalToSend == null || intervalToSend < 1)
              ? 1
              : intervalToSend;

          if (normalizedEndDate != null) {
            int occurrences = 0;
            DateTime cursor = recurrenceStartDate;
            while (!cursor.isAfter(normalizedEndDate)) {
              occurrences++;
              cursor = cursor.add(Duration(days: intervalToSend));
            }
            countToSend = occurrences;
          } else {
            countToSend ??= 30; // fallback: 30 days if no end date
          }
          break;

        case "weekly":
          frequency = "weekly";
          intervalToSend = (intervalToSend == null || intervalToSend < 1)
              ? 1
              : intervalToSend;

          if (normalizedEndDate != null) {
            final now = DateTime.now();
            final excludePastTimedOccurrences =
                baseTask.id == null && baseTask.timeOfDay != null;
            int occurrences = 0;
            DateTime cursor = recurrenceStartDate;
            DateTime? firstOccurrence;
            // walk week-by-week
            while (!cursor.isAfter(normalizedEndDate)) {
              for (int i = 0; i < 7; i++) {
                if (daysOfWeek != null &&
                    i < daysOfWeek.length &&
                    daysOfWeek[i]) {
                  // i=0 is Sunday; Dart uses Mon=1…Sun=7.
                  int dartDow = (i == 0 ? DateTime.sunday : i);
                  DateTime candidate = DateTime(
                    cursor.year,
                    cursor.month,
                    cursor.day + dartDow - cursor.weekday,
                  );
                  final candidateDateTime = baseTask.timeOfDay == null
                      ? candidate
                      : DateTime(
                          candidate.year,
                          candidate.month,
                          candidate.day,
                          baseTask.timeOfDay!.hour,
                          baseTask.timeOfDay!.minute,
                        );

                  if (!candidate.isBefore(recurrenceStartDate) &&
                      !candidate.isAfter(normalizedEndDate) &&
                      (!excludePastTimedOccurrences ||
                          !candidateDateTime.isBefore(now))) {
                    if (firstOccurrence == null ||
                        candidate.isBefore(firstOccurrence)) {
                      firstOccurrence = candidate;
                    }
                    occurrences++;
                  }
                }
              }
              cursor = DateTime(
                cursor.year,
                cursor.month,
                cursor.day + 7 * intervalToSend,
              );
            }
            countToSend = occurrences;
            if (countStartDate == null && firstOccurrence != null) {
              effectiveDate = firstOccurrence;
            }
          } else {
            countToSend ??= 4; // default 4 weeks if no end date
          }
          break;

        case "monthly":
          frequency = "monthly";
          intervalToSend = (intervalToSend == null || intervalToSend < 1)
              ? 1
              : intervalToSend;

          final preferredDom = dayOfMonth ??
              baseTask.recurrenceAnchorDate?.day ??
              recurrenceStartDate.day;
          int dom = preferredDom;

          // Adjust the first occurrence so it’s not before the startDate
          final daysInStartMonth = DateUtils.getDaysInMonth(
            recurrenceStartDate.year,
            recurrenceStartDate.month,
          );
          dom = dom.clamp(1, daysInStartMonth);
          DateTime firstCandidate = DateTime(
            recurrenceStartDate.year,
            recurrenceStartDate.month,
            dom,
          );

          if (firstCandidate.isBefore(recurrenceStartDate)) {
            // push to next month
            final nextMonth = recurrenceStartDate.month + 1;
            final nextYear = recurrenceStartDate.year + ((nextMonth - 1) ~/ 12);
            final adjustedMonth = ((nextMonth - 1) % 12) + 1;
            final daysInNextMonth = DateUtils.getDaysInMonth(
              nextYear,
              adjustedMonth,
            );
            final nextDom = preferredDom.clamp(1, daysInNextMonth);
            firstCandidate = DateTime(nextYear, adjustedMonth, nextDom);
          }

          if (normalizedEndDate != null) {
            int occurrences = 0;
            DateTime cursor = firstCandidate;
            while (!cursor.isAfter(normalizedEndDate)) {
              occurrences++;
              final nextMonth = cursor.month + intervalToSend;
              final nextYear = cursor.year + ((nextMonth - 1) ~/ 12);
              final adjustedMonth = ((nextMonth - 1) % 12) + 1;
              final daysInNextMonth = DateUtils.getDaysInMonth(
                nextYear,
                adjustedMonth,
              );
              final nextDom = preferredDom.clamp(1, daysInNextMonth);
              cursor = DateTime(nextYear, adjustedMonth, nextDom);
            }
            countToSend = occurrences;
            if (countStartDate == null) {
              effectiveDate = firstCandidate;
            }
          } else {
            countToSend ??= 12; // fallback: 12 months
            if (countStartDate == null) {
              effectiveDate = firstCandidate;
            }
          }
          break;

        case "yearly":
          frequency = "yearly";
          intervalToSend = (intervalToSend == null || intervalToSend < 1)
              ? 1
              : intervalToSend;

          if (normalizedEndDate != null) {
            int occurrences = 0;
            DateTime cursor = recurrenceStartDate;
            while (!cursor.isAfter(normalizedEndDate)) {
              occurrences++;
              final anchor =
                  baseTask.recurrenceAnchorDate ?? recurrenceStartDate;
              final nextYear = cursor.year + intervalToSend;
              final lastDay = DateUtils.getDaysInMonth(nextYear, anchor.month);
              cursor = DateTime(
                  nextYear, anchor.month, anchor.day.clamp(1, lastDay));
            }
            countToSend = occurrences;
          } else {
            countToSend ??= 5; // default: 5 years
          }
          break;
      }
    }
    if (isRecurring == true &&
        recurrenceType != null &&
        normalizedEndDate != null &&
        baseTask.recurrenceExcludedDates?.isNotEmpty == true) {
      final excluded = baseTask.recurrenceExcludedDates!
          .map(TaskUtils.normalizeDate)
          .toSet();
      var cursor = TaskUtils.normalizeDate(recurrenceStartDate);
      var activeCount = 0;
      while (!cursor.isAfter(normalizedEndDate)) {
        if (!excluded.contains(cursor) &&
            _isCadenceDate(
                cursor,
                recurrenceStartDate,
                recurrenceType,
                intervalToSend ?? 1,
                daysOfWeek,
                baseTask.recurrenceAnchorDate)) {
          activeCount++;
        }
        cursor = DateTime(cursor.year, cursor.month, cursor.day + 1);
      }
      countToSend = activeCount;
    }
    return baseTask.copyWith(
      date: effectiveDate,
      frequency: frequency,
      interval: intervalToSend,
      count: countToSend,
      daysOfWeek: daysOfWeek,
    );
  }

  /// Calculate how many occurrences fit between [startDate] and [endDate].
  ///
  /// Example:
  /// - Daily every 2 days → counts how many times until end
  /// - Weekly with [daysOfWeek] → counts only the selected weekdays
  static int calculateCount({
    required DateTime startDate,
    required DateTime endDate,
    required String frequency, // "daily", "weekly", "monthly", "yearly"
    required int interval,
    List<bool>? daysOfWeek, // for weekly: 7-length list Sunday..Saturday
  }) {
    switch (frequency.toLowerCase()) {
      case "daily":
        final diffDays = endDate.difference(startDate).inDays;
        return (diffDays ~/ interval) + 1;

      case "weekly":
        if (daysOfWeek == null || daysOfWeek.length != 7) {
          final diffWeeks = endDate.difference(startDate).inDays ~/ 7;
          return (diffWeeks ~/ interval) + 1;
        }
        final effectiveInterval = interval < 1 ? 1 : interval;
        final normalizedStart = TaskUtils.normalizeDate(startDate);
        final normalizedEnd = TaskUtils.normalizeDate(endDate);
        final startOfFirstWeek = DateTime(
          normalizedStart.year,
          normalizedStart.month,
          normalizedStart.day - normalizedStart.weekday % 7,
        );
        final startOfFirstWeekUtc = DateTime.utc(
          startOfFirstWeek.year,
          startOfFirstWeek.month,
          startOfFirstWeek.day,
        );
        int count = 0;
        DateTime cursor = normalizedStart;
        while (!cursor.isAfter(normalizedEnd)) {
          final cursorUtc = DateTime.utc(
            cursor.year,
            cursor.month,
            cursor.day,
          );
          final weeksFromStart =
              cursorUtc.difference(startOfFirstWeekUtc).inDays ~/ 7;
          if (weeksFromStart % effectiveInterval == 0 &&
              daysOfWeek[cursor.weekday % 7]) {
            count++;
          }
          cursor = DateTime(cursor.year, cursor.month, cursor.day + 1);
        }
        return count;

      case "monthly":
        int months = (endDate.year - startDate.year) * 12 +
            (endDate.month - startDate.month);
        return (months ~/ interval) + 1;

      case "yearly":
        int years = endDate.year - startDate.year;
        return (years ~/ interval) + 1;

      default:
        return 1;
    }
  }

  /// Calculate the end date of a recurrence series given [count].
  ///
  /// Example:
  /// - Daily, interval=1, count=10 → endDate = startDate + 9 days
  /// - Yearly, interval=2, count=3 → endDate = startDate + 4 years
  static DateTime calculateEndDate({
    required DateTime startDate,
    required String frequency,
    required int interval,
    required int count,
    List<bool>? daysOfWeek,
    DateTime? cadenceAnchorDate,
    List<DateTime>? excludedDates,
  }) {
    if (excludedDates?.isNotEmpty == true && count > 0) {
      var rawCount = count;
      while (true) {
        final end = calculateEndDate(
            startDate: startDate,
            frequency: frequency,
            interval: interval,
            count: rawCount,
            daysOfWeek: daysOfWeek,
            cadenceAnchorDate: cadenceAnchorDate);
        final removed = excludedDates!
            .map(TaskUtils.normalizeDate)
            .toSet()
            .where((day) =>
                !day.isBefore(startDate) &&
                !day.isAfter(end) &&
                _isCadenceDate(day, startDate, frequency, interval, daysOfWeek,
                    cadenceAnchorDate))
            .length;
        final requiredRawCount = count + removed;
        if (requiredRawCount == rawCount) return end;
        rawCount = requiredRawCount;
      }
    }
    if (cadenceAnchorDate != null && count > 1) {
      final yearly = frequency.toLowerCase() == "yearly";
      if (yearly || frequency.toLowerCase() == "monthly") {
        final month = DateTime(
          startDate.year + (yearly ? (count - 1) * interval : 0),
          yearly
              ? cadenceAnchorDate.month
              : startDate.month + (count - 1) * interval,
        );
        final lastDay = DateUtils.getDaysInMonth(month.year, month.month);
        return DateTime(
            month.year, month.month, cadenceAnchorDate.day.clamp(1, lastDay));
      }
    }
    switch (frequency.toLowerCase()) {
      case "daily":
        return startDate.add(Duration(days: (count - 1) * interval));
      case "weekly":
        if (daysOfWeek != null &&
            daysOfWeek.length == 7 &&
            daysOfWeek.any((selected) => selected)) {
          final effectiveInterval = interval < 1 ? 1 : interval;
          final normalizedStart = TaskUtils.normalizeDate(startDate);
          final startOfFirstWeek = DateTime(
            normalizedStart.year,
            normalizedStart.month,
            normalizedStart.day - normalizedStart.weekday % 7,
          );
          final startOfFirstWeekUtc = DateTime.utc(
            startOfFirstWeek.year,
            startOfFirstWeek.month,
            startOfFirstWeek.day,
          );
          final targetCount = count < 1 ? 1 : count;
          var occurrences = 0;
          var cursor = normalizedStart;

          while (true) {
            final cursorUtc = DateTime.utc(
              cursor.year,
              cursor.month,
              cursor.day,
            );
            final weeksFromStart =
                cursorUtc.difference(startOfFirstWeekUtc).inDays ~/ 7;
            if (weeksFromStart % effectiveInterval == 0 &&
                daysOfWeek[cursor.weekday % 7]) {
              occurrences++;
              if (occurrences == targetCount) return cursor;
            }
            cursor = DateTime(cursor.year, cursor.month, cursor.day + 1);
          }
        }
        return startDate.add(Duration(days: (count - 1) * 7 * interval));
      case "monthly":
        return DateTime(
          startDate.year,
          startDate.month + (count - 1) * interval,
          startDate.day,
        );
      case "yearly":
        return DateTime(
          startDate.year + (count - 1) * interval,
          startDate.month,
          startDate.day,
        );
      default:
        return startDate;
    }
  }

  static bool _isCadenceDate(DateTime day, DateTime start, String frequency,
      int interval, List<bool>? days, DateTime? anchor) {
    final step = interval < 1 ? 1 : interval;
    final date = TaskUtils.normalizeDate(day);
    final origin = TaskUtils.normalizeDate(start);
    final delta = DateTime.utc(date.year, date.month, date.day)
        .difference(DateTime.utc(origin.year, origin.month, origin.day))
        .inDays;
    if (delta < 0) return false;
    switch (frequency.toLowerCase()) {
      case 'daily':
        return delta % step == 0;
      case 'weekly':
        if (days == null || days.length != 7) {
          return delta % (7 * step) == 0;
        }
        if (!days.any((selected) => selected)) return false;
        return ((delta + origin.weekday % 7) ~/ 7) % step == 0 &&
            days[date.weekday % 7];
      case 'monthly':
        final months =
            (date.year - origin.year) * 12 + date.month - origin.month;
        return months >= 0 &&
            months % step == 0 &&
            calculateEndDate(
                    startDate: origin,
                    frequency: frequency,
                    interval: step,
                    count: months ~/ step + 1,
                    cadenceAnchorDate: anchor) ==
                date;
      case 'yearly':
        final years = date.year - origin.year;
        return years >= 0 &&
            years % step == 0 &&
            calculateEndDate(
                    startDate: origin,
                    frequency: frequency,
                    interval: step,
                    count: years ~/ step + 1,
                    cadenceAnchorDate: anchor) ==
                date;
      default:
        return date == origin;
    }
  }
}
