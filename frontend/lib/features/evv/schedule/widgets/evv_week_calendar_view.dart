import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../pages/schedule_page.dart';

class EVVWeekCalendarView extends StatefulWidget {
  final List<ScheduledVisit> visits;
  final DateTime selectedDate;
  final Function(DateTime)? onDateSelected;
  final Function(ScheduledVisit)? onVisitTap;

  const EVVWeekCalendarView({
    super.key,
    required this.visits,
    required this.selectedDate,
    this.onDateSelected,
    this.onVisitTap,
  });

  @override
  State<EVVWeekCalendarView> createState() => _EVVWeekCalendarViewState();
}

class _EVVWeekCalendarViewState extends State<EVVWeekCalendarView> {
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
      return visit.scheduledTime.year == date.year &&
          visit.scheduledTime.month == date.month &&
          visit.scheduledTime.day == date.day;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
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
                  style: theme.textTheme.headlineSmall,
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Column(
              children: List.generate(7, (index) {
                final date = _weekStart.add(Duration(days: index));
                final dayVisits = _getVisitsForDate(date);
                final isToday = date.year == DateTime.now().year &&
                    date.month == DateTime.now().month &&
                    date.day == DateTime.now().day;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (index > 0) const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isToday
                            ? cs.tertiaryContainer.withOpacity(0.3)
                            : Colors.transparent,
                        border: Border(
                          bottom: BorderSide(
                            color: isToday ? cs.tertiary : cs.outlineVariant,
                            width: isToday ? 2 : 1,
                          ),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            DateFormat('EEEE, MMM d').format(date),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: isToday ? cs.tertiary : cs.onSurface,
                            ),
                          ),
                          if (dayVisits.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: cs.primaryContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${dayVisits.length} visit${dayVisits.length != 1 ? 's' : ''}',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: cs.onPrimaryContainer,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (dayVisits.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12.0),
                        child: Text(
                          'No visits',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      )
                    else
                      Column(
                        children: dayVisits
                            .map((visit) => Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: GestureDetector(
                                    onTap: () => widget.onVisitTap?.call(visit),
                                    child: Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: _getPriorityColor(visit.priority)
                                            .withOpacity(0.15),
                                        border: Border(
                                          left: BorderSide(
                                            color: _getPriorityColor(
                                                visit.priority),
                                            width: 4,
                                          ),
                                        ),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            visit.patientName,
                                            style: theme.textTheme.titleSmall
                                                ?.copyWith(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                '${visit.scheduledTime.hour.toString().padLeft(2, '0')}:${visit.scheduledTime.minute.toString().padLeft(2, '0')} - ${visit.serviceType}',
                                                style:
                                                    theme.textTheme.bodySmall,
                                              ),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 2,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: _getPriorityColor(
                                                          visit.priority)
                                                      .withOpacity(0.3),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  visit.priority,
                                                  style: theme
                                                      .textTheme.labelSmall
                                                      ?.copyWith(
                                                    color: _getPriorityColor(
                                                        visit.priority),
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ))
                            .toList(),
                      ),
                  ],
                );
              }),
            ),
          ),
          const SizedBox(height: 24),
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
