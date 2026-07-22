// Tests for AdminAnalyticsSummary model
// (lib/features/admin_analytics/models/admin_analytics_summary_model.dart).
//
// Coverage strategy:
//   Pure fromJson parsing — no HTTP. Uses group() per DTO and
//   SharedPreferences.setMockInitialValues in setUp (telemetry_test pattern).

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/features/admin_analytics/models/admin_analytics_summary_model.dart';

Map<String, dynamic> _fullSummaryJson() {
  return {
    'periodStart': '2026-07-01T00:00:00Z',
    'periodEnd': '2026-07-08T00:00:00Z',
    'totalEvents': 120,
    'sessionCount': 15,
    'eventCountsByName': [
      {'eventName': 'screen_view', 'count': 50},
      {'eventName': 'feature_use', 'count': 30},
    ],
    'topFeatures': [
      {'feature': 'dashboard', 'count': 20},
      {'feature': 'tasks', 'count': 10},
    ],
    'syncMetrics': {
      'started': 5,
      'completed': 4,
      'failedEvents': 1,
      'attempted': 10,
      'succeeded': 8,
      'failed': 2,
      'successRate': 0.8,
    },
    'errorMetrics': {
      'totalErrors': 3,
      'byEndpointBucket': [
        {'endpoint': '/api/tasks', 'count': 2, 'rate': 0.6667},
        {'endpoint': '/api/users', 'count': 1, 'rate': 0.3333},
      ],
    },
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // ─── AdminAnalyticsSummary ──────────────────────────────────────────────

  group('AdminAnalyticsSummary.fromJson', () {
    test('parses full summary payload', () {
      final summary = AdminAnalyticsSummary.fromJson(_fullSummaryJson());

      expect(summary.periodStart, DateTime.parse('2026-07-01T00:00:00Z'));
      expect(summary.periodEnd, DateTime.parse('2026-07-08T00:00:00Z'));
      expect(summary.totalEvents, 120);
      expect(summary.sessionCount, 15);
      expect(summary.eventCountsByName, hasLength(2));
      expect(summary.topFeatures, hasLength(2));
      expect(summary.syncMetrics.succeeded, 8);
      expect(summary.errorMetrics.totalErrors, 3);
    });

    test('parses numeric fields delivered as doubles', () {
      final json = _fullSummaryJson()
        ..['totalEvents'] = 120.0
        ..['sessionCount'] = 15.0;

      final summary = AdminAnalyticsSummary.fromJson(json);

      expect(summary.totalEvents, 120);
      expect(summary.sessionCount, 15);
    });

    test('defaults missing nested objects to empty/zero values', () {
      final summary = AdminAnalyticsSummary.fromJson({
        'periodStart': '2026-07-01T00:00:00Z',
        'periodEnd': '2026-07-08T00:00:00Z',
        'totalEvents': 0,
        'sessionCount': 0,
        'eventCountsByName': null,
        'topFeatures': null,
        'syncMetrics': null,
        'errorMetrics': null,
      });

      expect(summary.eventCountsByName, isEmpty);
      expect(summary.topFeatures, isEmpty);
      expect(summary.syncMetrics.started, 0);
      expect(summary.syncMetrics.successRate, isNull);
      expect(summary.errorMetrics.totalErrors, 0);
      expect(summary.errorMetrics.byEndpointBucket, isEmpty);
    });

    test('ignores non-map entries in list fields', () {
      final json = _fullSummaryJson()
        ..['eventCountsByName'] = [
          {'eventName': 'screen_view', 'count': 1},
          'bad',
          42,
        ];

      final summary = AdminAnalyticsSummary.fromJson(json);

      expect(summary.eventCountsByName, hasLength(1));
      expect(summary.eventCountsByName.first.eventName, 'screen_view');
    });
  });

  // ─── EventNameCount ───────────────────────────────────────────────────────

  group('EventNameCount.fromJson', () {
    test('parses event name and count', () {
      final row = EventNameCount.fromJson({
        'eventName': 'session_start',
        'count': 12,
      });

      expect(row.eventName, 'session_start');
      expect(row.count, 12);
    });

    test('defaults missing fields', () {
      final row = EventNameCount.fromJson({});

      expect(row.eventName, '');
      expect(row.count, 0);
    });
  });

  // ─── FeatureUsageCount ────────────────────────────────────────────────────

  group('FeatureUsageCount.fromJson', () {
    test('parses feature and count', () {
      final row = FeatureUsageCount.fromJson({
        'feature': 'evv_dashboard',
        'count': 7,
      });

      expect(row.feature, 'evv_dashboard');
      expect(row.count, 7);
    });

    test('defaults missing fields', () {
      final row = FeatureUsageCount.fromJson({});

      expect(row.feature, '');
      expect(row.count, 0);
    });
  });

  // ─── SyncMetrics ──────────────────────────────────────────────────────────

  group('SyncMetrics.fromJson', () {
    test('parses all sync counters and successRate', () {
      final metrics = SyncMetrics.fromJson({
        'started': 3,
        'completed': 2,
        'failedEvents': 1,
        'attempted': 5,
        'succeeded': 4,
        'failed': 1,
        'successRate': 0.75,
      });

      expect(metrics.started, 3);
      expect(metrics.completed, 2);
      expect(metrics.failedEvents, 1);
      expect(metrics.attempted, 5);
      expect(metrics.succeeded, 4);
      expect(metrics.failed, 1);
      expect(metrics.successRate, 0.75);
    });

    test('successRate is null when omitted', () {
      final metrics = SyncMetrics.fromJson({
        'started': 0,
        'completed': 0,
        'failedEvents': 0,
        'attempted': 0,
        'succeeded': 0,
        'failed': 0,
      });

      expect(metrics.successRate, isNull);
    });
  });

  // ─── ErrorMetrics ─────────────────────────────────────────────────────────

  group('ErrorMetrics.fromJson', () {
    test('parses totalErrors and endpoint buckets', () {
      final metrics = ErrorMetrics.fromJson({
        'totalErrors': 5,
        'byEndpointBucket': [
          {'endpoint': '/api/patients', 'count': 3, 'rate': 0.6},
        ],
      });

      expect(metrics.totalErrors, 5);
      expect(metrics.byEndpointBucket, hasLength(1));
      expect(metrics.byEndpointBucket.first.endpoint, '/api/patients');
    });

    test('defaults missing bucket list to empty', () {
      final metrics = ErrorMetrics.fromJson({'totalErrors': 0});

      expect(metrics.byEndpointBucket, isEmpty);
    });
  });

  // ─── EndpointErrorCount ───────────────────────────────────────────────────

  group('EndpointErrorCount.fromJson', () {
    test('parses endpoint, count, and rate', () {
      final row = EndpointErrorCount.fromJson({
        'endpoint': '/api/analytics',
        'count': 4,
        'rate': 0.25,
      });

      expect(row.endpoint, '/api/analytics');
      expect(row.count, 4);
      expect(row.rate, 0.25);
    });

    test('defaults missing fields', () {
      final row = EndpointErrorCount.fromJson({});

      expect(row.endpoint, '');
      expect(row.count, 0);
      expect(row.rate, 0.0);
    });
  });
}
