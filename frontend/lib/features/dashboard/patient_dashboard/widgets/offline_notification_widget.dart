import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Offline Notification Widget
class OfflineNotification extends StatelessWidget {
  final DateTime? lastSynced;

  const OfflineNotification({super.key, this.lastSynced});

  /// Formats the time since the last sync
  String _getTimeSinceSync(AppLocalizations t) {
    if (lastSynced == null) return t.offlinenotiwidget_neverSynced;

    final difference = DateTime.now().difference(lastSynced!);
    if (difference.inMinutes < 60) {
      return '${difference.inMinutes} ${t.offlinenotiwidget_minutesAgo}';
    } else if (difference.inHours < 24) {
      return '${difference.inHours} ${t.offlinenotiwidget_hoursAgo}';
    } else {
      return '${difference.inDays} ${t.offlinenotiwidget_daysAgo}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.inverseSurface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.wifi_off,
            color: theme.colorScheme.primary.withValues(alpha: 0.7),
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.offlinenotiwidget_offlineMode,
                  style: TextStyle(
                    color: theme.colorScheme.onInverseSurface,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${t.offlinenotiwidget_lastSynced} ${_getTimeSinceSync(t)}. ${t.offlinenotiwidget_syncOnReconnect}',
                  style: TextStyle(
                    color: theme.colorScheme.onInverseSurface.withValues(
                      alpha: 0.8,
                    ),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
