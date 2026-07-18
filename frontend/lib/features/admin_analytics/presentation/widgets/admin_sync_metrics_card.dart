import 'package:flutter/material.dart';

import '../../models/admin_analytics_summary_model.dart';

class AdminSyncMetricsCard extends StatelessWidget {
  const AdminSyncMetricsCard({super.key, required this.metrics});

  final SyncMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final successRateText = metrics.successRate == null
        ? '—'
        : '${(metrics.successRate! * 100).toStringAsFixed(1)}%';

    final items = <_SyncMetricItem>[
      _SyncMetricItem('Started', metrics.started, Icons.play_arrow_outlined),
      _SyncMetricItem('Completed', metrics.completed, Icons.check_circle_outline),
      _SyncMetricItem('Failed events', metrics.failedEvents, Icons.error_outline),
      _SyncMetricItem('Attempted', metrics.attempted, Icons.sync),
      _SyncMetricItem('Succeeded', metrics.succeeded, Icons.cloud_done_outlined),
      _SyncMetricItem('Failed', metrics.failed, Icons.cloud_off_outlined),
      _SyncMetricItem('Success rate', successRateText, Icons.percent),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.sync, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Sync Metrics', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Offline sync telemetry from sync_* events',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 720 ? 3 : 2;
                final itemWidth =
                    (constraints.maxWidth - 12 * (columns - 1)) / columns;

                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: items
                      .map(
                        (item) => SizedBox(
                          width: itemWidth,
                          child: _SyncMetricTile(item: item),
                        ),
                      )
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SyncMetricItem {
  const _SyncMetricItem(this.label, this.value, this.icon);

  final String label;
  final dynamic value;
  final IconData icon;
}

class _SyncMetricTile extends StatelessWidget {
  const _SyncMetricTile({required this.item});

  final _SyncMetricItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final display = item.value is int ? '${item.value}' : item.value as String;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(item.icon, color: scheme.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.label,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  display,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
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
