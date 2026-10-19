import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:care_connect_app/features/activities/models/client_activity_model.dart';
import 'package:intl/intl.dart';

/// Screen showing activity log history for a client. Opened from ADL & IADL Management hub.
class ActivityLogHistoryScreen extends StatefulWidget {
  final int clientId;
  final String clientName;

  const ActivityLogHistoryScreen({
    super.key,
    required this.clientId,
    required this.clientName,
  });

  @override
  State<ActivityLogHistoryScreen> createState() =>
      _ActivityLogHistoryScreenState();
}

class _ActivityLogHistoryScreenState extends State<ActivityLogHistoryScreen> {
  List<ActivityLogEntry> _logs = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ApiService.getActivityLogs(widget.clientId, limit: 100);
      if (res.statusCode == 200) {
        final list = jsonDecode(res.body) as List<dynamic>?;
        final logs = (list ?? [])
            .map((e) =>
                ActivityLogEntry.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
        if (mounted) {
          setState(() {
            _logs = logs;
            _loading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _error = 'Failed to load: ${res.statusCode}';
            _loading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Error: $e';
          _loading = false;
        });
      }
    }
  }

  static String _satisfactionEmoji(int? r) {
    if (r == null) return '';
    if (r == 1) return '😫';
    if (r == 2) return '😕';
    if (r == 3) return '😐';
    if (r == 4) return '🙂';
    if (r == 5) return '😄';
    return '';
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
            const Text('Activity log history'),
            Text(
              widget.clientName,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!, textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: _load,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  )
                : _logs.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'No activity logs yet. Log activities from ADL or IADL screens.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyLarge,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _logs.length,
                        itemBuilder: (context, index) {
                          final log = _logs[index];
                          final dateStr =
                              DateFormat.yMMMd().add_jm().format(log.createdAt);
                          final satisfaction =
                              _satisfactionEmoji(log.satisfactionRating);
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              title: Text(
                                log.activityName?.isNotEmpty == true
                                    ? log.activityName!
                                    : 'Activity #${log.activityId}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(height: 4),
                                  Text('Competency: ${log.competencyScore}'),
                                  if (satisfaction.isNotEmpty)
                                    Text('Satisfaction: $satisfaction'),
                                  if (log.notes != null &&
                                      log.notes!.isNotEmpty)
                                    Text('Notes: ${log.notes}'),
                                  const SizedBox(height: 4),
                                  Text(
                                    dateStr,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                              isThreeLine: true,
                            ),
                          );
                        },
                      ),
      ),
    );
  }
}
