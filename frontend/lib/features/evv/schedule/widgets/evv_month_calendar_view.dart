import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../pages/schedule_page.dart';

class EVVMonthCalendarView extends StatefulWidget {
  final List<ScheduledVisit> visits;
  final DateTime selectedDate;
  final Function(DateTime)? onDateSelected;
  final Function(ScheduledVisit)? onVisitTap;
  final Function()? onScheduleNew;

  const EVVMonthCalendarView({
    super.key,
    required this.visits,
    required this.selectedDate,
    this.onDateSelected,
    this.onVisitTap,
    this.onScheduleNew,
  });

  @override
  State<EVVMonthCalendarView> createState() => _EVVMonthCalendarViewState();
}

class _EVVMonthCalendarViewState extends State<EVVMonthCalendarView> {
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
      return visit.scheduledTime.year == date.year &&
          visit.scheduledTime.month == date.month &&
          visit.scheduledTime.day == date.day;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final firstDay = DateTime(_currentMonth.year, _currentMonth.month, 1);
    final lastDay = DateTime(_currentMonth.year, _currentMonth.month + 1, 0);
    final daysInMonth = lastDay.day;
    final firstWeekday = firstDay.weekday; // 1 = Monday, 7 = Sunday

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
                  style: theme.textTheme.headlineSmall,
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Column(
              children: [
                // Weekday headers
                Row(
                  children: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
                      .map((day) => Expanded(
                            child: Center(
                              child: Text(
                                day,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 8),
                // Calendar grid
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    childAspectRatio: 1,
                  ),
                  itemCount: 42, // 6 weeks * 7 days
                  itemBuilder: (context, index) {
                    final dayOffset = index - (firstWeekday - 1);
                    if (dayOffset <= 0 || dayOffset > daysInMonth) {
                      return Container();
                    }

                    final date = DateTime(
                        _currentMonth.year, _currentMonth.month, dayOffset);
                    final visits = _getVisitsForDate(date);
                    final isSelected = date.year == widget.selectedDate.year &&
                        date.month == widget.selectedDate.month &&
                        date.day == widget.selectedDate.day;
                    final isToday = date.year == DateTime.now().year &&
                        date.month == DateTime.now().month &&
                        date.day == DateTime.now().day;

                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          // Update parent's selected date
                        });
                        widget.onDateSelected?.call(date);
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: isSelected
                              ? cs.primaryContainer
                              : (isToday
                                  ? cs.tertiaryContainer.withOpacity(0.3)
                                  : Colors.transparent),
                          border: Border.all(
                            color: isSelected
                                ? cs.primary
                                : (isToday ? cs.tertiary : cs.outlineVariant),
                            width: isSelected ? 2 : 1,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.all(4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              dayOffset.toString(),
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: isSelected
                                    ? cs.onPrimaryContainer
                                    : cs.onSurface,
                              ),
                            ),
                            if (visits.isNotEmpty)
                              Expanded(
                                child: SingleChildScrollView(
                                  child: Column(
                                    children: visits
                                        .take(2)
                                        .map((visit) => Padding(
                                              padding:
                                                  const EdgeInsets.only(top: 2),
                                              child: GestureDetector(
                                                onTap: () => widget.onVisitTap
                                                    ?.call(visit),
                                                child: Container(
                                                  width: double.infinity,
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                    horizontal: 2,
                                                    vertical: 1,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: _getPriorityColor(
                                                            visit.priority)
                                                        .withOpacity(0.7),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            2),
                                                  ),
                                                  child: Text(
                                                    visit.patientName
                                                        .split(' ')
                                                        .first,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      fontSize: 8,
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ))
                                        .toList(),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          if (widget.visits.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32.0),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.event_available,
                      size: 64,
                      color: cs.onSurfaceVariant.withOpacity(0.3),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No visits scheduled',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tap the + button to schedule a new visit',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
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
}
