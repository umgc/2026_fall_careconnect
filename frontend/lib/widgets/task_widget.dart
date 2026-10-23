import 'dart:convert';

import 'package:care_connect_app/features/tasks/models/task_model.dart';
import 'package:care_connect_app/features/tasks/models/template_model.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:flutter/material.dart';

class TaskFormDialog extends StatefulWidget {
  final int patientId;
  final Task? existingTask;
  final VoidCallback? onTaskSaved;
  final VoidCallback? onCancel;

  const TaskFormDialog({
    super.key,
    required this.patientId,
    this.existingTask,
    this.onTaskSaved,
    this.onCancel,
  });

  @override
  State<TaskFormDialog> createState() => _TaskFormDialogState();
}

class _TaskFormDialogState extends State<TaskFormDialog> {
  late String name;
  late String description;
  late DateTime date;
  TimeOfDay? timeOfDay;

  // Static icon mapping for tree-shaking optimization
  static const Map<int, IconData> _iconMap = {
    // Common Material Icons with their code points
    57344: Icons.task_alt, // task
    57345: Icons.assignment, // assignment
    57693: Icons.medical_services, // medical
    58133: Icons.fitness_center, // fitness
    58134: Icons.restaurant, // nutrition
    58135: Icons.bed, // rest
    58136: Icons.local_pharmacy, // medication
    58137: Icons.timer, // timer
    58138: Icons.schedule, // schedule
    58139: Icons.checklist, // checklist
    58140: Icons.note_add, // note
    58141: Icons.health_and_safety, // health
    58142: Icons.psychology, // mental health
    58143: Icons.directions_walk, // walking
    58144: Icons.water_drop, // hydration
    58145: Icons.self_improvement, // improvement
    58146: Icons.healing, // healing
    58147: Icons.monitor_heart, // heart monitor
    58148: Icons.bloodtype, // blood
    58149: Icons.thermostat, // temperature
    // Add more mappings as needed
  };

  // Helper method to get icon from code with fallback
  IconData _getIconFromCode(int? iconCode) {
    if (iconCode == null) return Icons.task_alt;
    return _iconMap[iconCode] ?? Icons.task_alt;
  }

  // For template selection
  List<Template> templates = [];
  bool loadingTemplates = true;
  String? templateError;
  Template? selectedTemplate;
  bool showForm = false; // If true, show the task form
  Template? selectedTemplateForForm;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    name = widget.existingTask?.name ?? '';
    description = widget.existingTask?.description ?? '';
    date = widget.existingTask?.date ?? now;
    timeOfDay = widget.existingTask?.timeOfDay;

