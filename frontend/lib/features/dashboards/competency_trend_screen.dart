import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../services/api_service.dart';
import '../activities/models/client_activity_model.dart';

/// Competency Trend Dashboard: line chart of average competency per activity per week,
/// overall status badge, and date range filter.
class CompetencyTrendScreen extends StatefulWidget {
  final int clientId;
  final String clientName;

  const CompetencyTrendScreen({
    super.key,
    required this.clientId,
    required this.clientName,
  });

  @override
  State<CompetencyTrendScreen> createState() => _CompetencyTrendScreenState();
}

class _CompetencyTrendScreenState extends State<CompetencyTrendScreen> {
  DateTime? _startDate;
  DateTime? _endDate;
  CompetencyTrendsResponse? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _setDefaultRange();
    _load();
  }

  void _setDefaultRange() {
    final end = DateTime.now();
    final start = end.subtract(const Duration(days: 8 * 7));
    setState(() {
      _endDate = end;
      _startDate = start;
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await ApiService.getCompetencyTrends(
        widget.clientId,
        startDate: _startDate,
        endDate: _endDate,
      );
      if (!mounted) return;
      if (response.statusCode == 200) {
        final map = jsonDecode(response.body) as Map<String, dynamic>;
        setState(() {
          _data = CompetencyTrendsResponse.fromJson(map);
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'Failed to load: ${response.statusCode}';
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _pickDateRange() async {
    final start =
        _startDate ?? DateTime.now().subtract(const Duration(days: 56));
    final end = _endDate ?? DateTime.now();
    final picked = await showDialog<({DateTime start, DateTime end})>(
      context: context,
      builder: (context) => _DateRangePickerDialog(
        initialStart: start,
        initialEnd: end,
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Competency Trends'),
            Text(
              widget.clientName,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.8),
              ),
            ),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError(theme)
              : _buildContent(theme),
    );
  }

  Widget _buildError(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            const SizedBox(height: 16),
            FilledButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(ThemeData theme) {
    final data = _data!;
    if (data.weekLabels.isEmpty && data.activityTrends.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No competency data yet. Log ADL/IADL activities to see trends here.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge,
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildStatusBadge(theme, data.status),
            const SizedBox(height: 16),
            _buildDateRangeFilter(theme),
            const SizedBox(height: 20),
            _buildChart(theme, data),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(ThemeData theme, String status) {
    Color color;
    IconData icon;
    switch (status.toUpperCase()) {
      case 'IMPROVING':
        color = Colors.green;
        icon = Icons.trending_up;
        break;
      case 'DECLINING':
        color = Colors.red;
        icon = Icons.trending_down;
        break;
      default:
        color = theme.colorScheme.outline;
        icon = Icons.trending_flat;
    }
    final label = status == 'IMPROVING'
        ? 'Improving'
        : (status == 'DECLINING' ? 'Declining' : 'Stable');
    return Material(
      color: color.withOpacity(0.15),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(width: 12),
            Text(
              'Overall: $label',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateRangeFilter(ThemeData theme) {
    final startStr = _startDate != null
        ? '${_startDate!.month}/${_startDate!.day}/${_startDate!.year}'
        : '—';
    final endStr = _endDate != null
        ? '${_endDate!.month}/${_endDate!.day}/${_endDate!.year}'
        : '—';
    return Row(
      children: [
        Text('Date range:', style: theme.textTheme.titleSmall),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _pickDateRange,
            icon: const Icon(Icons.calendar_month, size: 18),
            label: Text('$startStr – $endStr'),
          ),
        ),
      ],
    );
  }

  Widget _buildChart(ThemeData theme, CompetencyTrendsResponse data) {
    final weekLabels = data.weekLabels;
    if (weekLabels.isEmpty) {
      return const SizedBox(
        height: 200,
        child: Center(child: Text('No weekly data')),
      );
    }

    final colors = [
      theme.colorScheme.primary,
      Colors.teal,
      Colors.orange,
      Colors.purple,
      Colors.brown,
      Colors.indigo,
    ];

    final lineBars = <LineChartBarData>[];
    for (var i = 0; i < data.activityTrends.length; i++) {
      final trend = data.activityTrends[i];
      final weekToScore = {
        for (var p in trend.dataPoints)
          p.weekStartDate: p.averageCompetencyScore
      };
      final spots = <FlSpot>[];
      for (var wi = 0; wi < weekLabels.length; wi++) {
        final score = weekToScore[weekLabels[wi]];
        if (score != null) {
          spots.add(FlSpot(wi.toDouble(), score));
        }
      }
      if (spots.isEmpty) continue;
      spots.sort((a, b) => a.x.compareTo(b.x));
      final color = colors[i % colors.length];
      lineBars.add(
        LineChartBarData(
          spots: spots,
          isCurved: true,
          color: color,
          barWidth: 2.5,
          dotData: const FlDotData(show: true),
          belowBarData: BarAreaData(show: true, color: color.withOpacity(0.1)),
        ),
      );
    }

    if (lineBars.isEmpty) {
      return const SizedBox(
        height: 200,
        child: Center(child: Text('No activity data in this range')),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Average competency score by week',
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 260,
          child: LineChart(
            LineChartData(
              gridData: FlGridData(
                show: true,
                horizontalInterval: 1,
                getDrawingHorizontalLine: (value) => FlLine(
                  color: theme.colorScheme.outline.withOpacity(0.2),
                  strokeWidth: 1,
                ),
              ),
              titlesData: FlTitlesData(
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: 1,
                    getTitlesWidget: (value, meta) {
                      if (value == value.roundToDouble()) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Text(
                            value.toInt().toString(),
                            style: theme.textTheme.bodySmall,
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                    reservedSize: 28,
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: 1,
                    getTitlesWidget: (value, meta) {
                      final i = value.toInt();
                      if (i >= 0 && i < weekLabels.length) {
                        final label = weekLabels[i];
                        final short =
                            label.length >= 10 ? label.substring(5, 10) : label;
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            short,
                            style: theme.textTheme.bodySmall,
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                ),
              ),
              borderData: FlBorderData(
                show: true,
                border: Border.all(
                    color: theme.colorScheme.outline.withOpacity(0.3)),
              ),
              minX: 0,
              maxX: (weekLabels.length - 1).toDouble(),
              minY: 0,
              maxY: 6,
              lineBarsData: lineBars,
            ),
            duration: const Duration(milliseconds: 200),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            for (var i = 0; i < data.activityTrends.length; i++)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: colors[i % colors.length],
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    data.activityTrends[i].activityName,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

class _DateRangePickerDialog extends StatefulWidget {
  final DateTime initialStart;
  final DateTime initialEnd;

  const _DateRangePickerDialog({
    required this.initialStart,
    required this.initialEnd,
  });

  @override
  State<_DateRangePickerDialog> createState() => _DateRangePickerDialogState();
}

class _DateRangePickerDialogState extends State<_DateRangePickerDialog> {
  late DateTime _start;
  late DateTime _end;

  @override
  void initState() {
    super.initState();
    _start = widget.initialStart;
    _end = widget.initialEnd;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select date range'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: const Text('From'),
            subtitle: Text('${_start.month}/${_start.day}/${_start.year}'),
            trailing: const Icon(Icons.calendar_today),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _start,
                firstDate: DateTime(2020),
                lastDate: DateTime.now(),
              );
              if (picked != null && picked.isBefore(_end))
                setState(() => _start = picked);
            },
          ),
          ListTile(
            title: const Text('To'),
            subtitle: Text('${_end.month}/${_end.day}/${_end.year}'),
            trailing: const Icon(Icons.calendar_today),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _end,
                firstDate: _start,
                lastDate: DateTime.now(),
              );
              if (picked != null) setState(() => _end = picked);
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop((start: _start, end: _end)),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}
