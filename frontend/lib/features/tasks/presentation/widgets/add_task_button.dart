import 'package:flutter/material.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';

/// A responsive "Add Task" button.
/// - Shows a full [ElevatedButton.icon] on wide screens.
/// - Shows an icon-only [IconButton] on compact screens.
/// - Automatically adapts to theme colors (light/dark).
class AddTaskButton extends StatelessWidget {
  final VoidCallback onPressed;

  const AddTaskButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final label = AppLocalizations.of(context)!.calendarAddTask;
    final isCompact = MediaQuery.sizeOf(context).width < 500;

    if (isCompact) {
      // Compact icon-only button for phones
      return IconButton(
        tooltip: label,
        icon: const Icon(Icons.add),
        onPressed: onPressed,
      );
    }

    // Full labeled button for larger screens
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.add, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        textStyle: const TextStyle(fontSize: 14),
      ),
    );
  }
}
