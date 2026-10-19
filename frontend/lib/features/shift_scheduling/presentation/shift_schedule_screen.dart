import 'package:flutter/material.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'widgets/calendar_view.dart';
import 'widgets/schedule_visit_dialog.dart';

class CaregiverShiftSchedulingScreen extends StatefulWidget {
  // This screen allows caregivers to input their scheduled shifts to make them
  // visible to other caregivers and patients. It includes fields for recurring shifts,
  // Start Time, End Time, and Days of the Week.
  const CaregiverShiftSchedulingScreen({super.key});

  @override
  State<CaregiverShiftSchedulingScreen> createState() =>
      _CaregiverShiftSchedulingScreenState();
}

class _CaregiverShiftSchedulingScreenState
    extends State<CaregiverShiftSchedulingScreen> {
  TimeOfDay? selectedStartTime;
  TimeOfDay? selectedEndTime;
  var isRecurring = false; // Toggle for recurring shifts

  final Set<int> selectedDayIndexes = {};

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final days = [
      l10n.shiftSunday,
      l10n.shiftMonday,
      l10n.shiftTuesday,
      l10n.shiftWednesday,
      l10n.shiftThursday,
      l10n.shiftFriday,
      l10n.shiftSaturday,
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.shiftTitle),
        centerTitle: true,
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    // toggle for if the shift is Recurring
                    SwitchListTile(
                      title: Text(
                        l10n.shiftRecurring,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      value: isRecurring,
                      onChanged: (value) {
                        setState(() {
                          isRecurring = value;
                        });
                      },
                    ),
                    // Shift Start Time
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        l10n.shiftStartTime,
                        textAlign: TextAlign.left,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Card(
                      // margin: const EdgeInsets.symmetric(horizontal: 10),
                      shape: RoundedRectangleBorder(
                        side: const BorderSide(color: Colors.indigo, width: 1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: ListTile(
                        title: Text(
                          selectedStartTime != null
                              ? selectedStartTime!.format(context)
                              : l10n.shiftNoTimeSelected,
                        ),
                        leading: const Icon(
                          Icons.access_time,
                          color: Colors.indigo,
                          size: 40,
                        ),
                        onTap: () async {
                          final TimeOfDay? time = await showTimePicker(
                            context: context,
                            initialTime: selectedStartTime ??
                                TimeOfDay(
                                  hour: 9,
                                  minute: 0,
                                ), // Default to 9 AM
                          );
                          if (time != null) {
                            setState(() {
                              selectedStartTime = time;
                            });
                          }
                        },
                      ),
                    ),
                    // Shift End Time
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        l10n.shiftEndTime,
                        textAlign: TextAlign.left,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Card(
                      // margin: const EdgeInsets.symmetric(horizontal: 10),
                      shape: RoundedRectangleBorder(
                        side: const BorderSide(color: Colors.indigo, width: 1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: ListTile(
                        title: Text(
                          selectedEndTime != null
                              ? selectedEndTime!.format(context)
                              : l10n.shiftNoTimeSelected,
                        ),
                        leading: const Icon(
                          Icons.access_time,
                          color: Colors.indigo,
                          size: 40,
                        ),
                        onTap: () async {
                          final TimeOfDay? time = await showTimePicker(
                            context: context,
                            initialTime: selectedEndTime ??
                                TimeOfDay(
                                  hour: 17,
                                  minute: 0,
                                ), // Default to 6 PM
                          );
                          if (time != null) {
                            setState(() {
                              selectedEndTime = time;
                            });
                          }
                        },
                      ),
                    ),
                    // Days of the Week Selection
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        l10n.shiftDays,
                        textAlign: TextAlign.left,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Wrap(
                      spacing: 4.0,
                      runSpacing: 2.0,
                      children: [
                        for (var i = 0; i < days.length; i++)
                          ChoiceChip(
                            label: Text(
                              days[i],
                              style: const TextStyle(fontSize: 16),
                            ),
                            selectedColor: Colors.indigo,
                            showCheckmark: false,
                            selected: selectedDayIndexes.contains(i),
                            onSelected: (selected) {
                              setState(() {
                                if (selected) {
                                  selectedDayIndexes.add(i);
                                } else {
                                  selectedDayIndexes.remove(i);
                                }
                              });
                            },
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      // Save Button at the bottom
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(8.0),
        child: ElevatedButton(
          onPressed: () {
            // TODO: Logic to save the custom task
            Navigator.pop(context);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.indigo,
            padding: const EdgeInsets.symmetric(vertical: 20),
          ),
          child: Text(
            l10n.shiftSave,
            style: TextStyle(fontSize: 18, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

class ShiftScheduleScreen extends StatefulWidget {
  final int caregiverId;

  const ShiftScheduleScreen({super.key, required this.caregiverId});

  @override
  State<ShiftScheduleScreen> createState() => _ShiftScheduleScreenState();
}

class _ShiftScheduleScreenState extends State<ShiftScheduleScreen> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          showDialog(
            context: context,
            builder: (context) => ScheduleVisitDialog(
              caregiverId: widget.caregiverId,
              onSave: (visit) {
                // Save visit logic here
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(l10n.shiftVisitSaved(visit.patientName)),
                  ),
                );
              },
            ),
          );
        },
        child: const Icon(Icons.add),
      ),
      body: CalendarView(
        caregiverId: widget.caregiverId,
        onVisitTap: (visit) {
          // Show visit details or edit dialog
        },
      ),
    );
  }
}
