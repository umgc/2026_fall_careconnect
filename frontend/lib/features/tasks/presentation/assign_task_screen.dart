import 'dart:convert';

import 'package:care_connect_app/features/tasks/models/template_model.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:care_connect_app/widgets/common_drawer.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

// This screen provides a choice of what type of task to assign to a patient
// by loading the available pre-defined tasks or offering to create a custom task.
class AssignTaskScreen extends StatefulWidget {
  final int patientId;
  final String patientName;

  const AssignTaskScreen({
    super.key,
    required this.patientId,
    required this.patientName,
  });

  @override
  State<AssignTaskScreen> createState() => _AssignTaskScreenState();
}

class _AssignTaskScreenState extends State<AssignTaskScreen> {
  List<Template> templates = [];
  bool loading = true;
  String? error;

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

  @override
  void initState() {
    super.initState();
    _fetchTemplates();
  }

  Future<void> _fetchTemplates() async {
    setState(() {
      loading = true;
      error = null;
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
          loading = false;
        });
      } else {
        setState(() {
          error = 'Failed to load templates: ${response.statusCode}';
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
      appBar: AppBar(title: Text('Assign Task to ${widget.patientName}')),
      drawer: const CommonDrawer(currentRoute: '/assign-task'),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(child: Text(error!))
              : Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    children: [
                      const Text(
                        'Choose a task to assign to your patient.',
                        style: TextStyle(fontSize: 16),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        //Add a card to the top of this list for a custom task
                        child: ListView.builder(
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
                                    context.push(
                                      '/custom-task-scheduling?patientId=${widget.patientId}',
                                    );
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
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                title: Text(template.name),
                                subtitle: Text(template.description),
                                trailing: const Icon(Icons.arrow_forward_ios),
                                onTap: () {
                                  context.push(
                                    '/pre-defined-task?templateId=${template.id}&patientId=${widget.patientId}',
                                  );
                                },
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}
