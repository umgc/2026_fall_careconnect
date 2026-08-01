import 'package:flutter/material.dart';

enum AdminAnalyticsDetailKind { event, feature, error }

class AdminAnalyticsDetailSheet {
  const AdminAnalyticsDetailSheet._();

  static Future<void> show(
    BuildContext context, {
    required AdminAnalyticsDetailKind kind,
    required String title,
    required int count,
    required int totalEvents,
    required String description,
    int? totalErrors,
    double? shareOfErrors,
  }) {
    final kindLabel = switch (kind) {
      AdminAnalyticsDetailKind.event => 'Telemetry Event',
      AdminAnalyticsDetailKind.feature => 'Feature Usage',
      AdminAnalyticsDetailKind.error => 'HTTP Error Bucket',
    };

    final percentOfTotalEvents = totalEvents > 0
        ? (count / totalEvents) * 100
        : 0.0;

    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        final theme = Theme.of(context);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(kindLabel, style: theme.textTheme.labelLarge),
                const SizedBox(height: 4),
                Text(title, style: theme.textTheme.titleLarge),
                const SizedBox(height: 16),
                _MetricTile(
                  label: 'Count',
                  value: '$count',
                  icon: Icons.numbers,
                ),
                const SizedBox(height: 8),
                _MetricTile(
                  label: '% of total events',
                  value: '${percentOfTotalEvents.toStringAsFixed(1)}%',
                  icon: Icons.pie_chart_outline,
                ),
                if (kind == AdminAnalyticsDetailKind.error &&
                    totalErrors != null &&
                    shareOfErrors != null) ...[
                  const SizedBox(height: 8),
                  _MetricTile(
                    label: '% of total errors',
                    value: '${(shareOfErrors * 100).toStringAsFixed(1)}%',
                    icon: Icons.warning_amber_outlined,
                    subtitle: 'Out of $totalErrors errors in this period',
                  ),
                ],
                const SizedBox(height: 16),
                Text('What this means', style: theme.textTheme.titleSmall),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.icon,
    this.subtitle,
  });

  final String label;
  final String value;
  final IconData icon;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.45),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.bodySmall),
                Text(
                  value,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: theme.textTheme.bodySmall),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
