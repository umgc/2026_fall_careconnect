import 'package:intl/intl.dart';

import '../models/admin_analytics_summary_model.dart';

/// Builds a CSV export for the admin product analytics dashboard.
class AdminAnalyticsCsvExporter {
  const AdminAnalyticsCsvExporter._();

  static String build(
    AdminAnalyticsSummary summary, {
    bool sortFeaturesDescending = true,
  }) {
    final buffer = StringBuffer();
    final periodFormatter = DateFormat('yyyy-MM-dd HH:mm:ss');

    _writeRow(buffer, ['Product Analytics Export']);
    _writeRow(buffer, [
      'Period Start',
      periodFormatter.format(summary.periodStart.toLocal()),
    ]);
    _writeRow(buffer, [
      'Period End',
      periodFormatter.format(summary.periodEnd.toLocal()),
    ]);
    _writeRow(buffer, ['Total Events', '${summary.totalEvents}']);
    _writeRow(buffer, ['Sessions', '${summary.sessionCount}']);
    buffer.writeln();

    _writeRow(buffer, ['Event Counts']);
    _writeRow(buffer, ['Event Name', 'Count']);
    final events = List<EventNameCount>.from(summary.eventCountsByName)
      ..sort((a, b) => b.count.compareTo(a.count));
    for (final event in events) {
      _writeRow(buffer, [event.eventName, '${event.count}']);
    }
    buffer.writeln();

    _writeRow(buffer, ['Top Features']);
    _writeRow(buffer, ['Feature', 'Count']);
    final features = List<FeatureUsageCount>.from(summary.topFeatures)
      ..sort(
        (a, b) => sortFeaturesDescending
            ? b.count.compareTo(a.count)
            : a.count.compareTo(b.count),
      );
    for (final feature in features) {
      _writeRow(buffer, [feature.feature, '${feature.count}']);
    }
    buffer.writeln();

    _writeRow(buffer, ['Sync Metrics']);
    _writeRow(buffer, ['Metric', 'Value']);
    final sync = summary.syncMetrics;
    _writeRow(buffer, ['Started', '${sync.started}']);
    _writeRow(buffer, ['Completed', '${sync.completed}']);
    _writeRow(buffer, ['Failed Events', '${sync.failedEvents}']);
    _writeRow(buffer, ['Attempted', '${sync.attempted}']);
    _writeRow(buffer, ['Succeeded', '${sync.succeeded}']);
    _writeRow(buffer, ['Failed', '${sync.failed}']);
    _writeRow(buffer, [
      'Success Rate',
      sync.successRate == null ? '' : sync.successRate!.toStringAsFixed(4),
    ]);
    buffer.writeln();

    _writeRow(buffer, ['Error Metrics']);
    _writeRow(buffer, ['Total Errors', '${summary.errorMetrics.totalErrors}']);
    buffer.writeln();
    _writeRow(buffer, ['Errors By Endpoint']);
    _writeRow(buffer, ['Endpoint', 'Count', 'Rate']);
    for (final error in summary.errorMetrics.byEndpointBucket) {
      _writeRow(buffer, [
        error.endpoint,
        '${error.count}',
        error.rate.toStringAsFixed(4),
      ]);
    }

    return buffer.toString();
  }

  static void _writeRow(StringBuffer buffer, List<String> values) {
    buffer.writeln(values.map(_escapeCsvField).join(','));
  }

  static String _escapeCsvField(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }
}
