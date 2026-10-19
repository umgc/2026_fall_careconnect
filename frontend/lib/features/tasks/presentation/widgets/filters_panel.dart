import 'package:care_connect_app/features/tasks/utils/task_type_manager.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// =============================
/// FiltersPanel Widget
/// =============================
///
/// Collapsible panel that lets the user filter calendar tasks:
/// - By task type (Medication, Appointment, etc.).
/// - By assigned patient (only if current user is a caregiver).
///
/// Also provides:
/// - A "Clear" button to reset filters.
/// - A "Today" button to jump back to the current date.
///
/// Used at the top of the Calendar Assistant screen.
class FiltersPanel extends StatelessWidget {
  String _localizedTypeName(AppLocalizations t, String type) {
    switch (type.toLowerCase()) {
      case 'medication':
        return t.calendarTypeMedication;
      case 'appointment':
        return t.calendarTypeAppointment;
      case 'exercise':
        return t.calendarTypeExercise;
      case 'general':
        return t.calendarTypeGeneral;
      case 'lab':
        return t.calendarTypeLab;
      case 'pharmacy':
        return t.calendarTypePharmacy;
      case 'imported':
        return t.calendarTypeImported;
      default:
        return type[0].toUpperCase() + type.substring(1);
    }
  }

  /// Whether the panel is expanded (shows filters) or collapsed.
  final bool expanded;

  /// Map of patient IDs to display names (used for caregiver filters).
  final Map<int, String> patientNames;

  /// Currently selected task types.
  final Set<String> selectedTypes;

  /// Currently selected patient IDs.
  final Set<int> selectedPatients;

  /// Callback when the "Clear" button is pressed.
  final VoidCallback onClear;

  /// Callback when a task type chip is toggled.
  final ValueChanged<String> onTypeToggled;

  /// Callback when a patient chip is toggled.
  final ValueChanged<int> onPatientToggled;

  /// Callback when the expand/collapse icon is pressed.
  final VoidCallback onToggleExpanded;

  /// Callback when the "Today" button is pressed.
  final VoidCallback onTodayPressed;

  const FiltersPanel({
    super.key,
    required this.expanded,
    required this.patientNames,
    required this.selectedTypes,
    required this.selectedPatients,
    required this.onClear,
    required this.onTypeToggled,
    required this.onPatientToggled,
    required this.onToggleExpanded,
    required this.onTodayPressed,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final isCaregiver =
        Provider.of<UserProvider>(context, listen: false).user?.isCaregiver ??
        false;

    final manager = context.watch<TaskTypeManager>();
    final types = manager.taskTypeColors.keys.toList();

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // -----------------------
          // Left side: filter card
          // -----------------------
          Flexible(
            fit: FlexFit.tight,
            child: Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                    title: Text(t.calendarFilters),
                    trailing: IconButton(
                      icon: Icon(
                        expanded ? Icons.expand_more : Icons.chevron_right,
                      ),
                      onPressed: onToggleExpanded,
                    ),
                  ),
                  if (expanded) ...[
                    // -----------------------
                    // Task Type Filters
                    // -----------------------
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                      child: Text(
                        t.calendarTaskTypes,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: types.map((type) {
                          final color = manager.getColor(type);
                          final icon = manager.getIcon(type);

                          return FilterChip(
                            avatar: Icon(icon, color: color, size: 18),
                            label: Text(
                              _localizedTypeName(t, type),
                              style: TextStyle(
                                color: selectedTypes.contains(type)
                                    ? color
                                    : null,
                              ),
                            ),
                            selected: selectedTypes.contains(type),
                            selectedColor: color.withOpacity(0.2),
                            onSelected: (_) => onTypeToggled(type),
                            side: BorderSide(color: color, width: 1),
                          );
                        }).toList(),
                      ),
                    ),

                    // -----------------------
                    // Patient Filters
                    // -----------------------
                    if (isCaregiver) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                        child: Text(
                          t.calendarPatients,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: patientNames.entries.map((entry) {
                            return FilterChip(
                              label: Text(entry.value),
                              selected: selectedPatients.contains(entry.key),
                              onSelected: (_) => onPatientToggled(entry.key),
                            );
                          }).toList(),
                        ),
                      ),
                    ],

                    // -----------------------
                    // Clear button
                    // -----------------------
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        icon: const Icon(Icons.clear),
                        label: Text(t.calendarClear),
                        onPressed: onClear,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          // -----------------------
          // Right side: "Today" button
          // -----------------------
          ElevatedButton.icon(
            icon: const Icon(Icons.today),
            label: Text(t.calendarToday),
            onPressed: onTodayPressed,
          ),
        ],
      ),
    );
  }
}
