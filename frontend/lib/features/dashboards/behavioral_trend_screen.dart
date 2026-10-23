import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../services/api_service.dart';
import '../activities/models/client_activity_model.dart';

/// Behavioral incident frequency dashboard: bar chart per week, top keywords, trend.
class BehavioralTrendScreen extends StatefulWidget {
  final int clientId;
  final String clientName;

  const BehavioralTrendScreen({
    super.key,
    required this.clientId,
    required this.clientName,
  });

  @override
  State<BehavioralTrendScreen> createState() => _BehavioralTrendScreenState();
}

class _BehavioralTrendScreenState extends State<BehavioralTrendScreen> {
  DateTime? _startDate;
  DateTime? _endDate;
  BehavioralTrendsResponse? _data;
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
      final response = await ApiService.getBehavioralTrends(
        widget.clientId,
        startDate: _startDate,
        endDate: _endDate,
      );
      if (!mounted) return;
      if (response.statusCode == 200) {
        final map = jsonDecode(response.body) as Map<String, dynamic>;
        setState(() {
          _data = BehavioralTrendsResponse.fromJson(map);
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
            const Text('Behavioral Frequency'),
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
    if (data.weeklyCounts.isEmpty && data.topKeywords.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No behavioral incident data yet. Log behaviors to see trends here.',
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
            _buildTrendIndicator(theme, data.trend),
            const SizedBox(height: 16),
            _buildDateRangeFilter(theme),
            const SizedBox(height: 20),
            _buildBarChart(theme, data),
            if (data.topKeywords.isNotEmpty) ...[
              const SizedBox(height: 24),
              _buildTopKeywords(theme, data.topKeywords),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTrendIndicator(ThemeData theme, String trend) {
    String label;
    Color color;
    IconData icon;
    switch (trend.toUpperCase()) {
      case 'DOWN':
        label = 'Incidents trending down';
        color = Colors.green;
        icon = Icons.trending_down;
        break;
      case 'UP':
        label = 'Incidents trending up';
        color = Colors.orange;
        icon = Icons.trending_up;
        break;
      default:
        label = 'Incidents stable';
        color = theme.colorScheme.outline;
        icon = Icons.trending_flat;
    }
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
              label,
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

  Widget _buildBarChart(ThemeData theme, BehavioralTrendsResponse data) {
    final counts = data.weeklyCounts;
    if (counts.isEmpty) {
      return const SizedBox(
        height: 200,
        child: Center(child: Text('No weekly data')),
      );
    }

    final maxY =
        counts.map((c) => c.incidentCount).fold(0, (a, b) => a > b ? a : b);
    final maxYVal = (maxY < 4) ? 4.0 : (maxY + 1).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Incident count by week',
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 260,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: maxYVal,
              barTouchData: BarTouchData(enabled: true),
              titlesData: FlTitlesData(
                show: true,
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
                      if (i >= 0 && i < counts.length) {
                        final label = counts[i].weekStartDate;
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
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (value) => FlLine(
                  color: theme.colorScheme.outline.withOpacity(0.2),
                  strokeWidth: 1,
                ),
              ),
              borderData: FlBorderData(
                show: true,
                border: Border.all(
                    color: theme.colorScheme.outline.withOpacity(0.3)),
              ),
              barGroups: List.generate(
                counts.length,
                (i) => BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: counts[i].incidentCount.toDouble(),
                      color: theme.colorScheme.primary,
                      width: 20,
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(4)),
                    ),
                  ],
                  showingTooltipIndicators: [0],
                ),
              ),
            ),
            duration: const Duration(milliseconds: 200),
          ),
        ),
      ],
    );
  }

  Widget _buildTopKeywords(ThemeData theme, List<String> keywords) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Most frequently observed behavior keywords',
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ...keywords.map((kw) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Icon(Icons.label_outline,
                      size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    kw.isNotEmpty ? _capitalize(kw) : kw,
                    style: theme.textTheme.bodyLarge,
                  ),
                ],
              ),
            )),
      ],
    );
  }

  String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1).toLowerCase();
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
