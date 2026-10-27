import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:care_connect_app/widgets/app_bar_helper.dart';
import '../services/athena_data_service.dart';

/// Route /athena/{resourceType}/{id}: one athenahealth record with its FHIR
/// resource, like EpicResourceDetailPage does for Epic.
///
/// Reads GET /api/athena/resources/{type}/{id}, scoped server-side to the
/// caller. Inline attachment data has already been removed by the backend.
class AthenaResourceDetailPage extends StatefulWidget {
  final String resourceType;
  final String resourceId;

  /// Injected in tests.
  final AthenaDataService? service;

  const AthenaResourceDetailPage({
    super.key,
    required this.resourceType,
    required this.resourceId,
    this.service,
  });

  @override
  State<AthenaResourceDetailPage> createState() =>
      _AthenaResourceDetailPageState();
}

class _AthenaResourceDetailPageState extends State<AthenaResourceDetailPage> {
  bool _loading = true;
  bool _failed = false;
  Map<String, dynamic>? _data;

  /// Counts reads, so an older read that finishes late is ignored.
  int _read = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final read = ++_read;
    Map<String, dynamic>? data;
    var failed = false;
    try {
      data = await (widget.service ?? AthenaDataService())
          .fetchResource(widget.resourceType, widget.resourceId);
    } catch (_) {
      failed = true;
    }
    if (!mounted || read != _read) return;
    setState(() {
      _data = data;
      _failed = failed;
      _loading = false;
    });
  }

  /// The router reuses this page when only the type or id in the URL
  /// changes (browser history, an edited address): read the new record.
  @override
  void didUpdateWidget(AthenaResourceDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resourceType != widget.resourceType ||
        oldWidget.resourceId != widget.resourceId) {
      // build() follows didUpdateWidget, so no setState here.
      _loading = true;
      _failed = false;
      _data = null;
      _load();
    }
  }

  void _retry() {
    setState(() {
      _loading = true;
      _failed = false;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBarHelper.createAppBar(context, title: 'Health Record'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_failed)
                    ..._loadFailed(theme)
                  else if (_data == null)
                    ..._notFound(theme)
                  else
                    ..._details(theme),
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
          'This record is no longer available. It may have been removed when '
          'its provider was disconnected, or it has not been synced yet.',
          style: theme.textTheme.bodyMedium,
        ),
      ];

  /// The read failed (offline, server error): the record may well still be
  /// there, so don't say it was removed.
  List<Widget> _loadFailed(ThemeData theme) => [
        Text(
          'We couldn\'t load this record. Check your connection and try again.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        TextButton(
          // The light theme's primary is 2.85:1 on white.
          style: TextButton.styleFrom(
            foregroundColor: theme.brightness == Brightness.dark
                ? theme.colorScheme.primary
                : const Color(0xFF006B80),
            minimumSize: const Size(48, 48),
          ),
          onPressed: _retry,
          child: const Text('Try again'),
        ),
      ];

  List<Widget> _details(ThemeData theme) {
    final data = _data!;
    final resource = data['resource'];
    return [
      _row(theme, 'Type',
          (data['resourceType'] ?? widget.resourceType).toString()),
      if (data['category'] != null)
        _row(theme, 'Category', data['category'].toString()),
      if (data['title'] != null) _row(theme, 'Title', data['title'].toString()),
      if (data['status'] != null)
        _row(theme, 'Status', data['status'].toString()),
      if (data['occurredAt'] != null)
        _row(theme, 'Date', data['occurredAt'].toString()),
      _row(theme, 'FHIR id',
          (data['resourceId'] ?? widget.resourceId).toString()),
      if (data['lastSyncedAt'] != null)
        _row(theme, 'Last synced', data['lastSyncedAt'].toString()),
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
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
