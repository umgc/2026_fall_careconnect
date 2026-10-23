import 'package:calendar_view/calendar_view.dart';
import 'package:care_connect_app/features/tasks/models/task_model.dart';
import 'package:care_connect_app/features/tasks/utils/task_type_manager.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// =============================
/// EventTile Widget
/// =============================
///
/// A styled tile representing a single task event.
/// - Used in [WeekView] and [DayView] to display scheduled tasks.
/// - Shows a colored border and background tint based on task type.
/// - Displays a small dot + task name.
///
/// Only the first event in the list is displayed (assumes no overlap).
class EventTile extends StatelessWidget {
  /// The list of events that occur in the same time slot.
  /// - If multiple, only the first one is displayed.
  final List<CalendarEventData<Task>> events;

  const EventTile({super.key, required this.events});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    // Nothing to show if no events in this slot
    if (events.isEmpty) return const SizedBox.shrink();

    // Pick the first event and get its task + color
    final task = events.first.event;
    final color = context.select<TaskTypeManager, Color>(
      (mgr) => mgr.getColor(task?.taskType),
    );

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        border: Border.all(color: color, width: 1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.all(6),
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          Expanded(
            child: Text(
              task?.name ?? t.calendarTask,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
