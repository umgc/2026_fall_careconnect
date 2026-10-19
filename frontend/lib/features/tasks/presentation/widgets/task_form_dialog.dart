import 'package:care_connect_app/features/notifications/models/scheduled_notification_model.dart';
import 'package:care_connect_app/features/tasks/utils/task_type_manager.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/task_model.dart';
import '../../utils/recurrence_utils.dart';
import '../../utils/task_utils.dart';
import 'recurrence_form.dart';

// =============================
// TaskFormDialog.dart
// =============================

/// TaskFormDialog
/// - Unified form for adding and editing tasks
/// - Contains fields for title, description, type, time, patient assignment,
///   reminders, and recurrence (via [RecurrenceForm]).
/// - Used by both "Add Task" and "Edit Task" flows to keep logic consistent.
class TaskFormDialog extends StatefulWidget {
  final Task? initialTask;
  final bool isCaregiver;
  final List<Map<String, dynamic>> patients;
  final int? defaultPatientId;
  final DateTime? initialDate;
  final DateTime? seriesAnchorDate;

  const TaskFormDialog({
    super.key,
    this.initialTask,
    required this.isCaregiver,
    required this.patients,
    this.defaultPatientId,
    this.initialDate,
    this.seriesAnchorDate,
  });

  @override
  State<TaskFormDialog> createState() => _TaskFormDialogState();
}

class _TaskFormDialogState extends State<TaskFormDialog> {
  late TextEditingController titleController;
  late TextEditingController descriptionController;
  final ScrollController _patientListController = ScrollController();

  TimeOfDay? selectedTime;
  int? selectedPatientId;
  String? selectedTaskType;

  // Assignment state
  Set<int> selectedPatientIds = {};
  bool assignToAll = false;

  // Recurrence state
  bool isRecurring = false;
  String? recurrenceType;
  List<bool>? daysOfWeek;
  int? interval;
  int? count;
  DateTime? startDate;
  DateTime? endDate;
  int? dayOfMonth;
  bool applyToSeries = false;

  String? selectedReminder = "None";
  final List<String> reminderOptions = [
    "None",
    "5 minutes before",
    "15 minutes before",
    "30 minutes before",
    "1 hour before",
    "1 day before",
  ];
  static const String _keepExistingCustom = "Keep existing (custom)";

  @override
  void dispose() {
    _patientListController.dispose();
    titleController.dispose();
    descriptionController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();

    final t = widget.initialTask;

    titleController = TextEditingController(text: t?.name ?? '');
    descriptionController = TextEditingController(text: t?.description ?? '');
    selectedTime = t?.timeOfDay;
    //If editing and taskType is valid, keep it
    selectedTaskType = t?.taskType?.toLowerCase();

    // ensure Save button re-checks when text changes
    titleController.addListener(() => setState(() {}));

    // Setup assignment selection
    if (widget.isCaregiver) {
      if (t != null && t.assignedPatientId != null) {
        selectedPatientIds = {t.assignedPatientId!};
      } else if (widget.defaultPatientId != null) {
        selectedPatientIds = {widget.defaultPatientId!};
      }
    } else if (widget.defaultPatientId != null) {
      selectedPatientIds = {widget.defaultPatientId!};
    }

    if (t != null) {
      recurrenceType = _inferRecurrenceTypeFromTask(t);
      isRecurring = recurrenceType != null;
      daysOfWeek = t.daysOfWeek;
      interval = t.interval;
      count = t.count;
      startDate = t.date;
      final anchorStart = TaskUtils.normalizeDate(
        widget.seriesAnchorDate ?? t.date,
      );

      if (recurrenceType == "Monthly") {
        dayOfMonth = t.date.day;
      }
      // compute end date using helper
      if (count != null &&
          count! > 0 &&
          startDate != null &&
          recurrenceType != null) {
        final iv = (interval == null || interval! < 1) ? 1 : interval!;
        endDate = RecurrenceUtils.calculateEndDate(
          startDate: anchorStart,
          frequency: recurrenceType!,
          interval: iv,
          count: count!,
          daysOfWeek: daysOfWeek,
        );
      }
    } else {
      // Use initialDate from the calendar if passed, otherwise fallback to now
      startDate = TaskUtils.normalizeDate(widget.initialDate ?? DateTime.now());
    }
    _prefillReminderFromExistingIfEditing();
  }
  // ======================
  // Reminder Helpers
  // ======================

