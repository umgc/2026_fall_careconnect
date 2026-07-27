import 'dart:math' show log, pow;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/feature_trend_model.dart';

class AdminFeatureTrendChart extends StatelessWidget {
  const AdminFeatureTrendChart({super.key, required this.trend});

  final FeatureTrend trend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final points = trend.dailyCounts;

    if (points.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: Text('No usage for this feature in this period.')),
      );
    }

    final maxCount = points.map((p) => p.count).reduce((a, b) => a > b ? a : b);
    final axis = _computeNiceYAxis(maxCount.toDouble());
    final dateFormatter = DateFormat.Md();

    final spots = points
        .asMap()
        .entries
        .map((entry) => FlSpot(entry.key.toDouble(), entry.value.count.toDouble()))
        .toList();

    return SizedBox(
      height: 240,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: (points.length - 1).toDouble(),
          minY: 0,
          maxY: axis.maxY,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: axis.interval,
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 36,
                interval: axis.interval,
                getTitlesWidget: (value, meta) {
                  if ((value % axis.interval).abs() > 0.001 && value != 0) {
                    return const SizedBox.shrink();
                  }
                  return Text(
                    value.toInt().toString(),
                    style: const TextStyle(fontSize: 10),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: points.length > 14 ? 2 : 1,
                getTitlesWidget: (value, meta) {
                  final idx = value.toInt();
                  if (idx < 0 || idx >= points.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      dateFormatter.format(points[idx].date.toLocal()),
                      style: const TextStyle(fontSize: 10),
                    ),
                  );
                },
              ),
            ),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          lineTouchData: LineTouchData(
            enabled: true,
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (touchedSpots) {
                return touchedSpots.map((spot) {
                  final idx = spot.x.toInt();
                  if (idx < 0 || idx >= points.length) {
                    return null;
                  }
                  final point = points[idx];
                  return LineTooltipItem(
                    '${dateFormatter.format(point.date.toLocal())}\n${point.count}',
                    const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  );
                }).toList();
              },
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: theme.colorScheme.primary,
              barWidth: 3,
              dotData: FlDotData(
                show: points.length <= 31,
                getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
                  radius: 3,
                  color: theme.colorScheme.primary,
                  strokeWidth: 1,
                  strokeColor: theme.colorScheme.surface,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                color: theme.colorScheme.primary.withOpacity(0.12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

({double maxY, double interval}) _computeNiceYAxis(
  double maxValue, {
  int divisions = 4,
}) {
  if (maxValue <= 0) {
    return (maxY: divisions.toDouble(), interval: 1);
  }

  final rawStep = maxValue / divisions;
  final magnitude = pow(10, (log(rawStep) / log(10)).floor()).toDouble();
  final normalized = rawStep / magnitude;

  final niceNormalized = normalized <= 1
      ? 1.0
      : normalized <= 2
          ? 2.0
          : normalized <= 5
              ? 5.0
              : 10.0;

  final interval = niceNormalized * magnitude;
  var maxY = interval * divisions;

  while (maxY < maxValue) {
    maxY += interval;
  }

  return (maxY: maxY, interval: interval);
}
