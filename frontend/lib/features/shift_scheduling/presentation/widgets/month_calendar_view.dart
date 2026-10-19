import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:care_connect_app/features/shift_scheduling/models/scheduled_visit_model.dart';

class MonthCalendarView extends StatefulWidget {
  final int caregiverId;
  final List<ScheduledVisit> visits;
  final DateTime selectedDate;
  final Function(DateTime)? onDateSelected;
  final Function(ScheduledVisit)? onVisitTap;

  const MonthCalendarView({
    super.key,
    required this.caregiverId,
    required this.visits,
    required this.selectedDate,
    this.onDateSelected,
    this.onVisitTap,
  });

  @override
  State<MonthCalendarView> createState() => _MonthCalendarViewState();
}

class _MonthCalendarViewState extends State<MonthCalendarView> {
  late DateTime _currentMonth;

  @override
  void initState() {
    super.initState();
    _currentMonth = DateTime(
      widget.selectedDate.year,
      widget.selectedDate.month,
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
                      _currentMonth = DateTime(
                        _currentMonth.year,
                        _currentMonth.month - 1,
                      );
                    });
                    widget.onDateSelected?.call(_currentMonth);
                  },
                ),
                Text(
                  DateFormat('MMMM yyyy').format(_currentMonth),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () {
                    setState(() {
                      _currentMonth = DateTime(
                        _currentMonth.year,
                        _currentMonth.month + 1,
                      );
                    });
                    widget.onDateSelected?.call(_currentMonth);
                  },
                ),
              ],
            ),
          ),
          _buildDayHeaderRow(),
          _buildCalendarGrid(),
        ],
      ),
    );
  }

  Widget _buildDayHeaderRow() {
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        childAspectRatio: 1.2,
      ),
      itemCount: 7,
      itemBuilder: (context, index) {
        return Center(
          child: Text(
            days[index],
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
        );
      },
    );
  }

  Widget _buildCalendarGrid() {
    final firstDay = DateTime(_currentMonth.year, _currentMonth.month, 1);
    final lastDay = DateTime(_currentMonth.year, _currentMonth.month + 1, 0);
    final daysInMonth = lastDay.day;
    final firstWeekday = firstDay.weekday;

    List<Widget> cells = [];

    // Empty cells before month starts
    for (int i = 1; i < firstWeekday; i++) {
      cells.add(Container());
    }

    // Days of month
    for (int day = 1; day <= daysInMonth; day++) {
      final date = DateTime(_currentMonth.year, _currentMonth.month, day);
      final dayVisits = _getVisitsForDate(date);
      final isToday = date.year == DateTime.now().year &&
          date.month == DateTime.now().month &&
          date.day == DateTime.now().day;

      cells.add(_buildDayCell(date, dayVisits, isToday));
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        childAspectRatio: 1,
      ),
      itemCount: cells.length,
      itemBuilder: (context, index) => cells[index],
    );
  }

  Widget _buildDayCell(
    DateTime date,
    List<ScheduledVisit> visits,
    bool isToday,
  ) {
    final hasConflicts = visits.length > 1 &&
        visits.any(
          (v1) =>
              visits.any((v2) => v1.id != v2.id && _timeRangesOverlap(v1, v2)),
        );

    return GestureDetector(
      onTap: () {
        widget.onDateSelected?.call(date);
      },
      child: Card(
        color: isToday ? Colors.blue.shade50 : Colors.white,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(4.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    date.day.toString(),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isToday ? Colors.blue : Colors.black,
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: visits.take(2).map((visit) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 2.0),
                            child: GestureDetector(
                              onTap: () => widget.onVisitTap?.call(visit),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 2,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: visit.getPriorityColor().withOpacity(
                                        0.7,
                                      ),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                                child: Text(
                                  visit.patientName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 9,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (hasConflicts)
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.warning,
                    size: 10,
                    color: Colors.white,
                  ),
                ),
              ),
            if (visits.length > 2)
              Positioned(
                bottom: 2,
                right: 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Text(
                    '+${visits.length - 2}',
                    style: const TextStyle(fontSize: 8, color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  bool _timeRangesOverlap(ScheduledVisit v1, ScheduledVisit v2) {
    final v1Start = v1.scheduledTime.hour * 60 + v1.scheduledTime.minute;
    final v1End = v1Start + v1.durationMinutes;
    final v2Start = v2.scheduledTime.hour * 60 + v2.scheduledTime.minute;
    final v2End = v2Start + v2.durationMinutes;

    return v1Start < v2End && v2Start < v1End;
  }
}
