import 'dart:convert';

import 'package:care_connect_app/features/tasks/models/template_model.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:care_connect_app/features/tasks/models/task_model.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class PreDefinedTaskScreen extends StatefulWidget {
  final int patientId;
  final int templateId;
  final String patientName;
  const PreDefinedTaskScreen(
      {super.key,
      required this.patientId,
      required this.templateId,
      required this.patientName});

  @override
  State<PreDefinedTaskScreen> createState() => _PreDefinedTaskScreenState();
}

class _PreDefinedTaskScreenState extends State<PreDefinedTaskScreen> {
  TimeOfDay? selectedTime;
  String? selectedFrequency;
  int? interval;
  Template? template;
  Task task = Task(
    id: 0,
    name: '',
    date: DateTime.now(),
    notifications: [],
  );

  @override
  void initState() {
    super.initState();
    _getTemplateDetails();
  }

  Future<void> _getTemplateDetails() async {
    try {
      final response = await ApiService.getTaskTemplate(widget.templateId);
      setState(() {
        template = Template.fromJson(json.decode(response.body));
        print('Template loaded: ${template?.name}');
        task = Task(
          id: 0,
          name: template?.name ?? '',
          description: template?.description ?? '',
          date: DateTime.now(),
          timeOfDay: template?.timeOfDay,
          frequency: template?.frequency,
          interval: template?.interval,
          count: template?.count,
          daysOfWeek: template?.daysOfWeek,
          notifications: template?.notifications,
        );
        print('Template loaded: ${task.name}');
      });
    } catch (e) {
      // Handle error
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Predefined Task Scheduling'),
        centerTitle: true,
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            const Text(
              'Create a custom task for your patient.',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 10),
            Expanded(
              // Implements the form for custom task scheduling
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: const Text('Task Name',
                          textAlign: TextAlign.left,
                          style: TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold)),
                    ),
                    TextField(
                      controller: TextEditingController(text: task.name),
                      decoration: InputDecoration(
                        hintText: 'Task Name',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) {
                        setState(() {
                          task.name = value;
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: const Text('Description',
                          textAlign: TextAlign.left,
                          style: TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold)),
                    ),
                    TextField(
                      controller: TextEditingController(text: task.description),
                      decoration: const InputDecoration(
                        hintText: 'Description',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 3,
                      onChanged: (value) {
                        setState(() {
                          task.description = value;
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    // Frequency selection dropdown
                    Align(
                      alignment: Alignment.centerLeft,
                      child: const Text('Frequency',
                          textAlign: TextAlign.left,
                          style: TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold)),
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: task.frequency,
                      items: const [
                        DropdownMenuItem(value: 'DAILY', child: Text('Daily')),
                        DropdownMenuItem(
                            value: 'WEEKLY', child: Text('Weekly')),
                        DropdownMenuItem(
                            value: 'MONTHLY', child: Text('Monthly')),
                        DropdownMenuItem(
                            value: 'YEARLY', child: Text('Yearly')),
                        DropdownMenuItem(
                            value: 'EVERY_WEEK_DAY',
                            child: Text('Every Week Day')),
                      ],
                      onChanged: (value) {
                        setState(() {
                          task.frequency = value;
                        });
                      },
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Interval selection
                    Align(
                      alignment: Alignment.centerLeft,
                      child: const Text('Interval',
                          textAlign: TextAlign.left,
                          style: TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold)),
                    ),
                    TextField(
                      controller:
                          TextEditingController(text: task.interval.toString()),
                      decoration: const InputDecoration(
                        hintText: 'Interval (e.g., 1 day between tasks)',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (value) {
                        setState(() {
                          task.interval = int.tryParse(value) ?? 1;
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    // Count selection dropdown
                    Align(
                      alignment: Alignment.centerLeft,
                      child: const Text('Count',
                          textAlign: TextAlign.left,
                          style: TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold)),
                    ),
                    TextField(
                      controller: TextEditingController(
                          text: task.count?.toString() ?? ''),
                      decoration: const InputDecoration(
                        hintText: 'Number of times to repeat the task',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (value) {
                        setState(() {
                          task.count = int.tryParse(value) ?? 1;
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: const Text('Time',
                          textAlign: TextAlign.left,
                          style: TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold)),
                    ),
                    Card(
                      // margin: const EdgeInsets.symmetric(horizontal: 10),
                      shape: RoundedRectangleBorder(
                        side: const BorderSide(color: Colors.indigo, width: 1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: ListTile(
                        title: Text(task.timeOfDay != null
                            ? task.timeOfDay!.format(context)
                            : 'No time selected'),
                        leading: const Icon(Icons.access_time,
                            color: Colors.indigo, size: 40),
                        onTap: () async {
                          final TimeOfDay? time = await showTimePicker(
                            context: context,
                            initialTime: task.timeOfDay ?? TimeOfDay.now(),
                          );
                          if (time != null) {
                            setState(() {
                              task.timeOfDay = time;
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Date selection
                    Align(
                      alignment: Alignment.centerLeft,
                      child: const Text('Date',
                          textAlign: TextAlign.left,
                          style: TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold)),
                    ),
                    Card(
                      margin: const EdgeInsets.symmetric(horizontal: 10),
                      shape: RoundedRectangleBorder(
                        side: const BorderSide(color: Colors.indigo, width: 1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: ListTile(
                        title: Text(
                          '${task.date.toLocal()}'.split(' ')[0],
                        ),
                        leading: const Icon(Icons.calendar_today,
                            color: Colors.indigo, size: 40),
                        onTap: () async {
                          final DateTime? date = await showDatePicker(
                            context: context,
                            initialDate: task.date,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (date != null) {
                            setState(() {
                              task.date = date;
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Notifications
                    // const SizedBox(height: 20),
                    // SfCalendar(
                    //   view: CalendarView.month,
                    //   initialSelectedDate: DateTime.now(),
                    //   onTap: (CalendarTapDetails details) {
                    //     if (details.targetElement == CalendarElement.calendarCell) {
                    //       // Handle calendar cell tap
                    //     }
                    //   },
                    // ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(8.0),
        child: ElevatedButton(
          onPressed: () async {
            try {
              final result = await ApiService.createTask(
                widget.patientId,
                jsonEncode(task.toJson()),
              );
              if (!mounted) return;
              if (result.headers['x-offline-queued'] == 'true') {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Task queued for sync when internet is restored',
                    ),
                  ),
                );
              }
              context.go('/patient-tasks', extra: {
                'patientId': widget.patientId,
                'patientName': widget.patientName,
              });
            } catch (e) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Error: $e')),
              );
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.indigo,
            padding: const EdgeInsets.symmetric(vertical: 20),
          ),
          child: const Text('Save',
              style: TextStyle(fontSize: 18, color: Colors.white)),
        ),
      ),
    );
  }
}
