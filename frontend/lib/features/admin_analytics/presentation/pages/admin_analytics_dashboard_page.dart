import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../widgets/app_bar_helper.dart';
import '../../../../widgets/responsive_container.dart';
import '../../../../widgets/role_based_drawer.dart';
import '../../data/admin_analytics_api.dart';
import '../../models/admin_analytics_summary_model.dart';
import '../../models/feature_trend_model.dart';
import '../../utils/admin_analytics_csv_exporter.dart';
import '../../utils/admin_analytics_export.dart';
import '../widgets/admin_analytics_detail_sheet.dart';
import '../widgets/admin_analytics_item_descriptions.dart';
import '../widgets/admin_analytics_kpi_row.dart';
import '../widgets/admin_error_metrics_card.dart';
import '../widgets/admin_event_counts_chart.dart';
import '../widgets/admin_feature_trend_section.dart';
import '../widgets/admin_sync_metrics_card.dart';
import '../widgets/admin_top_features_section.dart';

class AdminAnalyticsDashboardPage extends StatefulWidget {
  const AdminAnalyticsDashboardPage({super.key});

  @override
  State<AdminAnalyticsDashboardPage> createState() =>
      _AdminAnalyticsDashboardPageState();
}

class _AdminAnalyticsDashboardPageState
    extends State<AdminAnalyticsDashboardPage> {
  static const int _maxRangeDays = 90;

  final AdminAnalyticsApi _api = const AdminAnalyticsApi();
  AdminAnalyticsSummary? _summary;
  bool _loading = true;
  String? _error;
  late DateTimeRange _selectedRange;
  bool _featuresSortDescending = true;
  String? _selectedTrendFeature;
  FeatureTrend? _featureTrend;
  bool _trendLoading = false;
  String? _trendError;

  @override
  void initState() {
    super.initState();
    _selectedRange = _defaultDateRange();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchSummary());
  }

  DateTimeRange _defaultDateRange() {
    final today = _dateOnly(DateTime.now());
    return DateTimeRange(
      start: today.subtract(const Duration(days: 6)),
      end: today,
    );
  }

  DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  Future<void> _fetchSummary() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final from = _dateOnly(_selectedRange.start);
      final to = _dateOnly(_selectedRange.end).add(const Duration(days: 1));
      final summary = await _api.fetchSummary(from: from, to: to);
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _loading = false;
      });
      _syncSelectedTrendFeature(summary);
      await _fetchFeatureTrend();
    } on AdminAnalyticsApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Error: $e';
        _loading = false;
      });
    }
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: now.subtract(const Duration(days: 365 * 5)),
      lastDate: now,
      initialDateRange: _selectedRange,
      helpText: 'Select analytics period',
    );
    if (picked == null || !mounted) return;

    final inclusiveDays = _dateOnly(picked.end).difference(_dateOnly(picked.start)).inDays + 1;
    if (inclusiveDays > _maxRangeDays) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Date range cannot exceed $_maxRangeDays days'),
        ),
      );
      return;
    }

    setState(() => _selectedRange = picked);
    await _fetchSummary();
  }

  void _syncSelectedTrendFeature(AdminAnalyticsSummary summary) {
    final features = summary.topFeatures;
    if (features.isEmpty) {
      _selectedTrendFeature = null;
      return;
    }

    if (_selectedTrendFeature == null ||
        !features.any((feature) => feature.feature == _selectedTrendFeature)) {
      final sorted = List<FeatureUsageCount>.from(features)
        ..sort((a, b) => b.count.compareTo(a.count));
      _selectedTrendFeature = sorted.first.feature;
    }
  }

  Future<void> _fetchFeatureTrend() async {
    final feature = _selectedTrendFeature;
    if (feature == null) {
      if (!mounted) return;
      setState(() {
        _featureTrend = null;
        _trendLoading = false;
        _trendError = null;
      });
      return;
    }

    setState(() {
      _trendLoading = true;
      _trendError = null;
    });

    try {
      final from = _dateOnly(_selectedRange.start);
      final to = _dateOnly(_selectedRange.end).add(const Duration(days: 1));
      final trend = await _api.fetchFeatureTrends(
        from: from,
        to: to,
        feature: feature,
      );
      if (!mounted) return;
      setState(() {
        _featureTrend = trend;
        _trendLoading = false;
      });
    } on AdminAnalyticsApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _trendError = e.message;
        _trendLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _trendError = 'Error: $e';
        _trendLoading = false;
      });
    }
  }

  String _formatSelectedRangeLabel() {
    final formatter = DateFormat.yMMMd();
    return '${formatter.format(_selectedRange.start)} – '
        '${formatter.format(_selectedRange.end)}';
  }

  String _formatSyncRate(SyncMetrics metrics) {
    if (metrics.successRate == null) return '—';
    return '${(metrics.successRate! * 100).toStringAsFixed(1)}%';
  }

  String _formatPeriod(AdminAnalyticsSummary summary) {
    final formatter = DateFormat.yMMMd();
    return '${formatter.format(summary.periodStart.toLocal())} – '
        '${formatter.format(summary.periodEnd.toLocal())}';
  }

  Future<void> _exportCsv() async {
    final summary = _summary;
    if (summary == null) return;

    try {
      final csv = AdminAnalyticsCsvExporter.build(
        summary,
        sortFeaturesDescending: _featuresSortDescending,
      );
      final fileName =
          'product_analytics_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.csv';
      await exportAdminAnalyticsCsv(csv, fileName, context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('CSV export failed: $e')),
      );
    }
  }

  void _showEventDetail(EventNameCount event, AdminAnalyticsSummary summary) {
    AdminAnalyticsDetailSheet.show(
      context,
      kind: AdminAnalyticsDetailKind.event,
      title: event.eventName,
      count: event.count,
      totalEvents: summary.totalEvents,
      description: AdminAnalyticsItemDescriptions.event(event.eventName),
    );
  }

  void _showFeatureDetail(
    FeatureUsageCount feature,
    AdminAnalyticsSummary summary,
  ) {
    AdminAnalyticsDetailSheet.show(
      context,
      kind: AdminAnalyticsDetailKind.feature,
      title: feature.feature,
      count: feature.count,
      totalEvents: summary.totalEvents,
      description: AdminAnalyticsItemDescriptions.feature(feature.feature),
    );
  }

  void _showErrorDetail(
    EndpointErrorCount error,
    AdminAnalyticsSummary summary,
  ) {
    AdminAnalyticsDetailSheet.show(
      context,
      kind: AdminAnalyticsDetailKind.error,
      title: error.endpoint.isEmpty ? 'unknown' : error.endpoint,
      count: error.count,
      totalEvents: summary.totalEvents,
      totalErrors: summary.errorMetrics.totalErrors,
      shareOfErrors: error.rate,
      description: AdminAnalyticsItemDescriptions.errorEndpoint(error.endpoint),
    );
  }

  Widget _buildDateRangeSelector() {
    return OutlinedButton.icon(
      onPressed: _pickDateRange,
      icon: const Icon(Icons.date_range),
      label: Text(_formatSelectedRangeLabel()),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        alignment: Alignment.centerLeft,
      ),
    );
  }

  Widget _buildContent(AdminAnalyticsSummary summary) {
    final syncRate = _formatSyncRate(summary.syncMetrics);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Product Analytics',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Anonymous telemetry summary (no PII)',
          style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 16),
        _buildDateRangeSelector(),
        const SizedBox(height: 16),
        AdminAnalyticsKpiRow(
          items: [
            AdminKpiSpec(
              title: 'Total Events',
              value: '${summary.totalEvents}',
              icon: Icons.analytics_outlined,
              tone: AdminKpiTone.info,
            ),
            AdminKpiSpec(
              title: 'Sessions',
              value: '${summary.sessionCount}',
              icon: Icons.people_outline,
              tone: AdminKpiTone.neutral,
            ),
            AdminKpiSpec(
              title: 'Sync Success',
              value: syncRate,
              icon: Icons.sync,
              tone: AdminKpiTone.info,
            ),
            AdminKpiSpec(
              title: 'Total Errors',
              value: '${summary.errorMetrics.totalErrors}',
              icon: Icons.error_outline,
              tone: summary.errorMetrics.totalErrors > 0
                  ? AdminKpiTone.error
                  : AdminKpiTone.neutral,
            ),
          ],
        ),
        const SizedBox(height: 16),
        AdminEventCountsChart(
          events: summary.eventCountsByName,
          totalEvents: summary.totalEvents,
          onEventTap: (event) => _showEventDetail(event, summary),
        ),
        const SizedBox(height: 16),
        AdminTopFeaturesSection(
          features: summary.topFeatures,
          sortDescending: _featuresSortDescending,
          onSortToggle: () =>
              setState(() => _featuresSortDescending = !_featuresSortDescending),
          onFeatureTap: (feature) => _showFeatureDetail(feature, summary),
        ),
        const SizedBox(height: 16),
        AdminFeatureTrendSection(
          features: summary.topFeatures,
          selectedFeature: _selectedTrendFeature,
          trend: _featureTrend,
          loading: _trendLoading,
          error: _trendError,
          onFeatureChanged: (feature) {
            setState(() => _selectedTrendFeature = feature);
            _fetchFeatureTrend();
          },
          onRetry: _fetchFeatureTrend,
        ),
        const SizedBox(height: 16),
        AdminSyncMetricsCard(metrics: summary.syncMetrics),
        const SizedBox(height: 16),
        AdminErrorMetricsCard(
          metrics: summary.errorMetrics,
          onErrorTap: (error) => _showErrorDetail(error, summary),
        ),
        const SizedBox(height: 16),
        Text(
          'Period: ${_formatPeriod(summary)}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontStyle: FontStyle.italic,
                color: Colors.grey.shade600,
              ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBarHelper.createAppBar(context, title: 'Product Analytics'),
        drawer: const RoleBasedDrawer(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBarHelper.createAppBar(context, title: 'Product Analytics'),
        drawer: const RoleBasedDrawer(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: Colors.red.shade400),
                const SizedBox(height: 16),
                Text(
                  _error!,
                  style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _fetchSummary,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final summary = _summary;
    if (summary == null) {
      return Scaffold(
        appBar: AppBarHelper.createAppBar(context, title: 'Product Analytics'),
        drawer: const RoleBasedDrawer(),
        body: const Center(child: Text('No analytics data available.')),
      );
    }

    return Scaffold(
      appBar: AppBarHelper.createAppBar(
        context,
        title: 'Product Analytics',
        additionalActions: [
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Export CSV',
            onPressed: _exportCsv,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _fetchSummary,
          ),
        ],
      ),
      drawer: const RoleBasedDrawer(),
      body: RefreshIndicator(
        onRefresh: _fetchSummary,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ResponsiveContainer(
            padding: EdgeInsets.all(
              MediaQuery.of(context).size.width < 400 ? 12 : 16,
            ),
            child: _buildContent(summary),
          ),
        ),
      ),
    );
  }
}
