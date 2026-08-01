import 'package:flutter_test/flutter_test.dart';

import 'package:care_connect_app/features/admin_analytics/models/feature_trend_model.dart';

void main() {
  group('FeatureTrend.fromJson', () {
    test('parses daily counts and period bounds', () {
      final trend = FeatureTrend.fromJson({
        'feature': 'dashboard',
        'periodStart': '2026-07-01T00:00:00Z',
        'periodEnd': '2026-07-08T00:00:00Z',
        'dailyCounts': [
          {'date': '2026-07-01', 'count': 5},
          {'date': '2026-07-02', 'count': 0},
          {'date': '2026-07-03', 'count': 2},
        ],
      });

      expect(trend.feature, 'dashboard');
      expect(trend.dailyCounts, hasLength(3));
      expect(trend.dailyCounts.first.count, 5);
      expect(trend.dailyCounts[1].count, 0);
      expect(trend.dailyCounts.last.count, 2);
    });

    test('returns empty dailyCounts when field is null', () {
      final trend = FeatureTrend.fromJson({
        'feature': 'tasks',
        'periodStart': '2026-07-01T00:00:00Z',
        'periodEnd': '2026-07-02T00:00:00Z',
        'dailyCounts': null,
      });

      expect(trend.dailyCounts, isEmpty);
    });
  });
}
