import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:care_connect_app/widgets/app_bar_helper.dart';
import 'package:care_connect_app/services/epic_service.dart';

/// Destination for Epic citation deep links (`/epic/{type}/{id}?patientId=...`) — Epic Phase 2.
///
/// Fetches the mirrored `ehr_resource` for the current user via `GET /api/epic/resource/{type}/{id}`
/// (scoped server-side to the caller) and renders its provenance plus the FHIR payload.
class EpicResourceDetailPage extends StatefulWidget {
  final String resourceType;
  final String resourceId;
  final String? patientId;

  const EpicResourceDetailPage({
    super.key,
    required this.resourceType,
    required this.resourceId,
    this.patientId,
  });

  @override
  State<EpicResourceDetailPage> createState() => _EpicResourceDetailPageState();
}

class _EpicResourceDetailPageState extends State<EpicResourceDetailPage> {
  bool _loading = true;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await EpicService.getResource(widget.resourceType, widget.resourceId);
    if (!mounted) return;
    setState(() {
      _data = data;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBarHelper.createAppBar(context, title: 'Epic Record'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.local_hospital_outlined),
                      const SizedBox(width: 8),
                      Text('From Epic (MyChart)', style: theme.textTheme.titleMedium),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_data == null) ..._notFound(theme) else ..._details(theme),
                ],
              ),
            ),
    );
  }

  List<Widget> _notFound(ThemeData theme) => [
        _row(theme, 'Resource type', widget.resourceType),
        _row(theme, 'FHIR id', widget.resourceId),
        const SizedBox(height: 16),
        Text(
          'This Epic record is no longer available. It may have been removed when Epic was '
          'disconnected, or it has not been synced yet.',
          style: theme.textTheme.bodyMedium,
        ),
      ];

  List<Widget> _details(ThemeData theme) {
    final data = _data!;
    final resource = data['resource'];
    return [
      _row(theme, 'Type', (data['resourceType'] ?? widget.resourceType).toString()),
      if (data['title'] != null) _row(theme, 'Title', data['title'].toString()),
      if (data['status'] != null) _row(theme, 'Status', data['status'].toString()),
      if (data['occurredAt'] != null) _row(theme, 'Date', data['occurredAt'].toString()),
      _row(theme, 'FHIR id', (data['resourceId'] ?? widget.resourceId).toString()),
      if (data['lastSyncedAt'] != null) _row(theme, 'Last synced', data['lastSyncedAt'].toString()),
      const SizedBox(height: 16),
      Text('FHIR resource', style: theme.textTheme.titleSmall),
      const SizedBox(height: 8),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border.all(color: theme.dividerColor),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          resource == null
              ? '(payload unavailable)'
              : const JsonEncoder.withIndent('  ').convert(resource),
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
      ),
    ];
  }

  Widget _row(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
