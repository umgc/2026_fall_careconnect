import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../models/admin_analytics_summary_model.dart';

class AdminErrorMetricsCard extends StatelessWidget {
  const AdminErrorMetricsCard({
    super.key,
    required this.metrics,
    this.onErrorTap,
  });

  final ErrorMetrics metrics;
  final ValueChanged<EndpointErrorCount>? onErrorTap;

  static const _chartColors = [
    Color(0xFFE57373),
    Color(0xFF64B5F6),
    Color(0xFF81C784),
    Color(0xFFFFB74D),
    Color(0xFFBA68C8),
    Color(0xFF4DB6AC),
    Color(0xFFA1887F),
    Color(0xFF90A4AE),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final buckets = metrics.byEndpointBucket;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_outlined,
                    color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Error Metrics', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'HTTP error telemetry by endpoint bucket · tap for details',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            _TotalErrorsBanner(total: metrics.totalErrors),
            const SizedBox(height: 12),
            if (buckets.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: Text('No errors recorded in this period.')),
              )
            else ...[
              LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth >= 720 && buckets.length > 1) {
                    return SizedBox(
                      height: 200,
                      child: Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: PieChart(
                              _buildPieData(buckets, onErrorTap),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 3,
                            child: _BucketTable(
                              buckets: buckets,
                              onErrorTap: onErrorTap,
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  return _BucketTable(
                    buckets: buckets,
                    onErrorTap: onErrorTap,
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  PieChartData _buildPieData(
    List<EndpointErrorCount> buckets,
    ValueChanged<EndpointErrorCount>? onErrorTap,
  ) {
    final sections = buckets.asMap().entries.map((entry) {
      final color = _chartColors[entry.key % _chartColors.length];
      return PieChartSectionData(
        value: entry.value.count.toDouble(),
        color: color,
        radius: 56,
        title: entry.value.rate > 0.05
            ? '${(entry.value.rate * 100).toStringAsFixed(0)}%'
            : '',
        titleStyle: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      );
    }).toList();

    return PieChartData(
      sections: sections,
      sectionsSpace: 2,
      centerSpaceRadius: 28,
      pieTouchData: PieTouchData(
        enabled: onErrorTap != null,
        touchCallback: (event, response) {
          if (onErrorTap == null ||
              event is! FlTapUpEvent ||
              response?.touchedSection == null) {
            return;
          }
          final idx = response!.touchedSection!.touchedSectionIndex;
          if (idx < 0 || idx >= buckets.length) return;
          onErrorTap(buckets[idx]);
        },
      ),
    );
  }
}

class _TotalErrorsBanner extends StatelessWidget {
  const _TotalErrorsBanner({required this.total});

  final int total;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withOpacity(0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.error.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: scheme.error),
          const SizedBox(width: 12),
          Text(
            'Total errors: $total',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

class _BucketTable extends StatelessWidget {
  const _BucketTable({
    required this.buckets,
    this.onErrorTap,
  });

  final List<EndpointErrorCount> buckets;
  final ValueChanged<EndpointErrorCount>? onErrorTap;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 24,
        headingRowHeight: 40,
        dataRowMinHeight: 40,
        columns: const [
          DataColumn(label: Text('Endpoint')),
          DataColumn(label: Text('Count'), numeric: true),
          DataColumn(label: Text('Share'), numeric: true),
        ],
        rows: buckets
            .map(
              (bucket) => DataRow(
                onSelectChanged: onErrorTap == null
                    ? null
                    : (_) => onErrorTap!(bucket),
                cells: [
                  DataCell(Text(bucket.endpoint.isEmpty ? 'unknown' : bucket.endpoint)),
                  DataCell(Text('${bucket.count}')),
                  DataCell(Text('${(bucket.rate * 100).toStringAsFixed(1)}%')),
                ],
              ),
            )
            .toList(),
      ),
    );
  }
}