  // ===== Reminder helpers =====
  Duration? _offsetForLabel(String? label) {
    switch (label) {
      case "5 minutes before":
        return const Duration(minutes: 5);
      case "15 minutes before":
        return const Duration(minutes: 15);
      case "30 minutes before":
        return const Duration(minutes: 30);
      case "1 hour before":
        return const Duration(hours: 1);
      case "1 day before":
        return const Duration(days: 1);
      default:
        return null;
    }
  }

  /// Try to map a [Duration] difference back into a standard reminder label
  String? _labelForOffset(Duration diff) {
    const tol = Duration(minutes: 2);
    final candidates = <String, Duration>{
      "5 minutes before": const Duration(minutes: 5),
      "15 minutes before": const Duration(minutes: 15),
      "30 minutes before": const Duration(minutes: 30),
      "1 hour before": const Duration(hours: 1),
      "1 day before": const Duration(days: 1),
    };

    for (final e in candidates.entries) {
      if ((e.value - diff).abs() <= tol) return e.key;
    }
    return null;
  }

  /// Populate reminder field if editing a task with existing notifications
  void _prefillReminderFromExistingIfEditing() {
    final t = widget.initialTask;
    if (t == null || t.notifications == null || t.notifications!.isEmpty) {
      selectedReminder = "None";
      return;
    }

    // Use first (earliest) notification
    final notif = (t.notifications!
          ..sort((a, b) {
            final da = DateTime.tryParse(a.scheduledTime.toIso8601String()) ??
                DateTime(1900);
            final db = DateTime.tryParse(b.scheduledTime.toIso8601String()) ??
                DateTime(1900);
            return da.compareTo(db);
          }))
        .first;

    if (startDate == null) {
      selectedReminder = "None";
      return;
    }

    final taskDateTime = DateTime(
      startDate!.year,
      startDate!.month,
      startDate!.day,
      selectedTime?.hour ?? 0,
      selectedTime?.minute ?? 0,
    );

    final scheduled = DateTime.tryParse(notif.scheduledTime.toIso8601String());
    if (scheduled == null) {
      selectedReminder = "None";
      return;
    }

    final diff = taskDateTime.difference(scheduled);

    // Try to match to a standard label
    final label = _labelForOffset(diff);
    selectedReminder = label ?? "None";
  }

  // ======================
  // Recurrence Helpers
  // ======================
  /// Infer recurrence type string from a [Task] model
  String? _inferRecurrenceTypeFromTask(Task t) {
    if (t.daysOfWeek?.any((d) => d) ?? false) return "Weekly";
    switch (t.frequency?.toLowerCase()) {
      case "daily":
        return "Daily";
      case "weekly":
        return "Weekly";
      case "monthly":
        return "Monthly";
      case "yearly":
        return "Yearly";
      default:
        return null;
    }
  }

  /// Validation for Save button
  /// - Requires title
  /// - If recurring, must have type, valid days (weekly), and valid end
  bool get canSave {
    // Must have a name
    if (titleController.text.trim().isEmpty) return false;

    if (isRecurring) {
      // Must have a recurrence type
      if (recurrenceType == null || recurrenceType!.isEmpty) return false;
      // Weekly: require at least one day
      if (recurrenceType!.toLowerCase() == "weekly") {
        if (daysOfWeek == null || !daysOfWeek!.any((d) => d)) {
          return false;
        }
      }
      // Must have an end condition (endDate or count)
      if ((endDate == null || endDate!.isBefore(startDate ?? DateTime.now())) &&
          (count == null || count! <= 0)) {
        return false;
      }
    }

    return true;
  }

  // ======================
  // Build UI
  // ======================

