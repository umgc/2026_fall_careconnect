import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:care_connect_app/features/activities/models/client_activity_model.dart';
import 'package:care_connect_app/features/evv/presentation/pages/incident_report_screens.dart';

class IncidentReportHistoryScreen extends StatefulWidget {
  final int clientId;
  final String clientName;

  const IncidentReportHistoryScreen({
    super.key,
    required this.clientId,
    required this.clientName,
  });

  @override
  State<IncidentReportHistoryScreen> createState() =>
      _IncidentReportHistoryScreenState();
}

class _IncidentReportHistoryScreenState
    extends State<IncidentReportHistoryScreen> {
  List<IncidentReportEntry> _reports = [];
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
      final res = await ApiService.getIncidentReports(widget.clientId);
      if (res.statusCode == 200) {
        final list = jsonDecode(res.body) as List<dynamic>?;
        final reports = (list ?? [])
            .map((e) => IncidentReportEntry.fromJson(
                Map<String, dynamic>.from(e as Map)))
            .toList();
        if (mounted) {
          setState(() {
            _reports = reports;
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Incident report history'),
            Text(
              widget.clientName,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.8),
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
                : _reports.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'No incident reports logged yet.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyLarge,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _reports.length,
                        itemBuilder: (context, index) {
                          final r = _reports[index];
                          final dateStr =
                              DateFormat.yMMMd().add_jm().format(r.occurredAt);
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (context) =>
                                        IncidentReportDetailScreen(
                                      clientName: widget.clientName,
                                      report: r,
                                    ),
                                  ),
                                );
                              },
                              title: Text(
                                r.incidentType.replaceAll('_', ' '),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(height: 4),
                                  Text(
                                    dateStr,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  if (r.location.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      r.location,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
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