    if (widget.existingTask == null) {
      _fetchTemplates();
    } else {
      showForm = true; // Editing an existing task, skip template selection
      loadingTemplates = false;
    }
  }

  Future<void> _fetchTemplates() async {
    setState(() {
      loadingTemplates = true;
      templateError = null;
    });
    try {
      final response = await ApiService.getTaskTemplates(
        widget.patientId,
      ).timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        final List data = json.decode(response.body);
        setState(() {
          templates = data
              .map((templateJson) => Template.fromJson(templateJson))
              .toList();
          loadingTemplates = false;
        });
      } else {
        setState(() {
          templateError = 'Failed to load templates: ${response.statusCode}';
          loadingTemplates = false;
        });
      }
    } catch (e) {
      setState(() {
        templateError = 'Error: $e';
        loadingTemplates = false;
      });
    }
  }

  Future<void> _submit(Task task) async {
    if (!task.isValid()) return;

    final taskData = task.toJson();

    try {
      if (widget.existingTask == null) {
        // Add
        await ApiService.createTask(widget.patientId, jsonEncode(taskData));
      } else {
        // Edit
        await ApiService.editTask(widget.existingTask!.id!, taskData);
      }
    } catch (e) {
      print('Error saving task: $e');
    }
    widget.onTaskSaved?.call();
  }

  @override
  Widget build(BuildContext context) {
    // If editing or form state is set, show the TaskForm
    if (showForm) {
      return AlertDialog(
        title: Text(
          widget.existingTask == null ? 'Add Custom Task' : 'Edit Task',
        ),
        content: TaskForm(
          key: const ValueKey('custom-task-form'),
          initialTask: widget.existingTask ??
              (selectedTemplateForForm != null
                  ? Task(
                      id: -1,
                      name: selectedTemplateForForm!.name,
                      description: selectedTemplateForForm!.description,
                      date: DateTime.now(),
                      timeOfDay: selectedTemplateForForm!.timeOfDay,
                      assignedPatientId: widget.patientId,
                      isComplete: false,
                      notifications: null,
                      frequency: selectedTemplateForForm!.frequency,
                      interval: selectedTemplateForForm!.interval,
                      count: selectedTemplateForForm!.count,
                      daysOfWeek: selectedTemplateForForm!.daysOfWeek ??
                          List<bool>.filled(7, false),
                    )
                  : null),
          template: selectedTemplateForForm,
          onSaved: (task) {
            setState(() {
              name = task.name;
              description = task.description;
              date = task.date;
              timeOfDay = task.timeOfDay;
              // Optionally update other fields if you want to keep them in state
            });
            _submit(task);
          },
          patientId: widget.patientId,
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (widget.existingTask == null) {
                // Go back to template selection
                setState(() {
                  showForm = false;
                  selectedTemplateForForm = null;
                });
              } else {
                if (widget.onCancel != null) widget.onCancel!();
              }
            },
            child: const Text('Back'),
          ),
        ],
      );
    }

    // Template selection step
    return AlertDialog(
      title: const Text('Assign Task'),
      content: loadingTemplates
          ? const SizedBox(
              height: 100,
              child: Center(child: CircularProgressIndicator()),
            )
          : templateError != null
              ? Text(templateError!)
              : SizedBox(
                  width: 350,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Choose a task template or create a custom task.',
                        style: TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: templates.length + 1,
                          itemBuilder: (context, index) {
                            if (index == 0) {
                              return Card(
                                margin: const EdgeInsets.symmetric(vertical: 5),
                                child: ListTile(
                                  leading: Icon(
                                    Icons.task,
                                    size: 40,
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                  ),
                                  title: const Text('Custom Task'),
                                  subtitle: const Text(
                                    'Create a custom task for your patient.',
                                  ),
                                  trailing: const Icon(Icons.arrow_forward_ios),
                                  onTap: () {
                                    setState(() {
                                      showForm = true;
                                      selectedTemplateForForm = null;
                                    });
                                  },
                                ),
                              );
                            }
                            final template = templates[index - 1];
                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 5),
                              child: ListTile(
                                leading: Icon(
                                  _getIconFromCode(template.iconCode),
                                  size: 40,
                                  color: Colors.indigo,
                                ),
                                title: Text(template.name),
                                subtitle: Text(template.description),
                                trailing: const Icon(Icons.arrow_forward_ios),
                                onTap: () {
                                  setState(() {
                                    showForm = true;
                                    selectedTemplateForForm = template;
                                  });
                                },
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
      actions: [
        TextButton(onPressed: widget.onCancel, child: const Text('Cancel')),
      ],
    );
  }
}

class TaskForm extends StatefulWidget {
  final Task? initialTask;
  final Template? template;
  final void Function(Task task) onSaved;
  final int patientId;

  const TaskForm({
    super.key,
    this.initialTask,
    this.template,
    required this.onSaved,
    required this.patientId,
  });

  @override
  State<TaskForm> createState() => _TaskFormState();
}

class _TaskFormState extends State<TaskForm> {
  final _formKey = GlobalKey<FormState>();
  late Task task;

