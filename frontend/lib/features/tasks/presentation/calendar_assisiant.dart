// =============================
// CalendarAssistantScreen
// =============================

import 'dart:convert';

import 'package:calendar_view/calendar_view.dart';
import 'package:care_connect_app/features/tasks/models/task_model.dart';
import 'package:care_connect_app/features/tasks/utils/recurrence_utils.dart';
import 'package:care_connect_app/features/tasks/utils/task_utils.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:care_connect_app/widgets/app_bar_helper.dart';
import 'package:care_connect_app/widgets/common_drawer.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'widgets/add_task_button.dart';
import 'widgets/calendar_cell.dart';
import 'widgets/event_tile.dart';
import 'widgets/filters_panel.dart';
import 'widgets/import_ics_button.dart';
import 'widgets/legend.dart';
import 'widgets/legend_editor.dart';
import 'widgets/task_form_dialog.dart';
import 'widgets/task_list_day.dart';
import 'widgets/task_list_week.dart';

// View type enum
enum CalendarViewType { month, week, day }

/// =============================
/// Calendar Assistant Screen
/// - Displays tasks in a calendar view
/// - Supports filtering by type and patient
/// - Integrates with TaskFormDialog to add/edit tasks
/// =============================
class CalendarAssistantScreen extends StatefulWidget {
  const CalendarAssistantScreen({super.key});

  @override
  State<CalendarAssistantScreen> createState() =>
      _CalendarAssistantScreenState();
}

class _CalendarAssistantScreenState extends State<CalendarAssistantScreen> {
  bool isLoading = true;
  String? error;
  bool _filtersExpanded = false;
  final Set<String> _selectedTypes = {};
  final Set<int> _selectedPatients = {};
  Map<int, String> patientNames = {};
  DateTime? _selectedDay;

  late EventController<Task> _eventController;

  final _monthKey = GlobalKey<MonthViewState>();
  final _weekKey = GlobalKey<WeekViewState>();
  final _dayKey = GlobalKey<DayViewState>();

  // Current view state
  CalendarViewType _currentView = CalendarViewType.month;

  @override
  void initState() {
    super.initState();
    _eventController = EventController<Task>();
    _selectedDay = DateTime.now();
    _loadTasksFromDb();
  }

  @override
  void dispose() {
    _eventController.dispose();
    super.dispose();
  }

  bool _isQueuedResponse(http.Response response) {
    return response.headers['x-offline-queued'] == 'true';
  }

  ///This function is used across the assistant to query task information from the DB
  Future<void> _loadTasksFromDb() async {
    if (!mounted) return;
    setState(() {
      isLoading = true;
      error = null;
    });

    try {
      final user = Provider.of<UserProvider>(context, listen: false).user;
      if (user == null) {
        setState(() {
          error = AppLocalizations.of(context)!.pleaseLogIn;
          isLoading = false;
        });
        return;
      }

      final List<Task> allTasks = [];

      if (user.isPatient) {
        // Build their display name
        if (user.patientId != null) {
          final safeName = (user.name ?? "").trim();
          patientNames[user.patientId!] =
              safeName.isNotEmpty ? safeName : "Unknown Patient";
        }
        allTasks.addAll(await _fetchTasksForPatient(user.patientId!));
      } else if (user.isCaregiver) {
        patientNames.clear();
        final patientsResponse = await ApiService.getCaregiverPatients(
          user.caregiverId!,
        );
        if (patientsResponse.statusCode == 200) {
          final patients = json.decode(patientsResponse.body);
          for (final patient in patients) {
            final pid = patient['patient']?['id'];
            if (pid != null) {
              patientNames[pid] =
                  "${patient['patient']?['firstName']} ${patient['patient']?['lastName']}";
              allTasks.addAll(await _fetchTasksForPatient(pid));
            }
          }
        }
      }
      // Apply filters
      final filtered = allTasks.where((task) {
        if (_selectedTypes.isNotEmpty &&
            !_selectedTypes.contains(task.taskType ?? "general")) {
          return false;
        }
        if (_selectedPatients.isNotEmpty &&
            (task.assignedPatientId == null ||
                !_selectedPatients.contains(task.assignedPatientId))) {
          return false;
        }
        return true;
      }).toList();

      // Build CalendarEventData list
      final events = filtered.map((task) {
        return CalendarEventData<Task>(
          title: task.name,
          description: task.description,
          date: TaskUtils.normalizeDate(task.date),
          startTime: task.timeOfDay != null
              ? DateTime(
                  task.date.year,
                  task.date.month,
                  task.date.day,
                  task.timeOfDay!.hour,
                  task.timeOfDay!.minute,
                )
              : TaskUtils.normalizeDate(task.date),
          endTime: task.timeOfDay != null
              ? DateTime(
                  task.date.year,
                  task.date.month,
                  task.date.day,
                  task.timeOfDay!.hour,
                  task.timeOfDay!.minute + 30,
                )
              : TaskUtils.normalizeDate(
                  task.date,
                ).add(const Duration(hours: 1)),
          event: task,
        );
      }).toList();

      _eventController
        ..removeWhere((_) => true)
        ..addAll(events);

      setState(() {
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        error = '${AppLocalizations.of(context)!.calendarTask}: $e';
        isLoading = false;
      });
    }
  }

