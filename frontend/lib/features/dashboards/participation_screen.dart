import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

import '../../services/api_service.dart';
import '../activities/models/client_activity_model.dart';

/// Activity participation summary: log counts and last logged by activity, grouped by ADL / IADL.
class ParticipationScreen extends StatefulWidget {
  final int clientId;
  final String clientName;

  const ParticipationScreen({
    super.key,
    required this.clientId,
    required this.clientName,
  });

  @override
  State<ParticipationScreen> createState() => _ParticipationScreenState();
}

class _ParticipationScreenState extends State<ParticipationScreen> {
  DateTime? _startDate;
  DateTime? _endDate;
  ParticipationResponse? _data;
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
    final start = end.subtract(const Duration(days: 4 * 7));
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
      final response = await ApiService.getParticipation(
        widget.clientId,
        startDate: _startDate,
        endDate: _endDate,
      );
      if (!mounted) return;
      if (response.statusCode == 200) {
        final map = jsonDecode(response.body) as Map<String, dynamic>;
        setState(() {
          _data = ParticipationResponse.fromJson(map);
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
        _startDate ?? DateTime.now().subtract(const Duration(days: 28));
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
            const Text('Participation'),
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
    if (data.weeklyCounts.isEmpty && data.activities.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No activity logs in this period. Log ADL or IADL activities to see participation here.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge,
          ),
        ),
      );
    }

    final adl = data.activities.where((a) => a.category == 'ADL').toList();
    final iadl = data.activities.where((a) => a.category == 'IADL').toList();

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
            _buildBarChart(theme, data.weeklyCounts),
            const SizedBox(height: 24),
            if (adl.isNotEmpty) ...[
              _buildSectionHeader(theme, 'ADL'),
              const SizedBox(height: 8),
              _buildActivityList(theme, adl),
              const SizedBox(height: 20),
            ],
            if (iadl.isNotEmpty) ...[
              _buildSectionHeader(theme, 'IADL'),
              const SizedBox(height: 8),
              _buildActivityList(theme, iadl),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(ThemeData theme, String status) {
    Color color;
    IconData icon;
    String label;
    switch (status.toUpperCase()) {
      case 'IMPROVING':
        color = Colors.green;
        icon = Icons.trending_up;
        label = 'Improving';
        break;
      case 'DECLINING':
        color = Colors.red;
        icon = Icons.trending_down;
        label = 'Declining';
        break;
      default:
        color = theme.colorScheme.outline;
        icon = Icons.trending_flat;
        label = 'Stable';
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

  Widget _buildBarChart(ThemeData theme, List<ParticipationWeekCount> counts) {
    if (counts.isEmpty) {
      return const SizedBox(
        height: 200,
        child: Center(child: Text('No weekly data')),
      );
    }

    final maxY =
        counts.map((c) => c.totalLogs).fold(0, (a, b) => a > b ? a : b);
    final maxYVal = (maxY < 4) ? 4.0 : (maxY + 1).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Activity logs per week',
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
                      toY: counts[i].totalLogs.toDouble(),
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

  Widget _buildSectionHeader(ThemeData theme, String category) {
    return Text(
      category,
      style: theme.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.bold,
        color: theme.colorScheme.primary,
      ),
    );
  }

  Widget _buildActivityList(
      ThemeData theme, List<ActivityParticipation> activities) {
    return Card(
      child: Column(
        children: [
          for (var i = 0; i < activities.length; i++)
            _buildActivityRow(theme, activities[i],
                isLast: i == activities.length - 1),
        ],
      ),
    );
  }

  Widget _buildActivityRow(ThemeData theme, ActivityParticipation a,
      {bool isLast = false}) {
    final noRecent = a.noRecentActivity;
    final dateStr = a.lastLoggedAt != null
        ? DateFormat.yMMMd().add_jm().format(a.lastLoggedAt!)
        : '—';

    return Container(
      decoration: BoxDecoration(
        color: noRecent
            ? theme.colorScheme.surfaceContainerHighest.withOpacity(0.5)
            : null,
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(
                  color: theme.colorScheme.outlineVariant.withOpacity(0.5),
                ),
              ),
      ),
      child: ListTile(
        title: Row(
          children: [
            Expanded(
              child: Text(
                a.activityName,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: noRecent
                      ? theme.colorScheme.onSurface.withOpacity(0.7)
                      : null,
                ),
              ),
            ),
            if (noRecent)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'No recent activity',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Text(
                '${a.totalLogsInPeriod} log${a.totalLogsInPeriod == 1 ? '' : 's'} in period',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: noRecent
                      ? theme.colorScheme.onSurface.withOpacity(0.6)
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 16),
              Text(
                'Last: $dateStr',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: noRecent
                      ? theme.colorScheme.onSurface.withOpacity(0.6)
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
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
