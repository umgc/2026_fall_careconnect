import 'dart:convert';

import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import 'audit_log_models.dart';

class AuditLogScreen extends StatefulWidget {
  final int clientId;
  final String clientName;

  const AuditLogScreen({
    super.key,
    required this.clientId,
    required this.clientName,
  });

  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  bool _isLoading = false;
  String? _error;
  List<AuditLogItem> _items = [];

  DateTime? _startDate;
  DateTime? _endDate;
  String? _typeFilter; // null = all

  @override
  void initState() {
    super.initState();
    _loadAuditLog();
  }

  Future<void> _loadAuditLog() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final resp = await ApiService.getAuditLog(
        widget.clientId,
        startDate: _startDate,
        endDate: _endDate,
        type: _typeFilter,
      );
      if (resp.statusCode != 200) {
        setState(() {
          _isLoading = false;
          _error = 'Failed to load audit log (${resp.statusCode})';
        });
        return;
      }
      final decoded = jsonDecode(resp.body) as List<dynamic>;
      final items = decoded
          .map((e) => AuditLogItem.fromJson(e as Map<String, dynamic>))
          .toList();
      setState(() {
        _isLoading = false;
        _items = items;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'Error loading audit log: $e';
      });
    }
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final initialStart = _startDate ?? now.subtract(const Duration(days: 7));
    final initialEnd = _endDate ?? now;
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
      initialDateRange: DateTimeRange(start: initialStart, end: initialEnd),
    );
    if (range != null) {
      setState(() {
        _startDate =
            DateTime(range.start.year, range.start.month, range.start.day);
        _endDate = DateTime(range.end.year, range.end.month, range.end.day);
      });
      await _loadAuditLog();
    }
  }

  void _clearDateFilter() {
    setState(() {
      _startDate = null;
      _endDate = null;
    });
    _loadAuditLog();
  }

  void _setTypeFilter(String? type) {
    setState(() {
      _typeFilter = type;
    });
    _loadAuditLog();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('Audit Log — ${widget.clientName}'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Read-only audit history of caregiver-entered records.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickDateRange,
                        icon: const Icon(Icons.date_range),
                        label: Text(
                          _startDate == null || _endDate == null
                              ? 'Filter by date range'
                              : '${_startDate!.month}/${_startDate!.day}/${_startDate!.year} - ${_endDate!.month}/${_endDate!.day}/${_endDate!.year}',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (_startDate != null || _endDate != null)
                      IconButton(
                        tooltip: 'Clear date filter',
                        onPressed: _clearDateFilter,
                        icon: const Icon(Icons.clear),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildTypeChip('All', null),
                      _buildTypeChip('Activity logs', 'ACTIVITY_LOG'),
                      _buildTypeChip(
                          'Behavioral incidents', 'BEHAVIORAL_INCIDENT'),
                      _buildTypeChip('Incident reports', 'INCIDENT_REPORT'),
                      _buildTypeChip('Client events', 'CLIENT_EVENT'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _buildBody(),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeChip(String label, String? value) {
    final selected =
        _typeFilter == value || (_typeFilter == null && value == null);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => _setTypeFilter(value),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text(_error!));
    }
    if (_items.isEmpty) {
      return const Center(child: Text('No audit log entries for this client.'));
    }
    return ListView.separated(
      itemCount: _items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = _items[index];
        return ListTile(
          leading: _buildTypeIcon(item.type, Theme.of(context)),
          title: Text(item.summary),
          subtitle: Text(
              '${item.caregiverName} • ${_formatTimestamp(item.createdAt)}'),
          // No trailing actions: read-only view
        );
      },
    );
  }

  Widget _buildTypeIcon(String type, ThemeData theme) {
    IconData icon;
    Color color = theme.colorScheme.primary;
    switch (type) {
      case 'ACTIVITY_LOG':
        icon = Icons.check_circle_outline;
        break;
      case 'BEHAVIORAL_INCIDENT':
        icon = Icons.warning_amber_rounded;
        color = Colors.orange;
        break;
      case 'INCIDENT_REPORT':
        icon = Icons.report_gmailerrorred_outlined;
        color = Colors.red;
        break;
      case 'CLIENT_EVENT':
        icon = Icons.touch_app_outlined;
        break;
      default:
        icon = Icons.article_outlined;
        break;
    }
    return CircleAvatar(
      backgroundColor: color.withOpacity(0.1),
      foregroundColor: color,
      child: Icon(icon, size: 20),
    );
  }

  String _formatTimestamp(DateTime dt) {
    // Simple local datetime formatting; you can replace with intl if desired.
    return '${dt.month}/${dt.day}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
