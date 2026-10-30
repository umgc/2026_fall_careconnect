// Tests for AdminAnalyticsCsvExporter
// (lib/features/admin_analytics/utils/admin_analytics_csv_exporter.dart) and
// AdminAnalyticsDetailSheet
// (lib/features/admin_analytics/presentation/widgets/admin_analytics_detail_sheet.dart).

import 'package:care_connect_app/features/admin_analytics/models/admin_analytics_summary_model.dart';
import 'package:care_connect_app/features/admin_analytics/presentation/widgets/admin_analytics_detail_sheet.dart';
import 'package:care_connect_app/features/admin_analytics/utils/admin_analytics_csv_exporter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

AdminAnalyticsSummary _summary({double? successRate = 0.75}) =>
    AdminAnalyticsSummary.fromJson({
      'periodStart': '2026-10-01T00:00:00Z',
      'periodEnd': '2026-10-08T00:00:00Z',
      'totalEvents': 120,
      'sessionCount': 9,
      'eventCountsByName': [
        {'eventName': 'screen_view', 'count': 10},
        {'eventName': 'button_tap, primary', 'count': 50},
      ],
      'topFeatures': [
        {'feature': 'calendar', 'count': 3},
        {'feature': 'say "hi"', 'count': 8},
      ],
      'syncMetrics': {
        'started': 4,
        'completed': 3,
        'failedEvents': 1,
        'attempted': 4,
        'succeeded': 3,
        'failed': 1,
        'successRate': successRate,
      },
      'errorMetrics': {
        'totalErrors': 2,
        'byEndpointBucket': [
          {'endpoint': '/v1/api/tasks\nPOST', 'count': 2, 'rate': 0.5},
        ],
      },
    });

void main() {
  group('AdminAnalyticsCsvExporter', () {
    test('writes every section with escaped fields, features descending', () {
      final csv = AdminAnalyticsCsvExporter.build(_summary());
      expect(csv, contains('Product Analytics Export'));
      expect(csv, contains('Total Events,120'));
      expect(csv, contains('Sessions,9'));
      expect(csv, contains('"button_tap, primary",50'));
      expect(csv, contains('"say ""hi""",8'));
      expect(csv, contains('Success Rate,0.7500'));
      expect(csv, contains('Total Errors,2'));
      expect(csv, contains('"/v1/api/tasks\nPOST",2,0.5000'));
      expect(csv.indexOf('button_tap'), lessThan(csv.indexOf('screen_view')));
      expect(csv.indexOf('say'), lessThan(csv.indexOf('calendar')));
    });

    test('ascending features and missing success rate', () {
      final csv = AdminAnalyticsCsvExporter.build(
        _summary(successRate: null),
        sortFeaturesDescending: false,
      );
      expect(csv, contains('Success Rate,\n'));
      expect(csv.indexOf('calendar'), lessThan(csv.indexOf('say')));
    });
  });

  group('AdminAnalyticsDetailSheet', () {
    Future<void> open(
      WidgetTester tester, {
      required AdminAnalyticsDetailKind kind,
      int totalEvents = 200,
      int? totalErrors,
      double? shareOfErrors,
    }) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => AdminAnalyticsDetailSheet.show(
                context,
                kind: kind,
                title: 'Item title',
                count: 50,
                totalEvents: totalEvents,
                description: 'Explains the metric.',
                totalErrors: totalErrors,
                shareOfErrors: shareOfErrors,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('event detail shows count and share of events',
        (tester) async {
      await open(tester, kind: AdminAnalyticsDetailKind.event);
      expect(find.text('Telemetry Event'), findsOneWidget);
      expect(find.text('Item title'), findsOneWidget);
      expect(find.text('50'), findsOneWidget);
      expect(find.text('25.0%'), findsOneWidget);
      expect(find.text('Explains the metric.'), findsOneWidget);
    });

    testWidgets('feature detail with zero events', (tester) async {
      await open(tester,
          kind: AdminAnalyticsDetailKind.feature, totalEvents: 0);
      expect(find.text('Feature Usage'), findsOneWidget);
      expect(find.text('0.0%'), findsOneWidget);
    });

    testWidgets('error detail adds share of errors', (tester) async {
      await open(
        tester,
        kind: AdminAnalyticsDetailKind.error,
        totalErrors: 4,
        shareOfErrors: 0.5,
      );
      expect(find.text('HTTP Error Bucket'), findsOneWidget);
      expect(find.text('% of total errors'), findsOneWidget);
      expect(find.text('Out of 4 errors in this period'), findsOneWidget);
    });
  });
}
