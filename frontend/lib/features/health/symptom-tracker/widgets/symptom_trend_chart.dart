import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// One logged symptom sample for [SymptomTrendChart].
class SymptomTrendPoint {
  const SymptomTrendPoint({
    required this.symptomKey,
    required this.severity,
    required this.takenAt,
    this.label,
  });

  final String symptomKey;
  final double severity;
  final DateTime takenAt;
  final String? label;
}

enum SymptomTrendRange { week, month, year }

/// Multi-series symptom severity chart with Week / Month / Year toggle.
class SymptomTrendChart extends StatefulWidget {
  const SymptomTrendChart({
    super.key,
    required this.points,
    this.initialRange = SymptomTrendRange.week,
    this.height = 240,
  });

  /// Convenience constructor for API symptom maps (`symptomKey`, `severity`, `takenAt`).
  factory SymptomTrendChart.fromRawEntries({
    Key? key,
    required List<Map<String, dynamic>> entries,
    SymptomTrendRange initialRange = SymptomTrendRange.week,
    double height = 240,
  }) {
    return SymptomTrendChart(
      key: key,
      points: pointsFromRaw(entries),
      initialRange: initialRange,
      height: height,
    );
  }

  final List<SymptomTrendPoint> points;
  final SymptomTrendRange initialRange;
  final double height;

  static List<SymptomTrendPoint> pointsFromRaw(
    List<Map<String, dynamic>> entries,
  ) {
    final points = <SymptomTrendPoint>[];
    for (final s in entries) {
      final key = (s['symptomKey'] as String?)?.trim() ?? '';
      if (key.isEmpty) continue;
      final takenRaw = s['takenAt'] ?? s['createdAt'];
      DateTime? takenAt;
      if (takenRaw is String) {
        takenAt = DateTime.tryParse(takenRaw);
      } else if (takenRaw is DateTime) {
        takenAt = takenRaw;
      }
      takenAt ??= DateTime.now();
      final severity = (s['severity'] as num?)?.toDouble() ?? 1;
      points.add(
        SymptomTrendPoint(
          symptomKey: key,
          severity: severity,
          takenAt: takenAt,
          label: s['symptomValue'] as String?,
        ),
      );
    }
    return points;
  }

  @override
  State<SymptomTrendChart> createState() => _SymptomTrendChartState();
}

class _SymptomTrendChartState extends State<SymptomTrendChart> {
  late SymptomTrendRange _range;
  final Set<String> _hiddenKeys = <String>{};

  static const _palette = <Color>[
    Color(0xFF1565C0),
    Color(0xFF2E7D32),
    Color(0xFFC62828),
    Color(0xFF6A1B9A),
    Color(0xFF00838F),
    Color(0xFFEF6C00),
  ];

  @override
  void initState() {
    super.initState();
    _range = widget.initialRange;
  }

  DateTime get _rangeStart {
    final now = DateTime.now();
    switch (_range) {
      case SymptomTrendRange.week:
        return now.subtract(const Duration(days: 7));
      case SymptomTrendRange.month:
        return now.subtract(const Duration(days: 30));
      case SymptomTrendRange.year:
        return now.subtract(const Duration(days: 365));
    }
  }

  List<SymptomTrendPoint> get _filtered {
    final start = _rangeStart;
    return widget.points
        .where((p) => !p.takenAt.isBefore(start))
        .toList(growable: false);
  }

  List<String> get _keys {
    final keys = <String>{};
    for (final p in _filtered) {
      if (p.symptomKey.trim().isNotEmpty) keys.add(p.symptomKey);
    }
    final list = keys.toList()..sort();
    return list;
  }