  /// Using V2 of endpoint, fetch the need task information
  Future<List<Task>> _fetchTasksForPatient(int patientId) async {
    final tasks = <Task>[];

    try {
      final response = await ApiService.getPatientTasksV2(patientId);
      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);

        for (final raw in data) {
          final map = TaskUtils.normalizeTaskMap(
            Map<String, dynamic>.from(raw),
          );

          try {
            final baseTask = Task.fromJson(map);
            baseTask.date = TaskUtils.normalizeDate(baseTask.date.toLocal());
            tasks.add(baseTask);
          } catch (e) {
            debugPrint("Error parsing task for patient $patientId: $e");
          }
        }
      } else {
        debugPrint(
          "Failed to fetch tasks for patient $patientId: ${response.statusCode}",
        );
      }
    } catch (e) {
      debugPrint("Exception while fetching tasks for patient $patientId: $e");
    }

    return tasks;
  }

  /// Render the timeline hour labels (respects theme & dark mode)
  Widget _themedTimeLabel(DateTime date) {
    final theme = Theme.of(context);
    final hour12 = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final suffix = date.hour < 12 ? 'AM' : 'PM';
    return Container(
      color: theme.colorScheme.surface,
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 8),
      child: Text(
        '$hour12 $suffix',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurface,
        ),
      ),
    );
  }

  /// Main widget tree for the screen
  /// - Shows loading spinner while fetching
  /// - Renders filter panel, calendar, legend, and task list
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    if (isLoading) {
      return Scaffold(
        drawer: const CommonDrawer(currentRoute: '/calendar'),
        appBar: AppBarHelper.createAppBar(context, title: t.calendarAssistant),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return CalendarControllerProvider<Task>(
      controller: _eventController,
      child: Scaffold(
        drawer: const CommonDrawer(currentRoute: '/calendar'),
        appBar: AppBarHelper.createAppBar(
          context,
          title: t.calendarAssistant,
          additionalActions: [
            AddTaskButton(onPressed: _addTask),
            ImportIcsButton(
              onTasksImported: _loadTasksFromDb,
              patientNames: patientNames, //refresh calendar after import
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              // ------------------
              // Filters Row
              // ------------------
              FiltersPanel(
                expanded: _filtersExpanded,
                patientNames: patientNames,
                selectedTypes: _selectedTypes,
                selectedPatients: _selectedPatients,
                onClear: () {
                  setState(() {
                    _selectedTypes.clear();
                    _selectedPatients.clear();
                  });
                  _loadTasksFromDb();
                },
                onTypeToggled: (type) {
                  setState(() {
                    _selectedTypes.contains(type)
                        ? _selectedTypes.remove(type)
                        : _selectedTypes.add(type);
                  });
                  _loadTasksFromDb();
                },
                onPatientToggled: (id) {
                  setState(() {
                    _selectedPatients.contains(id)
                        ? _selectedPatients.remove(id)
                        : _selectedPatients.add(id);
                  });
                  _loadTasksFromDb();
                },
                onToggleExpanded: () {
                  setState(() => _filtersExpanded = !_filtersExpanded);
                },
                onTodayPressed: () {
                  setState(() {
                    _selectedDay = DateTime.now();
                  });
                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => _animateToSelected(),
                  );
                },
              ),
              // ------------------
              // View switcher
              // ------------------
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    DropdownButton<CalendarViewType>(
                      value: _currentView,
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _currentView = val;
                            _selectedDay ??= DateTime.now();
                            if (val == CalendarViewType.week &&
                                _selectedDay != null) {
                              _selectedDay = TaskUtils.getStartOfWeek(
                                _selectedDay!,
                              );
                            }
                          });
                          WidgetsBinding.instance.addPostFrameCallback(
                            (_) => _animateToSelected(),
                          );
                        }
                      },
                      items: [
                        DropdownMenuItem(
                          value: CalendarViewType.month,
                          child: Text(t.calendarMonthly),
                        ),
                        DropdownMenuItem(
                          value: CalendarViewType.week,
                          child: Text(t.calendarWeekly),
                        ),
                        DropdownMenuItem(
                          value: CalendarViewType.day,
                          child: Text(t.calendarDaily),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // ------------------
              // Calendar widget
              // ------------------
              Expanded(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 500),
                  child: Builder(
                    builder: (context) {
                      final theme = Theme.of(context);

                      switch (_currentView) {
                        case CalendarViewType.month:
                          return MonthView<Task>(
                            key: _monthKey,
                            controller: _eventController,
                            initialMonth: _selectedDay,
                            cellAspectRatio: 1.5,
                            cellBuilder:
                                (date, events, isToday, isInMonth, isWeekend) {
                              return CalendarCell(
                                date: date,
                                events: events,
                                isToday: isToday,
                                isInMonth: isInMonth,
                                isWeekend: isWeekend,
                                isSelected: TaskUtils.isSameDay(
                                  date,
                                  _selectedDay,
                                ),
                              );
                            },
                            headerStyle: HeaderStyle(
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surface,
                              ),
                              headerTextStyle: (theme.textTheme.titleMedium ??
                                      const TextStyle(fontSize: 16))
                                  .copyWith(
                                color: theme.colorScheme.onSurface,
                              ),
                              leftIcon: Icon(
                                Icons.chevron_left,
                                color: theme.colorScheme.onSurface,
                              ),
                              rightIcon: Icon(
                                Icons.chevron_right,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            headerBuilder: (date) {
                              final locale = Localizations.localeOf(context);
                              final formatted = DateFormat.yMMM(
                                locale.toString(),
                              ).format(date);

                              return Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  // Left arrow (previous month)
                                  IconButton(
                                    icon: const Icon(Icons.chevron_left),
                                    color: theme.colorScheme.onSurface,
                                    onPressed: () {
                                      _monthKey.currentState?.previousPage();
                                    },
                                  ),

                                  // Month title
                                  Text(
                                    formatted,
                                    style:
                                        theme.textTheme.titleMedium?.copyWith(
                                      color: theme.colorScheme.onSurface,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),

                                  // Right arrow (next month)
                                  IconButton(
                                    icon: const Icon(Icons.chevron_right),
                                    color: theme.colorScheme.onSurface,
                                    onPressed: () {
                                      _monthKey.currentState?.nextPage();
                                    },
                                  ),
                                ],
                              );
                            },
                            weekDayBuilder: (day) {
                              final labels = [
                                "M",
                                "T",
                                "W",
                                "T",
                                "F",
                                "S",
                                "S",
                              ];
                              return Center(
                                child: Text(
                                  labels[day % 7],
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurface,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              );
                            },
                            onCellTap: (events, date) {
                              setState(() => _selectedDay = date);
                            },
                            onEventTap: (event, date) {
                              final task = event.event;
                              if (task != null) _editTask(task);
                            },
                          );

                        case CalendarViewType.week:
                          return WeekView<Task>(
                            key: _weekKey,
                            controller: _eventController,
                            initialDay: _selectedDay,
                            onPageChange: (date, _) {
                              setState(() {
                                _selectedDay = TaskUtils.getStartOfWeek(date);
                              });
                            },
                            backgroundColor: theme.colorScheme.surface,
                            hourIndicatorSettings: HourIndicatorSettings(
                              color: theme.dividerColor,
                              height: 1,
                              lineStyle: LineStyle.solid,
                            ),
                            halfHourIndicatorSettings: HourIndicatorSettings(
                              color: theme.dividerColor.withOpacity(0.4),
                              height: 1,
                              lineStyle: LineStyle.dashed,
                            ),
                            timeLineWidth: 56,
                            timeLineBuilder: _themedTimeLabel,
                            eventTileBuilder:
                                (date, events, boundary, start, end) =>
                                    EventTile(events: events),
                            headerStyle: HeaderStyle(
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surface,
                              ),
                              headerTextStyle: (theme.textTheme.titleMedium ??
                                      const TextStyle(fontSize: 16))
                                  .copyWith(
                                color: theme.colorScheme.onSurface,
                              ),
                              leftIcon: Icon(
                                Icons.chevron_left,
                                color: theme.colorScheme.onSurface,
                              ),
                              rightIcon: Icon(
                                Icons.chevron_right,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            weekDayBuilder: (date) {
                              final theme = Theme.of(context);

                              final isSelected = TaskUtils.isSameDay(
                                date,
                                _selectedDay,
                              );
                              final isToday = TaskUtils.isSameDay(
                                date,
                                DateTime.now(),
                              );

                              final labels = [
                                "M",
                                "T",
                                "W",
                                "T",
                                "F",
                                "S",
                                "S",
                              ];

                              return GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _selectedDay = date;
                                  });
                                },
                                child: Container(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 2,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: isSelected
                                          ? Colors.green
                                          : (isToday
                                              ? theme.colorScheme.primary
                                              : theme.dividerColor),
                                      width: isSelected ? 2 : 1,
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                    color: theme.colorScheme.surface,
                                  ),
                                  child: Center(
                                    child: Text(
                                      labels[date.weekday - 1],
                                      style:
                                          theme.textTheme.bodyMedium?.copyWith(
                                        color: theme.colorScheme.onSurface,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                            onEventTap: (events, date) {
                              if (events.isNotEmpty) {
                                final task = events.first.event;
                                if (task != null) _editTask(task);
                              }
                            },
                          );

                        case CalendarViewType.day:
                          return DayView<Task>(
                            key: _dayKey,
                            controller: _eventController,
                            initialDay: _selectedDay,
                            onPageChange: (date, _) {
                              setState(() {
                                _selectedDay = date;
                              });
                            },
                            backgroundColor: theme.colorScheme.surface,
                            hourIndicatorSettings: HourIndicatorSettings(
                              color: theme.dividerColor,
                              height: 1,
                              lineStyle: LineStyle.solid,
                            ),
                            halfHourIndicatorSettings: HourIndicatorSettings(
                              color: theme.dividerColor.withOpacity(0.4),
                              height: 1,
                              lineStyle: LineStyle.dashed,
                            ),
                            timeLineWidth: 56,
                            timeLineBuilder: _themedTimeLabel,
                            eventTileBuilder:
                                (date, events, boundary, start, end) =>
                                    EventTile(events: events),
                            headerStyle: HeaderStyle(
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surface,
                              ),
                              headerTextStyle: (theme.textTheme.titleMedium ??
                                      const TextStyle(fontSize: 16))
                                  .copyWith(
                                color: theme.colorScheme.onSurface,
                              ),
                              leftIcon: Icon(
                                Icons.chevron_left,
                                color: theme.colorScheme.onSurface,
                              ),
                              rightIcon: Icon(
                                Icons.chevron_right,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            onEventTap: (events, date) {
                              if (events.isNotEmpty) {
                                final task = events.first.event;
                                if (task != null) _editTask(task);
                              }
                            },
                          );
                      }
                    },
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // ------------------
              // Legend
              // ------------------
              Legend(
                onManage: () {
                  showDialog(
                    context: context,
                    builder: (_) => LegendEditor(
                      usedTaskTypes: _eventController.events
                          .map((e) => e.event?.taskType?.toLowerCase() ?? "")
                          .toSet(),
                    ),
                  );
                },
              ),

              const SizedBox(height: 16),

              // ------------------
              // Task list section (scrollable)
              // ------------------
              if (_selectedDay != null)
                Column(
                  children: [
                    const Divider(thickness: 1),
                    SizedBox(
                      // adjust this to control how tall the list area is
                      height: MediaQuery.of(context).size.height * 0.20,
                      child: _currentView == CalendarViewType.week
                          ? TaskListWeek(
                              events: _eventController.events.where((e) {
                                final weekStart = TaskUtils.getStartOfWeek(
                                  _selectedDay!,
                                );
                                final weekEnd = weekStart.add(
                                  const Duration(days: 7),
                                );
                                return e.date.isAfter(
                                      weekStart.subtract(
                                        const Duration(seconds: 1),
                                      ),
                                    ) &&
                                    e.date.isBefore(weekEnd);
                              }).toList(),
                              patientNames: patientNames,
                              onEdit: _editTask,
                              onDelete: _removeTask,
                            )
                          : TaskListDay(
                              events: _eventController.getEventsOnDay(
                                _selectedDay!,
                              ),
                              patientNames: patientNames,
                              onEdit: _editTask,
                              onDelete: _removeTask,
                            ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _animateToSelected() {
    final target = _selectedDay ?? DateTime.now();
    switch (_currentView) {
      case CalendarViewType.month:
        _monthKey.currentState?.animateToMonth(
          DateTime(target.year, target.month),
        );
        break;
      case CalendarViewType.week:
        // Use start-of-week so the page index lines up
        _weekKey.currentState?.animateToWeek(TaskUtils.getStartOfWeek(target));
        break;
      case CalendarViewType.day:
        _dayKey.currentState?.animateToDate(target);
        break;
    }
  }

  // ==========================
  // TASK CRUD HANDLERS
  // ==========================

  /// Add a new task to the CareConnect system
  /// - Opens the [TaskFormDialog] for user input
  /// - Preloads patient list if caregiver
  /// - Submits new task to backend via [ApiService.createTask]
  /// - On success: refreshes tasks from DB and shows confirmation
  /// - On failure: shows error snackbar
  Future<void> _addTask() async {
    final user = Provider.of<UserProvider>(context, listen: false).user;
    if (user == null) return;
    // Preload patients if caregiver
    List<Map<String, dynamic>> patients = [];
    if (user.isCaregiver) {
      final response = await ApiService.getCaregiverPatients(user.caregiverId!);
      if (response.statusCode == 200) {
        patients = List<Map<String, dynamic>>.from(jsonDecode(response.body));
      }
    }
    // Show dialog
    if (!mounted) return;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => TaskFormDialog(
        isCaregiver: user.isCaregiver,
        patients: patients,
        defaultPatientId: user.isPatient ? user.patientId : null,
        initialDate: _selectedDay,
      ),
    );
    if (result == null) return;
    final List<Task> baseTasks = result['tasks'] != null
        ? (result['tasks'] as List<Task>)
        : (result['task'] as List<Task>);

    if (baseTasks.isEmpty) return;

    try {
      final List<Task> expandedTasks = [];

      for (final Task base in baseTasks) {
        final Object built = RecurrenceUtils.buildTask(baseTask: base);

        if (built is List<Task>) {
          expandedTasks.addAll(built);
        } else if (built is Task) {
          expandedTasks.add(built);
        } else {
          debugPrint(
            "Unexpected return type from buildTask: ${built.runtimeType}",
          );
        }
      }

      // Save each generated task
      var queuedCount = 0;
      var savedCount = 0;
      for (final Task newTask in expandedTasks) {
        final response = await ApiService.createTask(
          newTask.assignedPatientId!,
          jsonEncode(newTask.toJson()),
        );

        if (response.statusCode < 200 || response.statusCode >= 300) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${AppLocalizations.of(context)!.calendarAddTaskFailed}: '
                '${response.statusCode}',
              ),
            ),
          );
          continue;
        }

        savedCount++;
        if (_isQueuedResponse(response)) {
          queuedCount++;
        }
      }

      if (savedCount == 0) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.calendarAddTaskFailed),
          ),
        );
        return;
      }

      await _loadTasksFromDb();
      if (!mounted) return;
      await _maybeShowAppointmentNotificationPreview(expandedTasks);
      if (!mounted) return;
      final offlineQueueMessage = queuedCount == 1
          ? "Task queued for sync when internet is restored"
          : "$queuedCount tasks queued for sync when internet is restored";
      final mixedMessage =
          "${savedCount - queuedCount} saved now, $queuedCount queued for sync";
      final successMessage = expandedTasks.length > 1
          ? "${expandedTasks.length} tasks added successfully"
          : "Task added successfully";
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            queuedCount == 0
                ? successMessage
                : (queuedCount == savedCount
                    ? offlineQueueMessage
                    : mixedMessage),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error adding task: $e")));
    }
  }

  Future<void> _maybeShowAppointmentNotificationPreview(
      List<Task> tasks) async {
    Task? appointmentTask;
    for (final task in tasks) {
      if ((task.taskType ?? '').toLowerCase() == 'appointment') {
        appointmentTask = task;
        break;
      }
    }

    if (appointmentTask == null || appointmentTask.assignedPatientId == null) {
      return;
    }

    try {
      final response = await ApiService.previewTaskNotification(
        appointmentTask.assignedPatientId!,
        jsonEncode(appointmentTask.toJson()),
      );

      if (!mounted || response.statusCode != 200) {
        return;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return;
      }

      final preview = decoded['notificationPreview'];
      if (preview is! Map<String, dynamic>) {
        return;
      }

      final emailRecipient =
          preview['emailRecipient']?.toString() ?? 'Not configured';
      final smsRecipient =
          preview['smsRecipient']?.toString() ?? 'Not configured';
      final emailSubject =
          preview['emailSubject']?.toString() ?? 'Appointment Reminder';
      final emailTextBody = preview['emailTextBody']?.toString() ?? '';
      final smsBody = preview['smsBody']?.toString() ?? '';

      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Appointment Notification Preview'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Email To: $emailRecipient'),
                const SizedBox(height: 6),
                Text('Email Subject: $emailSubject'),
                const SizedBox(height: 6),
                const Text('Email Body:'),
                const SizedBox(height: 4),
                SelectableText(emailTextBody),
                const SizedBox(height: 16),
                Text('SMS To: $smsRecipient'),
                const SizedBox(height: 6),
                const Text('SMS Body:'),
                const SizedBox(height: 4),
                SelectableText(smsBody),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      debugPrint('Failed to load notification preview: $e');
    }
  }

  /// Edit an existing task in the CareConnect system
  /// - Refreshes the latest version of the task from backend
  /// - Resolves series anchor date if task is part of a recurrence
  /// - Opens the [TaskFormDialog] for editing
  /// - Submits updates via [ApiService.editTaskV2]
  /// - Supports updating a single task or entire series
  Future<void> _editTask(Task task) async {
    final user = Provider.of<UserProvider>(context, listen: false).user;
    if (user == null) return;

    if (task.id == null || task.id == -1) {
      debugPrint("Tried to edit a task without a valid ID");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Cannot edit a task without an ID")),
      );
      return;
    }

    // Refresh task from backend
    try {
      final freshResponse = await ApiService.getTaskByIdV2(task.id!);
      if (freshResponse.statusCode == 200) {
        task = Task.fromJson(jsonDecode(freshResponse.body));
        task = task.copyWith(
          date: TaskUtils.normalizeDate(task.date.toLocal()),
        );
      }
    } catch (e) {
      debugPrint("Error refreshing task ${task.id}: $e");
    }

    DateTime seriesAnchorDate = task.date;
    if (task.parentTaskId != null) {
      try {
        final parentResp = await ApiService.getTaskByIdV2(task.parentTaskId!);
        if (parentResp.statusCode == 200) {
          final parent = Task.fromJson(jsonDecode(parentResp.body));
          seriesAnchorDate = TaskUtils.normalizeDate(parent.date.toLocal());
        }
      } catch (_) {}
    }

    // Preload patients if caregiver
    List<Map<String, dynamic>> patients = [];
    if (user.isCaregiver) {
      final response = await ApiService.getCaregiverPatients(user.caregiverId!);
      if (response.statusCode == 200) {
        patients = List<Map<String, dynamic>>.from(jsonDecode(response.body));
      }
    }

    // Show edit form
    if (!mounted) return;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => TaskFormDialog(
        initialTask: task,
        isCaregiver: user.isCaregiver,
        patients: patients,
        defaultPatientId:
            user.isPatient ? user.patientId : task.assignedPatientId,
        initialDate: _selectedDay,
        seriesAnchorDate: seriesAnchorDate,
      ),
    );

    if (result == null) return;

    final applyToSeries = result['applyToSeries'] as bool? ?? false;
    final Object? returned = result['task'];

    // Normalize into a list of Task objects (dialog always returns a list)
    final List<Task> editedTasks = <Task>[];
    if (returned is List<Task>) {
      editedTasks.addAll(returned);
    } else if (returned is Task) {
      editedTasks.add(returned);
    } else {
      debugPrint("Unexpected task return type: ${returned.runtimeType}");
      return;
    }

    // Expand recurrence safely
    final List<Task> expandedTasks = <Task>[];
    for (final Task base in editedTasks) {
      final Object built = RecurrenceUtils.buildTask(baseTask: base);

      if (built is List<Task>) {
        expandedTasks.addAll(built);
      } else if (built is Task) {
        expandedTasks.add(built);
      } else {
        debugPrint(
          " Unexpected type from RecurrenceUtils.buildTask: ${built.runtimeType}",
        );
      }
    }

    try {
      var queuedCount = 0;
      var updatedCount = 0;
      for (final Task updated in expandedTasks) {
        final response = await ApiService.editTaskV2(
          updated.id!,
          updated.toJson(),
          updateSeries: applyToSeries,
        );

        if (response.statusCode < 200 || response.statusCode >= 300) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${AppLocalizations.of(context)!.calendarUpdateTaskFailed}: '
                '${response.statusCode}',
              ),
            ),
          );
          continue;
        }

        updatedCount++;
        if (_isQueuedResponse(response)) {
          queuedCount++;
        }
      }

      if (updatedCount == 0) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.calendarUpdateTaskFailed,
            ),
          ),
        );
        return;
      }

      await _loadTasksFromDb();
      if (!mounted) return;
      final offlineQueueMessage = queuedCount == 1
          ? "Task update queued for sync when internet is restored"
          : "$queuedCount task updates queued for sync when internet is restored";
      final mixedMessage =
          "${updatedCount - queuedCount} updated now, $queuedCount queued for sync";
      final successMessage = applyToSeries
          ? "Series updated successfully"
          : (expandedTasks.length > 1
              ? "${expandedTasks.length} tasks updated successfully"
              : "Task updated successfully");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            queuedCount == 0
                ? successMessage
                : (queuedCount == updatedCount
                    ? offlineQueueMessage
                    : mixedMessage),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error updating task: $e")));
    }
  }

  /// Remove a task from the CareConnect system
  /// - Prompts user for confirmation
  /// - If task is part of a recurrence, offers option to delete entire series
  /// - Calls [ApiService.deleteTaskV2] with appropriate flag
  /// - On success: reloads tasks and shows confirmation
  Future<void> _removeTask(Task task) async {
    bool applyToSeries = false;

    final confirmed = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text("Confirm Delete"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("Are you sure you want to delete '${task.name}'?"),
                  if (task.frequency != null || task.parentTaskId != null)
                    CheckboxListTile(
                      title: const Text("Delete entire series"),
                      value: applyToSeries,
                      onChanged: (val) {
                        setState(() => applyToSeries = val ?? false);
                      },
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: () => Navigator.pop(context, {
                    'confirmed': true,
                    'applyToSeries': applyToSeries,
                  }),
                  child: const Text("Delete"),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed == null || confirmed['confirmed'] != true) return;
    if (!mounted) return;

    final deleteSeries = confirmed['applyToSeries'] as bool? ?? false;

    if (task.id == null || task.id == -1) {
      debugPrint("Tried to remove a task without a valid ID");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Cannot delete a task without an ID")),
      );
      return;
    }

    try {
      final response = await ApiService.deleteTaskV2(
        task.id!,
        deleteSeries: deleteSeries,
      );

      if (response.statusCode == 200 || response.statusCode == 204) {
        await _loadTasksFromDb();
        if (!mounted) return;
        final queuedOffline = _isQueuedResponse(response);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              queuedOffline
                  ? (deleteSeries
                      ? "Task series delete queued for sync when internet is restored"
                      : "Task delete queued for sync when internet is restored")
                  : (deleteSeries
                      ? "Task series deleted"
                      : "Task '${task.name}' deleted"),
            ),
          ),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to delete task: ${response.statusCode}"),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error deleting task: $e")));
    }
  }
}