  /// Builds the full Add/Edit Task form inside an AlertDialog
  @override
  Widget build(BuildContext context) {
    final manager = context.watch<TaskTypeManager>();
    final taskTypes = manager.taskTypeColors.keys.toList();

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
          minWidth: 350,
          maxWidth: 600,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ---- Title ----
                Text(
                  widget.initialTask == null ? "Add Task" : "Edit Task",
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),

                // ---- Title field ----
                TextFormField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: "Task Title",
                    border: OutlineInputBorder(),
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                  ),
                ),
                const SizedBox(height: 12),

                // ---- Description ----
                TextFormField(
                  controller: descriptionController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: "Description",
                    border: OutlineInputBorder(),
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                  ),
                ),
                const SizedBox(height: 12),

                // ---- Task Type ----
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: "Task Type",
                    border: OutlineInputBorder(),
                  ),
                  initialValue: selectedTaskType != null &&
                          taskTypes.contains(selectedTaskType)
                      ? selectedTaskType
                      : (taskTypes.contains("general")
                          ? "general"
                          : taskTypes.firstOrNull),
                  items: taskTypes.map((type) {
                    final color = manager.getColor(type);
                    final icon = manager.getIcon(type);
                    return DropdownMenuItem(
                      value: type,
                      child: Row(
                        children: [
                          Icon(icon, color: color, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            type[0].toUpperCase() + type.substring(1),
                            style: TextStyle(color: color),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (val) => setState(() => selectedTaskType = val),
                ),

                const SizedBox(height: 16),
                // ---- Date picker (only for single, nonrecurring tasks) ----
                if (!isRecurring) ...[
                  Row(
                    children: [
                      const Text("Date: "),
                      Text(
                        startDate != null
                            ? "${startDate!.month}/${startDate!.day}/${startDate!.year}"
                            : "Not set",
                      ),
                      const Spacer(),
                      ElevatedButton(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: startDate ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            setState(() => startDate = picked);
                          }
                        },
                        child: const Text("Pick Date"),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],

                // ---- Time picker ----
                Row(
                  children: [
                    const Text("Time: "),
                    Text(
                      selectedTime != null
                          ? "${selectedTime!.hour.toString().padLeft(2, '0')}:${selectedTime!.minute.toString().padLeft(2, '0')}"
                          : "Not set",
                    ),
                    const Spacer(),
                    ElevatedButton(
                      onPressed: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: selectedTime ?? TimeOfDay.now(),
                        );
                        if (picked != null) {
                          setState(() => selectedTime = picked);
                        }
                      },
                      child: const Text("Pick Time"),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // ---- Caregiver patient assignment ----
                if (widget.isCaregiver)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Assign to Patient(s)",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 180,
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Scrollbar(
                            controller: _patientListController,
                            thumbVisibility: true,
                            child: ListView(
                              controller: _patientListController,
                              padding: EdgeInsets.zero,
                              children: [
                                CheckboxListTile(
                                  title: const Text("Assign to All Patients"),
                                  value: assignToAll,
                                  onChanged: (val) {
                                    setState(() {
                                      assignToAll = val ?? false;
                                      if (assignToAll) {
                                        selectedPatientIds = widget.patients
                                            .map<int>(
                                              (p) => p['patient']?['id'] as int,
                                            )
                                            .toSet();
                                      } else {
                                        selectedPatientIds.clear();
                                      }
                                    });
                                  },
                                ),
                                ...widget.patients.map((p) {
                                  final pid = p['patient']?['id'] as int?;
                                  final name =
                                      "${p['patient']?['firstName'] ?? ''} ${p['patient']?['lastName'] ?? ''}"
                                          .trim();
                                  if (pid == null) {
                                    return const SizedBox.shrink();
                                  }
                                  return CheckboxListTile(
                                    title: Text(
                                      name.isEmpty ? "Unknown" : name,
                                    ),
                                    value: selectedPatientIds.contains(pid),
                                    onChanged: (val) {
                                      setState(() {
                                        if (val == true) {
                                          selectedPatientIds.add(pid);
                                        } else {
                                          selectedPatientIds.remove(pid);
                                        }
                                        assignToAll =
                                            selectedPatientIds.length ==
                                                widget.patients.length;
                                      });
                                    },
                                  );
                                }),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),

                // ---- Reminder dropdown ----
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: "Reminder Notification",
                    border: OutlineInputBorder(),
                  ),
                  initialValue: selectedReminder,
                  items: reminderOptions.map((opt) {
                    return DropdownMenuItem(value: opt, child: Text(opt));
                  }).toList(),
                  onChanged: (val) {
                    setState(() => selectedReminder = val);
                  },
                ),

                const SizedBox(height: 16),

                // ---- Recurrence form ----
                RecurrenceForm(
                  initialIsRecurring: isRecurring,
                  initialRecurrenceType: recurrenceType,
                  initialDaysOfWeek: daysOfWeek,
                  initialInterval: interval,
                  initialCount: count,
                  initialStartDate: startDate,
                  initialEndDate: endDate,
                  initialDayOfMonth: dayOfMonth,
                  showApplyToSeries: widget.initialTask != null,
                  anchorStartDate: widget.seriesAnchorDate,
                  onChanged: ({
                    bool? isRecurring,
                    String? recurrenceType,
                    List<bool>? daysOfWeek,
                    int? interval,
                    int? count,
                    DateTime? startDate,
                    DateTime? endDate,
                    int? dayOfMonth,
                    bool? applyToSeries,
                  }) {
                    setState(() {
                      this.isRecurring = isRecurring ?? false;
                      this.recurrenceType = recurrenceType;
                      this.daysOfWeek = daysOfWeek;
                      this.interval = interval;
                      this.count = count;
                      this.startDate = startDate ?? this.startDate;
                      this.endDate = endDate;
                      this.dayOfMonth = dayOfMonth;
                      this.applyToSeries = applyToSeries ?? this.applyToSeries;
                    });
                  },
                ),

                const SizedBox(height: 20),

                // ---- Actions (manually placed) ----
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, null),
                      child: const Text("Cancel"),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: canSave
                          ? () {
                              final rawTask = Task(
                                id: widget.initialTask?.id,
                                name: titleController.text,
                                description: descriptionController.text,
                                date: startDate ?? DateTime.now(),
                                timeOfDay: selectedTime,
                                assignedPatientId: widget.isCaregiver
                                    ? (selectedPatientIds.isNotEmpty
                                        ? selectedPatientIds.first
                                        : null)
                                    : widget.defaultPatientId,
                                isComplete:
                                    widget.initialTask?.isComplete ?? false,
                                notifications:
                                    widget.initialTask?.notifications,
                                frequency: recurrenceType,
                                interval: interval,
                                count: count,
                                daysOfWeek: daysOfWeek,
                                taskType: (selectedTaskType ??
                                        widget.initialTask?.taskType ??
                                        "general")
                                    .toLowerCase(),
                              );

                              // ---- Notifications ----
                              List<ScheduledNotification>? notificationsToSave;
                              if (selectedReminder == "None") {
                                notificationsToSave = [];
                              } else if (selectedReminder ==
                                  _keepExistingCustom) {
                                notificationsToSave =
                                    widget.initialTask?.notifications ?? [];
                              } else {
                                final off = _offsetForLabel(selectedReminder);
                                final base = DateTime(
                                  rawTask.date.year,
                                  rawTask.date.month,
                                  rawTask.date.day,
                                  rawTask.timeOfDay?.hour ?? 0,
                                  rawTask.timeOfDay?.minute ?? 0,
                                );
                                final reminderTime =
                                    off == null ? base : base.subtract(off);
                                notificationsToSave = [
                                  ScheduledNotification(
                                    scheduledTime: reminderTime,
                                    title: "Reminder: ${rawTask.name}",
                                    body: rawTask.description.isNotEmpty
                                        ? rawTask.description
                                        : "Don't forget this task.",
                                    notificationType: "TASK_REMINDER",
                                    receiverId: rawTask.assignedPatientId!,
                                    status: "PENDING",
                                  ),
                                ];
                              }
                              rawTask.notifications = notificationsToSave;

                              final finalTask = RecurrenceUtils.buildTask(
                                baseTask: rawTask,
                                isRecurring: isRecurring,
                                recurrenceType: recurrenceType,
                                daysOfWeek: daysOfWeek,
                                interval: interval,
                                count: count,
                                startDate: rawTask.date,
                                endDate: endDate,
                                dayOfMonth: dayOfMonth,
                              );

                              Future.microtask(() {
                                if (!mounted) return;

                                if (widget.isCaregiver &&
                                    selectedPatientIds.length > 1) {
                                  final multipleTasks = selectedPatientIds
                                      .map(
                                        (pid) => finalTask.copyWith(
                                          assignedPatientId: pid,
                                        ),
                                      )
                                      .toList();

                                  Navigator.pop(context, {
                                    'tasks': multipleTasks,
                                    'applyToSeries': applyToSeries,
                                  });
                                } else {
                                  Navigator.pop(context, {
                                    'task': [finalTask],
                                    'applyToSeries': applyToSeries,
                                  });
                                }
                              });
                            }
                          : null,
                      child: const Text("Save"),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