  String get _semanticsSummary {
    final filtered = _filtered;
    if (filtered.isEmpty) {
      return 'No symptom data for the selected ${_range.name} range.';
    }
    final keys = _keys.where((k) => !_hiddenKeys.contains(k)).toList();
    final latest = filtered.reduce(
      (a, b) => a.takenAt.isAfter(b.takenAt) ? a : b,
    );
    return 'Symptom trend for ${_range.name}. '
        '${keys.length} symptom series visible. '
        'Latest: ${latest.symptomKey} severity ${latest.severity.toStringAsFixed(0)} '
        'on ${latest.takenAt.toLocal().toIso8601String().substring(0, 10)}.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _filtered;
    final keys = _keys;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'Symptom trends',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            SegmentedButton<SymptomTrendRange>(
              segments: const [
                ButtonSegment(
                  value: SymptomTrendRange.week,
                  label: Text('Week'),
                ),
                ButtonSegment(
                  value: SymptomTrendRange.month,
                  label: Text('Month'),
                ),
                ButtonSegment(
                  value: SymptomTrendRange.year,
                  label: Text('Year'),
                ),
              ],
              selected: {_range},
              onSelectionChanged: (next) {
                setState(() => _range = next.first);
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (filtered.isEmpty)
          Semantics(
            label: _semanticsSummary,
            child: Container(
              height: widget.height,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'No symptoms logged in this ${_range.name}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),
          )
        else ...[
          if (keys.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (var i = 0; i < keys.length; i++)
                  FilterChip(
                    selected: !_hiddenKeys.contains(keys[i]),
                    label: Text(keys[i]),
                    avatar: CircleAvatar(
                      backgroundColor: _palette[i % _palette.length],
                      radius: 6,
                    ),
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _hiddenKeys.remove(keys[i]);
                        } else {
                          _hiddenKeys.add(keys[i]);
                        }
                      });
                    },
                  ),
              ],
            ),
          const SizedBox(height: 8),
          Semantics(
            label: _semanticsSummary,
            child: SizedBox(
              height: widget.height,
              child: LineChart(_buildChartData(keys, filtered, theme)),
            ),
          ),
        ],
      ],
    );
  }

  LineChartData _buildChartData(
    List<String> keys,
    List<SymptomTrendPoint> filtered,
    ThemeData theme,
  ) {
    final start = _rangeStart;
    final end = DateTime.now();
    final spanMs = end.difference(start).inMilliseconds.clamp(1, 1 << 62);

    final spotsByKey = <String, List<FlSpot>>{};
    for (final key in keys) {
      if (_hiddenKeys.contains(key)) continue;
      final series = filtered.where((p) => p.symptomKey == key).toList()
        ..sort((a, b) => a.takenAt.compareTo(b.takenAt));
      spotsByKey[key] = series
          .map((p) {
            final x = p.takenAt.difference(start).inMilliseconds / spanMs;
            return FlSpot(x, p.severity.clamp(0, 10));
          })
          .toList(growable: false);
    }

    return LineChartData(
      minX: 0,
      maxX: 1,
      minY: 0,
      maxY: 10,
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        getDrawingHorizontalLine: (value) => FlLine(
          color: theme.dividerColor.withValues(alpha: 0.4),
          strokeWidth: 1,
        ),
      ),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 28,
            interval: 2,
            getTitlesWidget: (value, meta) => Text(
              value.toInt().toString(),
              style: theme.textTheme.bodySmall,
            ),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 22,
            interval: 0.5,
            getTitlesWidget: (value, meta) {
              if (value == 0) return const Text('Start');
              if (value == 1) return const Text('Now');
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
      lineBarsData: [
        for (var i = 0; i < keys.length; i++)
          if (!_hiddenKeys.contains(keys[i]) &&
              (spotsByKey[keys[i]]?.isNotEmpty ?? false))
            LineChartBarData(
              spots: spotsByKey[keys[i]]!,
              isCurved: true,
              color: _palette[i % _palette.length],
              barWidth: 3,
              dotData: const FlDotData(show: true),
              belowBarData: BarAreaData(show: false),
            ),
      ],
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipItems: (touched) => touched
              .map(
                (t) => LineTooltipItem(
                  t.y.toStringAsFixed(0),
                  TextStyle(
                    color: theme.colorScheme.onInverseSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}
