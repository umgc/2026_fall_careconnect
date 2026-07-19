import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../models/admin_analytics_summary_model.dart';

class AdminTopFeaturesSection extends StatelessWidget {
  const AdminTopFeaturesSection({super.key, required this.features});

  final List<FeatureUsageCount> features;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sorted = List<FeatureUsageCount>.from(features)
      ..sort((a, b) => b.count.compareTo(a.count));
    final top = sorted.take(8).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.star_outline, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Top Features', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Most-used features from feature_use events',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (top.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('No feature usage in this period.')),
              )
            else ...[
              LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth >= 720) {
                    return SizedBox(
                      height: 220,
                      child: _FeatureBarChart(features: top),
                    );
                  }
                  return _FeatureList(features: top);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FeatureBarChart extends StatelessWidget {
  const _FeatureBarChart({required this.features});

  final List<FeatureUsageCount> features;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final maxCount =
        features.map((f) => f.count).reduce((a, b) => a > b ? a : b);
    final yMax = (maxCount <= 5) ? 6.0 : maxCount.toDouble() + 2.0;

    final bars = features
        .asMap()
        .entries
        .map(
          (entry) => BarChartGroupData(
            x: entry.key,
            barRods: [
              BarChartRodData(
                toY: entry.value.count.toDouble(),
                width: 16,
                color: primary.withOpacity(0.85),
                borderRadius: BorderRadius.circular(4),
              ),
            ],
          ),
        )
        .toList();

    return BarChart(
      BarChartData(
        gridData: FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        barGroups: bars,
        maxY: yMax,
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 28),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                if (idx < 0 || idx >= features.length) {
                  return const SizedBox.shrink();
                }
                final label = features[idx].feature;
                final short =
                    label.length > 12 ? '${label.substring(0, 12)}…' : label;
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(short, style: const TextStyle(fontSize: 10)),
                );
              },
            ),
          ),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        barTouchData: BarTouchData(enabled: true),
      ),
    );
  }
}

class _FeatureList extends StatelessWidget {
  const _FeatureList({required this.features});

  final List<FeatureUsageCount> features;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: features.asMap().entries.map((entry) {
        final rank = entry.key + 1;
        final feature = entry.value;
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            dense: true,
            leading: CircleAvatar(
              radius: 14,
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Text(
                '$rank',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
            title: Text(feature.feature),
            trailing: Text(
              '${feature.count}',
              style: theme.textTheme.titleMedium,
            ),
          ),
        );
      }).toList(),
    );
  }
}
