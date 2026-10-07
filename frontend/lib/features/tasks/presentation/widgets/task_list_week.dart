import 'package:calendar_view/calendar_view.dart';
import 'package:care_connect_app/features/tasks/models/task_model.dart';
import 'package:care_connect_app/features/tasks/utils/task_type_manager.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// =============================
/// TaskListWeek Widget
/// =============================
///
/// Displays all tasks scheduled within a week as a vertical list of [ListTile]s.
/// - Groups tasks by day (implicitly by sorting).
/// - Shows task icon, name, time, and assigned patient.
/// - Provides edit and delete actions through callbacks.
///
/// Used in the Calendar Assistant screen when the "Weekly" view is active.
class TaskListWeek extends StatelessWidget {
  /// Events from the calendar controller (converted into tasks).
  final List<CalendarEventData<Task>> events;

  /// Map of patient IDs to display names (used for "assigned to" labels).
  final Map<int, String> patientNames;

  /// Callback when the user taps the edit button on a task.
  final void Function(Task) onEdit;

  /// Callback when the user taps the delete button on a task.
  final void Function(Task) onDelete;

  /// Injectable backend update callback for easier testing.
  final Future<void> Function(int taskId, bool complete) updateCompletion;

  TaskListWeek({
    super.key,
    required this.events,
    required this.patientNames,
    required this.onEdit,
    required this.onDelete,
    Future<void> Function(int, bool)? updateCompletion,
  }) : updateCompletion =
           updateCompletion ??
           ((int id, bool complete) =>
               ApiService.updateTaskCompletionV2(id, complete));

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final manager = context.watch<TaskTypeManager>();

    if (events.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Text(t.calendarNoTasksWeek),
      );
    }

    // Extract Task objects and sort by date/time/name
    final tasks = events.map((e) => e.event!).toList()
      ..sort((a, b) {
        final cmpDate = a.date.compareTo(b.date);
        if (cmpDate != 0) return cmpDate;
        if (a.timeOfDay != null && b.timeOfDay != null) {
          final aMins = a.timeOfDay!.hour * 60 + a.timeOfDay!.minute;
          final bMins = b.timeOfDay!.hour * 60 + b.timeOfDay!.minute;
          return aMins.compareTo(bMins);
        }
        if (a.timeOfDay != null) return -1;
        if (b.timeOfDay != null) return 1;
        return a.name.compareTo(b.name);
      });

    return ListView.builder(
      shrinkWrap: true,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: tasks.length,
      itemBuilder: (context, index) {
        final task = tasks[index];
        final assignedName = task.assignedPatientId != null
            ? patientNames[task.assignedPatientId] ?? t.calendarUnknownPatient
            : t.calendarUnassigned;
        final color = manager.getColor(task.taskType);
        final icon = manager.getIcon(task.taskType);

        return StatefulBuilder(
          builder: (context, setState) {
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 2,
              ),
              leading: Icon(icon, color: color),
              title: Text(
                task.name,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 0,
                    children: [
                      Text(
                        "${task.date.month}/${task.date.day} • "
                        "${task.timeOfDay != null ? task.timeOfDay!.format(context) : t.calendarAllDay}",
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: task.isComplete
                              ? Colors.white
                              : Colors.green,
                          backgroundColor: task.isComplete
                              ? Colors.green
                              : Colors.transparent,
                          side: BorderSide(
                            color: task.isComplete ? Colors.green : Colors.grey,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          minimumSize: const Size(0, 26),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: task.isComplete
                            ? const Icon(Icons.check, size: 14)
                            : const SizedBox.shrink(),
                        label: Text(
                            task.isComplete
                              ? t.calendarCompleted
                              : t.calendarMarkComplete,
                          style: TextStyle(
                            color: task.isComplete
                                ? Colors.white
                                : Colors.green,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        onPressed: () async {
                          final newStatus = !task.isComplete;
                          setState(() => task.isComplete = newStatus);
                          try {
                            await updateCompletion(task.id!, newStatus);
                          } catch (e) {
                            setState(() => task.isComplete = !newStatus);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(t.calendarUpdateTaskFailed),
                              ),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                    if (assignedName.isNotEmpty &&
                      assignedName != t.calendarUnassigned)
                    Text("👤 $assignedName"),
                ],
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit, color: Colors.blue),
                    onPressed: () => onEdit(task),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => onDelete(task),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
