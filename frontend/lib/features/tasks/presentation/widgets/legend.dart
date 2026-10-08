import 'package:care_connect_app/features/tasks/utils/task_type_manager.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// =============================
/// Legend Widget (Display Only)
/// =============================
///
/// Shows task type icons + labels. Does NOT manage add/edit/delete.
/// Parent can provide an [onManage] callback to open LegendEditor.
///
/// Use like:
///   Legend(onManage: () {
///     showDialog(context: context, builder: (_) => const LegendEditor());
///   })
class Legend extends StatelessWidget {
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

  /// Optional: show a "Manage" icon in the header and invoke this callback.
  final VoidCallback? onManage;

  /// Optional: make type chips interactive (used only if you want).
  final void Function(String type)? onTypeTap;
  final void Function(String type)? onTypeLongPress;

  /// Controls whether the header manage button shows. Defaults to true.
  final bool showManageButton;

  const Legend({
    super.key,
    this.onManage,
    this.onTypeTap,
    this.onTypeLongPress,
    this.showManageButton = true,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final manager = context.watch<TaskTypeManager>();
    final taskTypes = manager.taskTypeColors.keys.toList();

    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    t.calendarTaskTypes,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (showManageButton)
                    IconButton(
                      tooltip: t.calendarManageTaskTypes,
                      icon: const Icon(Icons.edit, size: 20),
                      onPressed: onManage,
                    ),
                ],
              ),
            ),
            const Divider(height: 4),

            // Items
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Wrap(
                spacing: 16,
                runSpacing: 8,
                children: taskTypes.map((type) {
                  final color = manager.getColor(type);
                  final icon = manager.getIcon(type);

                  final chip = Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, color: color, size: 18),
                      const SizedBox(width: 4),
                      Text(
                        _localizedTypeName(t, type),
                        style: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.copyWith(color: color),
                      ),
                    ],
                  );

                  if (onTypeTap != null || onTypeLongPress != null) {
                    return InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: onTypeTap == null ? null : () => onTypeTap!(type),
                      onLongPress: onTypeLongPress == null
                          ? null
                          : () => onTypeLongPress!(type),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        child: chip,
                      ),
                    );
                  }
                  return chip;
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
