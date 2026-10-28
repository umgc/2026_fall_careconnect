import 'package:flutter/material.dart';

import '../../utils/recurrence_utils.dart'; // RecurrenceUtils
import '../../utils/task_utils.dart'; // TaskUtils

// =============================
// RecurrenceForm Widget
// =============================

/// RecurrenceForm
/// - Reusable widget for configuring recurrence options on tasks
/// - Supports daily, weekly, monthly, yearly rules
/// - Allows picking start/end dates, interval, days of week, day of month
/// - Can optionally include "apply to entire series" toggle (for editing)
class RecurrenceForm extends StatefulWidget {
  final void Function({
    bool? isRecurring,
    String? recurrenceType,
    List<bool>? daysOfWeek,
    int? interval,
    int? count,
    DateTime? startDate,
    DateTime? endDate,
    int? dayOfMonth,
    bool? applyToSeries,
  }) onChanged;

  final bool initialIsRecurring;
  final String? initialRecurrenceType;
  final List<bool>? initialDaysOfWeek;
  final int? initialInterval;
  final int? initialCount;
  final DateTime? initialStartDate;
  final DateTime? initialEndDate;
  final int? initialDayOfMonth;
  final bool applyToSeries;
  final bool initialApplyToSeries;
  final bool showApplyToSeries;
  final DateTime? anchorStartDate;
  final DateTime? cadenceAnchorDate;

  const RecurrenceForm({
    super.key,
    required this.onChanged,
    this.initialIsRecurring = false,
    this.initialRecurrenceType,
    this.initialDaysOfWeek,
    this.initialInterval,
    this.initialCount,
    this.initialStartDate,
    this.initialEndDate,
    this.initialDayOfMonth,
    this.showApplyToSeries = false,
    this.applyToSeries = false,
    this.initialApplyToSeries = false,
    this.anchorStartDate,
    this.cadenceAnchorDate,
  });

  @override
  State<RecurrenceForm> createState() => _RecurrenceFormState();
}

class _RecurrenceFormState extends State<RecurrenceForm> {
  bool isRecurring = false;
  String? recurrenceType;
  List<bool>? daysOfWeek;
  int? interval;
  int? count;
  DateTime? startDate;
  DateTime? endDate;
  int? dayOfMonth;
  bool applyToSeries = false;

  @override
  void initState() {
    super.initState();
    isRecurring = widget.initialIsRecurring;
    recurrenceType = widget.initialRecurrenceType;
    daysOfWeek = widget.initialDaysOfWeek ?? List.filled(7, false);
    interval = widget.initialInterval;
    count = widget.initialCount;
    //Normalize incoming dates
    startDate = widget.initialStartDate != null
        ? TaskUtils.normalizeDate(widget.initialStartDate!)
        : null;

    endDate = widget.initialEndDate != null
        ? TaskUtils.normalizeDate(widget.initialEndDate!)
        : null;
    dayOfMonth = widget.initialDayOfMonth;
    applyToSeries = widget.initialApplyToSeries;
  }

  // ======================
  // Validation flags
  // ======================

  /// Missing type (recurrence enabled but no type selected)
  bool get isMissingType =>
      isRecurring && (recurrenceType == null || recurrenceType!.isEmpty);

  /// Invalid weekly config (weekly selected but no days picked)
  bool get isWeeklyInvalid =>
      recurrenceType == "Weekly" && !(daysOfWeek?.any((d) => d) ?? false);

