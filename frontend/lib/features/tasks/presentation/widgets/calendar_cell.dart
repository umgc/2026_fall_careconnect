import 'package:calendar_view/calendar_view.dart';
import 'package:care_connect_app/features/tasks/models/task_model.dart';
import 'package:care_connect_app/features/tasks/utils/task_type_manager.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// =============================
/// CalendarCell Widget
/// =============================
///
/// Represents a single day cell in the [MonthView] calendar.
/// - Displays the day number.
/// - Shows up to 4 dots, each representing a task for that day.
/// - Highlights today or the currently selected day.
///
/// Used by the Calendar Assistant screen for the monthly view.
class CalendarCell extends StatelessWidget {
  /// The calendar day this cell represents.
  final DateTime date;

  /// List of tasks scheduled for this day.
  final List<CalendarEventData<Task>> events;

  /// Whether this day is the current day (today).
  final bool isToday;

  /// Whether this day is within the current month.
  final bool isInMonth;

  /// Whether this day falls on a weekend.
  final bool isWeekend;

  /// Whether this day is the currently selected day.
  final bool isSelected;

  const CalendarCell({
    super.key,
    required this.date,
    required this.events,
    required this.isToday,
    required this.isInMonth,
    required this.isWeekend,
    required this.isSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final manager = context.watch<TaskTypeManager>();

    return Container(
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(
          color: isSelected
              ? Colors.green
              : (isToday ? theme.colorScheme.primary : theme.dividerColor),
          width: isSelected ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        children: [
          Text(
            "${date.day}",
            style: (theme.textTheme.bodySmall ?? const TextStyle()).copyWith(
              color:
                  isInMonth ? theme.colorScheme.onSurface : theme.disabledColor,
            ),
          ),
          Wrap(
            spacing: 2,
            runSpacing: 2,
            children: events.take(4).map((e) {
              final color = manager.getColor(e.event?.taskType);
              return Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(shape: BoxShape.circle, color: color),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
