import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../widgets/app_bar_helper.dart';
import '../../../../widgets/responsive_container.dart';
import '../../../../widgets/role_based_drawer.dart';
import '../../data/admin_analytics_api.dart';
import '../../models/admin_analytics_summary_model.dart';
import '../widgets/admin_analytics_kpi_row.dart';
import '../widgets/admin_error_metrics_card.dart';
import '../widgets/admin_event_counts_chart.dart';
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
  final AdminAnalyticsApi _api = const AdminAnalyticsApi();
  AdminAnalyticsSummary? _summary;
  bool _loading = true;
  String? _error;
  int _selectedDays = 7;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchSummary());
  }

  Future<void> _fetchSummary() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final summary = await _api.fetchSummary(days: _selectedDays);
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _loading = false;
      });
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

  void _onDaysChanged(int days) {
    if (_selectedDays == days) return;
    setState(() => _selectedDays = days);
    _fetchSummary();
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

  Widget _buildFilterChips() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = MediaQuery.of(context).size.width;

        return Wrap(
          spacing: screenWidth < 400 ? 6 : 8,
          runSpacing: 6,
          children: [7, 14, 21, 30].map((days) {
            final isSelected = _selectedDays == days;
            return FilterChip(
              label: Text(
                screenWidth < 400 ? '${days}d' : '$days days',
                style: TextStyle(fontSize: screenWidth < 400 ? 12 : 14),
              ),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) _onDaysChanged(days);
              },
              selectedColor:
                  Theme.of(context).colorScheme.primary.withOpacity(0.15),
              checkmarkColor: Theme.of(context).colorScheme.primary,
              labelStyle: TextStyle(
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey.shade600,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                fontSize: screenWidth < 400 ? 12 : 14,
              ),
              backgroundColor: Colors.grey.shade100,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey.shade300,
                ),
              ),
              padding: EdgeInsets.symmetric(
                horizontal: screenWidth < 400 ? 8 : 12,
                vertical: screenWidth < 400 ? 4 : 8,
              ),
            );
          }).toList(),
        );
      },
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
        _buildFilterChips(),
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
        AdminEventCountsChart(events: summary.eventCountsByName),
        const SizedBox(height: 16),
        AdminTopFeaturesSection(features: summary.topFeatures),
        const SizedBox(height: 16),
        AdminSyncMetricsCard(metrics: summary.syncMetrics),
        const SizedBox(height: 16),
        AdminErrorMetricsCard(metrics: summary.errorMetrics),
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
