import 'package:flutter/material.dart';

import '../../models/admin_analytics_summary_model.dart';
import '../../models/feature_trend_model.dart';
import 'admin_feature_trend_chart.dart';

class AdminFeatureTrendSection extends StatelessWidget {
  const AdminFeatureTrendSection({
    super.key,
    required this.features,
    required this.selectedFeature,
    required this.trend,
    required this.loading,
    this.error,
    required this.onFeatureChanged,
    required this.onRetry,
  });

  final List<FeatureUsageCount> features;
  final String? selectedFeature;
  final FeatureTrend? trend;
  final bool loading;
  final String? error;
  final ValueChanged<String> onFeatureChanged;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.show_chart, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Feature Trend', style: theme.textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Daily feature_use counts over the selected period',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (features.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text('No features available for trend analysis.'),
                ),
              )
            else ...[
              DropdownButtonFormField<String>(
                value: _resolvedSelection(),
                decoration: const InputDecoration(
                  labelText: 'Feature',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: features
                    .map(
                      (feature) => DropdownMenuItem<String>(
                        value: feature.feature,
                        child: Text('${feature.feature} (${feature.count})'),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) onFeatureChanged(value);
                },
              ),
              const SizedBox(height: 16),
              if (loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Column(
                    children: [
                      Text(
                        error!,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: onRetry,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              else if (trend != null)
                AdminFeatureTrendChart(trend: trend!),
            ],
          ],
        ),
      ),
    );
  }

  String? _resolvedSelection() {
    if (selectedFeature != null &&
        features.any((feature) => feature.feature == selectedFeature)) {
      return selectedFeature;
    }
    return features.isEmpty ? null : features.first.feature;
  }
}
