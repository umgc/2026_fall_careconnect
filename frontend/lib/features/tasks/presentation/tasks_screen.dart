// Display the tasks screen for a specific patient, consisting of a list of tasks retrieved from the backend.
import 'dart:convert';

import 'package:care_connect_app/features/tasks/models/task_model.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:care_connect_app/widgets/common_drawer.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TasksScreen extends StatefulWidget {
  final int patientId;
  final String patientName;

  const TasksScreen({
    super.key,
    required this.patientId,
    required this.patientName,
  });

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  List<Task> tasks = [];
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _fetchTasks();
  }

  @override
  void didUpdateWidget(TasksScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _fetchTasks();
  }

  Future<void> _fetchTasks() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final user = Provider.of<UserProvider>(context, listen: false).user;
      if (user == null) {
        setState(() {
          error = 'User not logged in.';
          loading = false;
        });
        return;
      }
      final response = await ApiService.getPatientTasks(
        widget.patientId,
      ).timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        final List data = json.decode(response.body);
        print('Fetched tasks: ${data.length}');
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.blue.shade900,
        iconTheme: const IconThemeData(color: Colors.white),
        foregroundColor: Colors.white,
        title: const Text(
          'Tasks Dashboard',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      drawer: const CommonDrawer(currentRoute: '/patient-tasks'),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          context.go(
            '/assign-task?patientId=${widget.patientId}&patientName=${widget.patientName}',
          );
        },
        backgroundColor: Colors.indigo,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(child: Text(error!))
              : ListView.builder(
                  itemCount: tasks.length,
                  itemBuilder: (context, index) {
                    final task = tasks[index];
                    return Card(
                      margin: const EdgeInsets.all(8.0),
                      child: ListTile(
                        title: Text(task.name),
                        subtitle: Text(task.description),
                        trailing: Semantics(
                          label: 'Delete task',
                          button: true,
                          child: IconButton(
                            icon: const Icon(Icons.delete),
                            tooltip: 'Delete task',
                            onPressed: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('Delete Task'),
                                  content: const Text(
                                    'Are you sure you want to delete this task?',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(false),
                                      child: const Text('Cancel'),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(true),
                                      child: const Text('Delete'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm == true) {
                                final prefs =
                                    await SharedPreferences.getInstance();
                                final userId = prefs.getString('userId');
                                if (userId != null) {
                                  await ApiService.deleteTask(task.id!);
                                  _fetchTasks();
                                }
                              }
                            },
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
