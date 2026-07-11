import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../models/admin_analytics_summary_model.dart';

class AdminEventCountsChart extends StatelessWidget {
  const AdminEventCountsChart({super.key, required this.events});

  final List<EventNameCount> events;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sorted = List<EventNameCount>.from(events)
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
                Icon(Icons.bar_chart, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Event Counts',
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Telemetry events grouped by name',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (top.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text('No telemetry events in this period.'),
                ),
              )
            else
              SizedBox(
                height: 260,
                child: BarChart(_buildChartData(context, top)),
              ),
          ],
        ),
      ),
    );
  }

  BarChartData _buildChartData(BuildContext context, List<EventNameCount> top) {
    final primary = Theme.of(context).colorScheme.primary;
    final maxCount = top.map((e) => e.count).reduce((a, b) => a > b ? a : b);
    final yMax = (maxCount <= 5) ? 6.0 : maxCount.toDouble() + 2.0;

    final bars = top
        .asMap()
        .entries
        .map(
          (entry) => BarChartGroupData(
            x: entry.key,
            barRods: [
              BarChartRodData(
                toY: entry.value.count.toDouble(),
                width: 18,
                color: primary,
                borderRadius: BorderRadius.circular(4),
              ),
            ],
          ),
        )
        .toList();

    return BarChartData(
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: yMax > 10 ? (yMax / 5).ceilToDouble() : 2,
      ),
      borderData: FlBorderData(show: false),
      barGroups: bars,
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 32,
            interval: yMax > 10 ? (yMax / 5).ceilToDouble() : 2,
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            getTitlesWidget: (value, meta) {
              final idx = value.toInt();
              if (idx < 0 || idx >= top.length) {
                return const SizedBox.shrink();
              }
              final label = top[idx].eventName;
              final short =
                  label.length > 10 ? '${label.substring(0, 10)}…' : label;
              return Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(short, style: const TextStyle(fontSize: 10)),
              );
            },
          ),
        ),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      barTouchData: BarTouchData(
        enabled: true,
        touchTooltipData: BarTouchTooltipData(
          getTooltipItem: (group, groupIndex, rod, rodIndex) {
            final event = top[group.x.toInt()];
            return BarTooltipItem(
              '${event.eventName}\n${event.count}',
              const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            );
          },
        ),
      ),
      maxY: yMax,
    );
  }
}