  /// Missing end condition (recurrence enabled but no endDate or count)
  bool get isMissingEndCondition =>
      isRecurring &&
      ((endDate == null ||
              (startDate != null && endDate!.isBefore(startDate!))) &&
          (count == null || count! <= 0));

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CheckboxListTile(
          title: const Text("Recurring Task"),
          value: isRecurring,
          onChanged: (val) {
            setState(() => isRecurring = val ?? false);
            widget.onChanged(
              isRecurring: isRecurring,
              recurrenceType: recurrenceType,
              daysOfWeek: daysOfWeek,
              interval: interval,
              count: count,
              startDate: startDate,
              endDate: endDate,
              dayOfMonth: dayOfMonth,
            );
          },
        ),
        if (isRecurring) ...[
          const SizedBox(height: 8),
          // Recurrence type dropdown
          DropdownButtonFormField<String>(
            decoration: const InputDecoration(
              labelText: "Recurrence Type",
              border: OutlineInputBorder(),
              floatingLabelBehavior: FloatingLabelBehavior.always,
            ),
            initialValue: recurrenceType,
            items: [
              "Daily",
              "Weekly",
              "Monthly",
              "Yearly",
            ].map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
            onChanged: (val) {
              setState(() => recurrenceType = val);
              widget.onChanged(
                isRecurring: isRecurring,
                recurrenceType: recurrenceType,
                daysOfWeek: daysOfWeek,
                interval: interval,
                count: count,
                startDate: startDate,
                endDate: endDate,
                dayOfMonth: dayOfMonth,
              );
            },
          ),
          if (isMissingType)
            const Padding(
              padding: EdgeInsets.only(top: 4.0),
              child: Text(
                "Please select a recurrence type",
                style: TextStyle(color: Colors.red, fontSize: 12),
              ),
            ),
          if (widget.showApplyToSeries)
            CheckboxListTile(
              title: const Text("Apply changes to entire series"),
              value: applyToSeries,
              onChanged: (val) {
                setState(() => applyToSeries = val ?? false);
                widget.onChanged(
                  isRecurring: isRecurring,
                  recurrenceType: recurrenceType,
                  daysOfWeek: daysOfWeek,
                  interval: interval,
                  count: count,
                  startDate: startDate,
                  endDate: endDate,
                  dayOfMonth: dayOfMonth,
                  applyToSeries: applyToSeries,
                );
              },
            ),

          // ======================
          // Weekly config
          // ======================
          if (recurrenceType == "Weekly") ...[
            const SizedBox(height: 12),
            const Text("Select Days of Week"),
            Wrap(
              spacing: 8,
              children: List.generate(7, (i) {
                const days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
                return FilterChip(
                  label: Text(days[i]),
                  selected: daysOfWeek?[i] ?? false,
                  onSelected: (selected) {
                    setState(() => daysOfWeek?[i] = selected);
                    widget.onChanged(
                      isRecurring: isRecurring,
                      recurrenceType: recurrenceType,
                      daysOfWeek: daysOfWeek,
                      interval: interval,
                      count: count,
                      startDate: startDate,
                      endDate: endDate,
                      dayOfMonth: dayOfMonth,
                    );
                  },
                );
              }),
            ),
            if (isWeeklyInvalid)
              const Padding(
                padding: EdgeInsets.only(top: 4.0),
                child: Text(
                  "Please select at least one day of the week",
                  style: TextStyle(color: Colors.red, fontSize: 12),
                ),
              ),
          ],

          // ======================
          // Monthly config
          // ======================
          if (recurrenceType == "Monthly") ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Text("Day of Month:"),
                const SizedBox(width: 12),
                DropdownButton<int>(
                  value: dayOfMonth,
                  hint: const Text("Select Day"),
                  items: List.generate(31, (i) => i + 1)
                      .map(
                        (d) => DropdownMenuItem(
                          value: d,
                          child: Text(d.toString()),
                        ),
                      )
                      .toList(),
                  onChanged: (val) {
                    setState(() => dayOfMonth = val);
                    widget.onChanged(
                      isRecurring: isRecurring,
                      recurrenceType: recurrenceType,
                      daysOfWeek: daysOfWeek,
                      interval: interval,
                      count: count,
                      startDate: startDate,
                      endDate: endDate,
                      dayOfMonth: dayOfMonth,
                    );
                  },
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),

          // ======================
          // Start Date Picker
          // ======================
          Row(
            children: [
              Text(
                startDate != null
                    ? "Starts: ${startDate!.toLocal().toString().split(' ')[0]}"
                    : "No start date set",
              ),
              const Spacer(),
              TextButton(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: startDate ?? DateTime.now(),
                    firstDate: DateTime(2000),
                    lastDate: DateTime(DateTime.now().year + 5),
                  );
                  if (picked != null) {
                    setState(() => startDate = TaskUtils.normalizeDate(picked));
                    widget.onChanged(
                      isRecurring: isRecurring,
                      recurrenceType: recurrenceType,
                      daysOfWeek: daysOfWeek,
                      interval: interval,
                      count: count,
                      startDate: startDate,
                      endDate: endDate,
                      dayOfMonth: dayOfMonth,
                    );
                  }
                },
                child: const Text("Pick Start Date"),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // ======================
          // End Date Picker
          // ======================
          if (recurrenceType != "Yearly") ...[
            Row(
              children: [
                Text(
                  endDate != null
                      ? "Ends: ${endDate!.toLocal().toString().split(' ')[0]}"
                      : "No end date set",
                ),
                const Spacer(),
                TextButton(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: endDate ?? startDate ?? DateTime.now(),
                      firstDate:
                          widget.anchorStartDate ?? startDate ?? DateTime.now(),
                      lastDate: DateTime(DateTime.now().year + 5),
                    );
                    if (picked != null) {
                      setState(() => endDate = TaskUtils.normalizeDate(picked));
                      if (recurrenceType != null) {
                        final iv =
                            (interval == null || interval! < 1) ? 1 : interval!;
                        final effectiveStart = widget.anchorStartDate ??
                            startDate ??
                            DateTime.now();

                        count = RecurrenceUtils.calculateCount(
                          startDate: TaskUtils.normalizeDate(effectiveStart),
                          endDate: endDate!,
                          frequency: recurrenceType!,
                          interval: iv,
                          daysOfWeek: daysOfWeek,
                        );
                      }
                      widget.onChanged(
                        isRecurring: isRecurring,
                        recurrenceType: recurrenceType,
                        daysOfWeek: daysOfWeek,
                        interval: interval,
                        count: count,
                        startDate: startDate,
                        endDate: endDate,
                        dayOfMonth: dayOfMonth,
                      );
                    }
                  },
                  child: const Text("Pick End Date"),
                ),
              ],
            ),
          ]
          // ======================
          // Yearly config (end year instead of date)
          // ======================
          else if (recurrenceType == "Yearly") ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Text("Ends in Year:"),
                const SizedBox(width: 12),
                DropdownButton<int>(
                  value: endDate?.year,
                  hint: const Text("Select Year"),
                  items: List.generate(10, (i) => DateTime.now().year + i)
                      .map(
                        (y) => DropdownMenuItem(
                          value: y,
                          child: Text(y.toString()),
                        ),
                      )
                      .toList(),
                  onChanged: (val) {
                    if (val != null && startDate != null) {
                      setState(() {
                        final anchor = widget.cadenceAnchorDate ?? startDate!;
                        final lastDay =
                            DateUtils.getDaysInMonth(val, anchor.month);
                        endDate = DateTime(
                            val, anchor.month, anchor.day.clamp(1, lastDay));
                        count = (val - startDate!.year) + 1; // auto-calc count
                      });
                      widget.onChanged(
                        isRecurring: isRecurring,
                        recurrenceType: recurrenceType,
                        daysOfWeek: daysOfWeek,
                        interval: interval,
                        count: count,
                        startDate: startDate,
                        endDate: endDate,
                        dayOfMonth: dayOfMonth,
                      );
                    }
                  },
                ),
              ],
            ),
          ],

          if (isMissingEndCondition)
            const Padding(
              padding: EdgeInsets.only(top: 4.0),
              child: Text(
                "Please provide an end date of the series",
                style: TextStyle(color: Colors.red, fontSize: 12),
              ),
            ),
        ],
      ],
    );
  }
}
