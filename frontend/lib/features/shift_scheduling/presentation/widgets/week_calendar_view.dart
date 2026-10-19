import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:care_connect_app/features/shift_scheduling/models/scheduled_visit_model.dart';

class WeekCalendarView extends StatefulWidget {
  final int caregiverId;
  final List<ScheduledVisit> visits;
  final DateTime selectedDate;
  final Function(DateTime)? onDateSelected;
  final Function(ScheduledVisit)? onVisitTap;

  const WeekCalendarView({
    super.key,
    required this.caregiverId,
    required this.visits,
    required this.selectedDate,
    this.onDateSelected,
    this.onVisitTap,
  });

  @override
  State<WeekCalendarView> createState() => _WeekCalendarViewState();
}

class _WeekCalendarViewState extends State<WeekCalendarView> {
  late DateTime _weekStart;

  @override
  void initState() {
    super.initState();
    _weekStart = widget.selectedDate.subtract(
      Duration(days: widget.selectedDate.weekday - 1),
    );
  }

  List<ScheduledVisit> _getVisitsForDate(DateTime date) {
    return widget.visits.where((visit) {
      return visit.scheduledDate.year == date.year &&
          visit.scheduledDate.month == date.month &&
          visit.scheduledDate.day == date.day;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final weekEnd = _weekStart.add(const Duration(days: 6));

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
                    setState(() {
                      _weekStart = _weekStart.subtract(const Duration(days: 7));
                    });
                    widget.onDateSelected?.call(_weekStart);
                  },
                ),
                Text(
                  '${DateFormat('MMM d').format(_weekStart)} - ${DateFormat('MMM d, yyyy').format(weekEnd)}',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () {
                    setState(() {
                      _weekStart = _weekStart.add(const Duration(days: 7));
                    });
                    widget.onDateSelected?.call(_weekStart);
                  },
                ),
              ],
            ),
          ),
          _buildWeekView(),
        ],
      ),
    );
  }

  Widget _buildWeekView() {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 7,
      itemBuilder: (context, index) {
        final date = _weekStart.add(Duration(days: index));
        final dayVisits = _getVisitsForDate(date);
        final isToday = date.year == DateTime.now().year &&
            date.month == DateTime.now().month &&
            date.day == DateTime.now().day;

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          color: isToday ? Colors.blue.shade50 : Colors.white,
          child: ListTile(
            title: Text(
              DateFormat('EEE, MMM d').format(date),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isToday ? Colors.blue : Colors.black,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: dayVisits.isEmpty
                  ? [const Text('No visits scheduled')]
                  : dayVisits.map((visit) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                        child: GestureDetector(
                          onTap: () => widget.onVisitTap?.call(visit),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: visit.getPriorityColor().withOpacity(0.2),
                              border: Border.all(
                                color: visit.getPriorityColor(),
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        visit.patientName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        '${visit.scheduledTime.format(context)} - ${visit.getEndTime()} (${visit.serviceType})',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: visit.getPriorityColor(),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: Text(
                                    visit.priority,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
            ),
          ),
        );
      },
    );
  }
}
