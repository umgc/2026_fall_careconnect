import 'dart:convert';

import 'package:care_connect_app/features/tasks/models/task_model.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:care_connect_app/widgets/task_widget.dart';
import 'package:flutter/material.dart';

class PatientTasksWidget extends StatefulWidget {
  final int patientId;
  final String patientName;

  /// If true, allows add/edit/delete. If false, read-only.
  final bool isCaregiver;

  const PatientTasksWidget({
    super.key,
    required this.patientId,
    required this.patientName,
    required this.isCaregiver,
  });

  @override
  State<PatientTasksWidget> createState() => _PatientTasksWidgetState();
}

class _PatientTasksWidgetState extends State<PatientTasksWidget> {
  List<Task> tasks = [];
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _fetchTasks();
  }

  Future<void> _fetchTasks() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final response = await ApiService.getPatientTasks(widget.patientId);
      if (response.statusCode == 200) {
        final List data = json.decode(response.body);
        setState(() {
          tasks = data.map((taskJson) => Task.fromJson(taskJson)).toList();
          loading = false;
        });
      } else {
        setState(() {
          error = 'Failed to load tasks: ${response.statusCode}';
          loading = false;
        });
      }
    } catch (e) {
      setState(() {
        error = 'Error: $e';
        loading = false;
      });
    }
  }

  Future<void> _deleteTask(int taskId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Task'),
        content: const Text('Are you sure you want to delete this task?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await ApiService.deleteTask(taskId);
      _fetchTasks();
    }
  }

  void _showTaskForm({Task? task}) async {
    await showDialog<Task>(
      context: context,
      builder: (context) => TaskFormDialog(
        patientId: widget.patientId,
        existingTask: task,
        onTaskSaved: () {
          _fetchTasks();
        },
        onCancel: () => Navigator.of(context).pop(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(8.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : error != null
                ? Center(child: Text(error!))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Tasks for ${widget.patientName}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                          const Spacer(),
                          if (widget.isCaregiver)
                            IconButton(
                              icon: const Icon(Icons.add),
                              tooltip: 'Add Task',
                              onPressed: () => _showTaskForm(),
                            ),
                        ],
                      ),
                      const Divider(),
                      tasks.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(16.0),
                              child: Text('No tasks assigned.'),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: tasks.length,
                              itemBuilder: (context, index) {
                                final task = tasks[index];
                                return ListTile(
                                  title: Text(task.name),
                                  subtitle: Text(task.description),
                                  trailing: widget.isCaregiver
                                      ? Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              icon: const Icon(Icons.edit),
                                              tooltip: 'Edit Task',
                                              onPressed: () =>
                                                  _showTaskForm(task: task),
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.delete),
                                              tooltip: 'Delete Task',
                                              onPressed: () =>
                                                  _deleteTask(task.id!),
                                            ),
                                          ],
                                        )
                                      : null,
                                  onTap: () {
                                    // Display task details in a non-editable format
                                    showDialog(
                                      context: context,
                                      builder: (context) =>
                                          TaskInfo(task: task),
                                    );
                                  },
                                );
                              },
                            ),
                    ],
                  ),
      ),
    );
  }
}
