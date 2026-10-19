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
    DateTime? endDate,
    int? dayOfMonth,
  }) {
    String? frequency;
    int? intervalToSend = interval;
    int? countToSend = count;

    // Default effective start date
    DateTime effectiveDate = (startDate ?? baseTask.date).toLocal();
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
            DateTime cursor = effectiveDate;
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
            int occurrences = 0;
            DateTime cursor = effectiveDate;
            // walk week-by-week
            while (!cursor.isAfter(normalizedEndDate)) {
              for (int i = 0; i < 7; i++) {
                if (daysOfWeek != null &&
                    i < daysOfWeek.length &&
                    daysOfWeek[i]) {
                  // i=0 is Sunday → Dart DateTime.weekday is Mon=1…Sun=7
                  int dartDow = (i == 0 ? DateTime.sunday : i + 1);
                  DateTime candidate = cursor.subtract(
                    Duration(days: cursor.weekday - dartDow),
                  );

                  if (!candidate.isBefore(effectiveDate) &&
                      !candidate.isAfter(normalizedEndDate)) {
                    occurrences++;
                  }
                }
              }
              cursor = cursor.add(Duration(days: 7 * intervalToSend));
            }
            countToSend = occurrences;
          } else {
            countToSend ??= 4; // default 4 weeks if no end date
          }
          break;

        case "monthly":
          frequency = "monthly";
          intervalToSend = (intervalToSend == null || intervalToSend < 1)
              ? 1
              : intervalToSend;

          int dom = dayOfMonth ?? effectiveDate.day;

          // Adjust the first occurrence so it’s not before the startDate
          final daysInStartMonth = DateUtils.getDaysInMonth(
            effectiveDate.year,
            effectiveDate.month,
          );
          dom = dom.clamp(1, daysInStartMonth);
          DateTime firstCandidate = DateTime(
            effectiveDate.year,
            effectiveDate.month,
            dom,
          );

          if (firstCandidate.isBefore(effectiveDate)) {
            // push to next month
            final nextMonth = effectiveDate.month + 1;
            final nextYear = effectiveDate.year + ((nextMonth - 1) ~/ 12);
            final adjustedMonth = ((nextMonth - 1) % 12) + 1;
            final daysInNextMonth = DateUtils.getDaysInMonth(
              nextYear,
              adjustedMonth,
            );
            final nextDom = dom.clamp(1, daysInNextMonth);
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
              final nextDom = dom.clamp(1, daysInNextMonth);
              cursor = DateTime(nextYear, adjustedMonth, nextDom);
            }
            countToSend = occurrences;
            effectiveDate =
                firstCandidate; // anchor to correct first occurrence
          } else {
            countToSend ??= 12; // fallback: 12 months
            effectiveDate = firstCandidate;
          }
          break;

        case "yearly":
          frequency = "yearly";
          intervalToSend = (intervalToSend == null || intervalToSend < 1)
              ? 1
              : intervalToSend;

          if (normalizedEndDate != null) {
            int occurrences = 0;
            DateTime cursor = effectiveDate;
            while (!cursor.isAfter(normalizedEndDate)) {
              occurrences++;
              cursor = DateTime(
                cursor.year + intervalToSend,
                cursor.month,
                cursor.day,
              );
            }
            countToSend = occurrences;
          } else {
            countToSend ??= 5; // default: 5 years
          }
          break;
      }
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
        int count = 0;
        DateTime cursor = startDate;
        while (!cursor.isAfter(endDate)) {
          if (daysOfWeek[cursor.weekday % 7]) {
            count++;
          }
          cursor = cursor.add(const Duration(days: 1));
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
  }) {
    switch (frequency.toLowerCase()) {
      case "daily":
        return startDate.add(Duration(days: (count - 1) * interval));
      case "weekly":
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
}
