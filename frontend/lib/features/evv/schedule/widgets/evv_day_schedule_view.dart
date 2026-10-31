import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../pages/schedule_page.dart';

class EVVDayScheduleView extends StatefulWidget {
  final List<ScheduledVisit> visits;
  final DateTime selectedDate;
  final Function(DateTime)? onDateSelected;
  final Function(ScheduledVisit)? onVisitTap;

  const EVVDayScheduleView({
    super.key,
    required this.visits,
    required this.selectedDate,
    this.onDateSelected,
    this.onVisitTap,
  });

  @override
  State<EVVDayScheduleView> createState() => _EVVDayScheduleViewState();
}

class _EVVDayScheduleViewState extends State<EVVDayScheduleView> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Scroll to current time on init
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToCurrentTime();
    });
  }

  void _scrollToCurrentTime() {
    final now = DateTime.now();
    final minute = now.hour * 60 + now.minute;
    final offset = (minute / 60) * 80; // Approximate pixel offset per hour
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(
        offset.clamp(0, _scrollController.position.maxScrollExtent),
      );
    }
  }

  List<ScheduledVisit> _getVisitsForDay(DateTime date) {
    return widget.visits.where((visit) {
      return visit.scheduledTime.year == date.year &&
          visit.scheduledTime.month == date.month &&
          visit.scheduledTime.day == date.day;
    }).toList()
      ..sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dayVisits = _getVisitsForDay(widget.selectedDate);

    return SingleChildScrollView(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () {
                    widget.onDateSelected?.call(
                      widget.selectedDate.subtract(const Duration(days: 1)),
                    );
                  },
                ),
                Text(
                  DateFormat.yMMMMEEEEd(Localizations.localeOf(context).toString()).format(widget.selectedDate),
                  style: theme.textTheme.headlineSmall,
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () {
                    widget.onDateSelected?.call(
                      widget.selectedDate.add(const Duration(days: 1)),
                    );
                  },
                ),
              ],
            ),
          ),
          _buildTimeSlots(dayVisits, context),
        ],
      ),
    );
  }

  Widget _buildTimeSlots(List<ScheduledVisit> visits, BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.8,
      child: SingleChildScrollView(
        controller: _scrollController,
        child: Column(
          children: List.generate(24, (hour) {
            final visitsAtHour = visits.where((visit) {
              return visit.scheduledTime.hour == hour;
            }).toList();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 8.0,
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 50,
                        child: Text(
                          '${hour.toString().padLeft(2, '0')}:00',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Container(
                          height: 1,
                          color: Colors.grey.shade300,
                        ),
                      ),
                    ],
                  ),
                ),
                ...visitsAtHour.map((visit) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 4.0,
                    ),
                    child: GestureDetector(
                      onTap: () => widget.onVisitTap?.call(visit),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _getPriorityColor(
                            visit.priority,
                          ).withOpacity(0.15),
                          border: Border(
                            left: BorderSide(
                              color: _getPriorityColor(visit.priority),
                              width: 4,
                            ),
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    visit.patientName,
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _getPriorityColor(
                                      visit.priority,
                                    ).withOpacity(0.3),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    visit.priority,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: _getPriorityColor(visit.priority),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              visit.serviceType,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${visit.scheduledTime.hour.toString().padLeft(2, '0')}:${visit.scheduledTime.minute.toString().padLeft(2, '0')} - ${_getEndTime(visit)}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ],
            );
          }),
        ),
      ),
    );
  }

  String _getEndTime(ScheduledVisit visit) {
    final endMinutes = visit.scheduledTime.hour * 60 +
        visit.scheduledTime.minute +
        visit.duration.inMinutes;
    final endHour = endMinutes ~/ 60;
    final endMinute = endMinutes % 60;
    return '${endHour.toString().padLeft(2, '0')}:${endMinute.toString().padLeft(2, '0')}';
  }

  Color _getPriorityColor(String priority) {
    switch (priority.toLowerCase()) {
      case 'high':
        return Colors.red;
      case 'medium':
        return Colors.orange;
      case 'low':
        return Colors.green;
      default:
        return Colors.blue;
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}
