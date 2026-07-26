import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:care_connect_app/features/dashboard/patient_dashboard/models/medication_reminder_item.dart';

/// Medication Reminders Widget
class MedicationRemindersWidget extends StatelessWidget {
  final List<MedicationReminderItem> reminders;
  final void Function(int medicationId)? onMarkTaken;
  final void Function(int medicationId)? onMarkMissed;

  const MedicationRemindersWidget({
    super.key,
    required this.reminders,
    this.onMarkTaken,
    this.onMarkMissed,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    if (reminders.isEmpty) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: theme.shadowColor.withValues(alpha: 0.1),
              spreadRadius: 1,
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: Text(
            t.medicationreminderwidget_noMedReminders,
            style: TextStyle(
              fontSize: 16,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      );
    }

    final visibleReminders = reminders.take(6).toList();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withValues(alpha: 0.1),
            spreadRadius: 1,
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.medication,
                color: theme.colorScheme.secondary,
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                t.medicationreminderwidget_medRemindersTitle,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.secondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...visibleReminders.map(
            (reminder) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: reminder.isTakenForCurrentWindow
                      ? theme.colorScheme.primaryContainer.withValues(alpha: 0.28)
                      : theme.colorScheme.surfaceContainerHighest.withValues(
                          alpha: 0.3,
                        ),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: reminder.isTakenForCurrentWindow
                        ? theme.colorScheme.primary.withValues(alpha: 0.35)
                        : theme.colorScheme.outline.withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            reminder.medicationName,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (reminder.isTakenForCurrentWindow)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              t.medicationreminderwidget_taken,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${reminder.dosage} • ${reminder.frequency}',
                      style: TextStyle(
                        fontSize: 14,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.76),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      reminder.isTakenForCurrentWindow
                          ? '${t.medicationreminderwidget_nextDose} ${_formatScheduledTime(reminder.nextDueAt, t)}'
                          : '${t.medicationreminderwidget_due} ${_formatScheduledTime(reminder.nextDueAt, t)}',
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.62),
                      ),
                    ),
                    if (!reminder.isTakenForCurrentWindow) ...[
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: onMarkTaken == null
                                  ? null
                                  : () => onMarkTaken!(reminder.medicationId),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: theme.colorScheme.tertiary,
                                side: BorderSide(color: theme.colorScheme.tertiary),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: Text(t.medicationreminderwidget_markTaken),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: onMarkMissed == null
                                  ? null
                                  : () => onMarkMissed!(reminder.medicationId),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: theme.colorScheme.error,
                                side: BorderSide(color: theme.colorScheme.error),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: Text(t.medicationreminderwidget_markMissed),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          if (reminders.length > visibleReminders.length)
            Text(
              '+${reminders.length - visibleReminders.length} ${t.medicationreminderwidget_moreMedications}',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.62),
              ),
            ),
        ],
      ),
    );
  }

  /// Formats the scheduled time into a more readable format
  String _formatScheduledTime(DateTime time, AppLocalizations t) {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);

    String dayStr;
    if (time.day == now.day) {
      dayStr = t.medicationreminderwidget_today;
    } else if (time.day == tomorrow.day) {
      dayStr = t.medicationreminderwidget_tomorrow;
    } else {
      dayStr = '${time.month}/${time.day}';
    }

    final hour = (time.hour % 12 == 0) ? 12 : time.hour % 12;
    final amPm = time.hour >= 12 ? 'PM' : 'AM';

    return '$dayStr, $hour:${time.minute.toString().padLeft(2, '0')} $amPm';
  }
}