  @override
  void initState() {
    super.initState();
    // Use initialTask if provided, else build from template, else default
    if (widget.initialTask != null) {
      task = Task(
        id: widget.initialTask!.id,
        name: widget.initialTask!.name,
        description: widget.initialTask!.description,
        date: widget.initialTask!.date,
        timeOfDay: widget.initialTask!.timeOfDay,
        assignedPatientId: widget.initialTask!.assignedPatientId,
        isComplete: widget.initialTask!.isComplete,
        notifications: widget.initialTask!.notifications,
        frequency: widget.initialTask!.frequency,
        interval: widget.initialTask!.interval,
        count: widget.initialTask!.count,
        daysOfWeek:
            widget.initialTask!.daysOfWeek ?? List<bool>.filled(7, false),
      );
    } else if (widget.template != null) {
      task = Task(
        id: -1,
        name: widget.template!.name,
        description: widget.template!.description,
        date: DateTime.now(),
        timeOfDay: widget.template!.timeOfDay,
        assignedPatientId: widget.patientId,
        isComplete: false,
        notifications: null,
        frequency: widget.template!.frequency,
        interval: widget.template!.interval,
        count: widget.template!.count,
        daysOfWeek: widget.template!.daysOfWeek ?? List<bool>.filled(7, false),
      );
    } else {
      task = Task(
        id: -1,
        name: '',
        description: '',
        date: DateTime.now(),
        timeOfDay: null,
        assignedPatientId: widget.patientId,
        isComplete: false,
        notifications: null,
        frequency: null,
        interval: null,
        count: null,
        daysOfWeek: List<bool>.filled(7, false),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              initialValue: task.name,
              decoration: const InputDecoration(labelText: 'Task Name'),
              validator: (v) => v == null || v.isEmpty ? 'Enter a name' : null,
              onChanged: (v) => setState(() => task.name = v),
            ),
            TextFormField(
              initialValue: task.description,
              decoration: const InputDecoration(labelText: 'Description'),
              onChanged: (v) => setState(() => task.description = v),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Date'),
              subtitle: Text('${task.date.toLocal()}'.split(' ')[0]),
              trailing: IconButton(
                icon: const Icon(Icons.calendar_today),
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: task.date,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) setState(() => task.date = picked);
                },
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Time'),
              subtitle: Text(
                task.timeOfDay != null
                    ? '${task.timeOfDay!.hour.toString().padLeft(2, '0')}:${task.timeOfDay!.minute.toString().padLeft(2, '0')}'
                    : 'Not set',
              ),
              trailing: IconButton(
                icon: const Icon(Icons.access_time),
                onPressed: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: task.timeOfDay ?? TimeOfDay.now(),
                  );
                  if (picked != null) setState(() => task.timeOfDay = picked);
                },
              ),
            ),
            const SizedBox(height: 8),
            // Frequency Dropdown
            DropdownButtonFormField<String>(
              initialValue: task.frequency,
              items: const [
                DropdownMenuItem(value: 'DAILY', child: Text('Daily')),
                DropdownMenuItem(value: 'WEEKLY', child: Text('Weekly')),
                DropdownMenuItem(value: 'MONTHLY', child: Text('Monthly')),
                DropdownMenuItem(value: 'YEARLY', child: Text('Yearly')),
                DropdownMenuItem(
                  value: 'EVERY_WEEK_DAY',
                  child: Text('Every Week Day'),
                ),
              ],
              onChanged: (value) => setState(() => task.frequency = value),
              decoration: const InputDecoration(
                labelText: 'Frequency',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            // Interval
            TextFormField(
              initialValue: task.interval?.toString() ?? '',
              decoration: const InputDecoration(
                labelText: 'Interval (e.g., 1 = every day)',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              onChanged: (v) => setState(() => task.interval = int.tryParse(v)),
            ),
            const SizedBox(height: 8),
            // Count
            TextFormField(
              initialValue: task.count?.toString() ?? '',
              decoration: const InputDecoration(
                labelText: 'Count (number of occurrences)',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              onChanged: (v) => setState(() => task.count = int.tryParse(v)),
            ),
            const SizedBox(height: 8),
            // Days of Week
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Days of Week',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Row(
                  spacing: 4,
                  children: List.generate(7, (i) {
                    const days = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
                    return FilterChip(
                      label: Text(days[i]),
                      showCheckmark: false,
                      selected: task.daysOfWeek?[i] ?? false,
                      onSelected: (selected) {
                        setState(() {
                          task.daysOfWeek?[i] = selected;
                        });
                      },
                    );
                  }),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () {
                if (_formKey.currentState!.validate()) {
                  _formKey.currentState!.save();
                  widget.onSaved(task);
                  Navigator.of(context).pop();
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

class TaskInfo extends StatelessWidget {
  final Task task;

  const TaskInfo({super.key, required this.task});

  @override
  Widget build(BuildContext context) {
    String daysOfWeekString = '';
    if (task.daysOfWeek != null) {
      const dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      final selectedDays = <String>[];
      for (int i = 0;
          i < task.daysOfWeek!.length && i < dayLabels.length;
          i++) {
        if (task.daysOfWeek![i]) selectedDays.add(dayLabels[i]);
      }
      daysOfWeekString =
          selectedDays.isNotEmpty ? selectedDays.join(', ') : 'None';
    }

    return AlertDialog(
      title: Text(task.name),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Description: ${task.description}'),
            Text('Date: ${task.date.toLocal()}'),
            if (task.timeOfDay != null)
              Text(
                'Time: ${task.timeOfDay!.hour.toString().padLeft(2, '0')}:${task.timeOfDay!.minute.toString().padLeft(2, '0')}',
              ),
            Text('Status: ${task.isComplete ? 'Completed' : 'Incomplete'}'),
            if (task.frequency != null) Text('Frequency: ${task.frequency}'),
            if (task.interval != null) Text('Interval: ${task.interval}'),
            if (task.count != null) Text('Count: ${task.count}'),
            if (task.daysOfWeek != null)
              Text('Days of Week: $daysOfWeekString'),
            if (task.notifications != null &&
                task.notifications!.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text(
                'Notifications:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              ...task.notifications!.map((n) => Text(n.toString())),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
