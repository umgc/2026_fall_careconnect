// Coverage-focused tests for analytics charts and telemetry handlers (group I).
import 'dart:ui';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:care_connect_app/features/admin_analytics/models/admin_analytics_summary_model.dart';
import 'package:care_connect_app/features/admin_analytics/models/feature_trend_model.dart';
import 'package:care_connect_app/features/admin_analytics/presentation/widgets/admin_error_metrics_card.dart';
import 'package:care_connect_app/features/admin_analytics/presentation/widgets/admin_feature_trend_chart.dart';
import 'package:care_connect_app/features/admin_analytics/presentation/widgets/admin_top_features_section.dart';
import 'package:care_connect_app/features/telemetry/telemetry_error_handler.dart';

Widget _app(Widget child) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

FeatureTrend _trend(List<int> counts) => FeatureTrend(
      feature: 'feed',
      periodStart: DateTime(2024, 1, 1),
      periodEnd: DateTime(2024, 1, 10),
      dailyCounts: [
        for (var i = 0; i < counts.length; i++)
          DailyFeatureCount(date: DateTime(2024, 1, i + 1), count: counts[i]),
      ],
    );

final _tap = FlTapUpEvent(TapUpDetails(kind: PointerDeviceKind.touch));

void main() {
  group('AdminFeatureTrendChart', () {
    for (final counts in [
      [0, 0],
      [8, 1],
      [16, 2],
      [70, 3],
    ]) {
      testWidgets('renders axis for max ${counts.first}', (tester) async {
        await tester.pumpWidget(_app(AdminFeatureTrendChart(trend: _trend(counts))));
        expect(find.byType(LineChart), findsOneWidget);
      });
    }

    testWidgets('tooltip builder formats date and count', (tester) async {
      await tester.pumpWidget(_app(AdminFeatureTrendChart(trend: _trend([3, 5]))));
      final chart = tester.widget<LineChart>(find.byType(LineChart));
      final data = chart.data;
      final bar = data.lineBarsData.first;
      final items = data.lineTouchData.touchTooltipData.getTooltipItems([
        LineBarSpot(bar, 0, bar.spots[1]),
        LineBarSpot(bar, 0, const FlSpot(9, 1)),
      ]);
      expect(items.first!.text, contains('5'));
      expect(items.length, 2);
    });
  });

  group('AdminTopFeaturesSection touch', () {
    testWidgets('tap on bar invokes onFeatureTap', (tester) async {
      FeatureUsageCount? tapped;
      const features = [
        FeatureUsageCount(feature: 'feed', count: 5),
        FeatureUsageCount(feature: 'calendar', count: 3),
      ];
      await tester.pumpWidget(_app(AdminTopFeaturesSection(
        features: features,
        onSortToggle: () {},
        onFeatureTap: (f) => tapped = f,
      )));
      final chart = tester.widget<BarChart>(find.byType(BarChart));
      final cb = chart.data.barTouchData.touchCallback!;
      final group = chart.data.barGroups.first;
      BarTouchResponse resp(int idx) => BarTouchResponse(
            touchLocation: Offset.zero,
            touchChartCoordinate: Offset.zero,
            spot: BarTouchedSpot(group, idx, group.barRods.first, 0, null, -1,
                const FlSpot(0, 0), Offset.zero),
          );
      cb(_tap, null);
      cb(_tap, resp(99));
      cb(_tap, resp(0));
      expect(tapped, isNotNull);
    });
  });

  group('AdminErrorMetricsCard touch', () {
    testWidgets('tap on slice invokes onErrorTap', (tester) async {
      EndpointErrorCount? tapped;
      await tester.pumpWidget(_app(AdminErrorMetricsCard(
        metrics: const ErrorMetrics(totalErrors: 10, byEndpointBucket: [
          EndpointErrorCount(endpoint: 'auth', count: 6, rate: 0.6),
          EndpointErrorCount(endpoint: 'feed', count: 4, rate: 0.4),
        ]),
        onErrorTap: (e) => tapped = e,
      )));
      final chart = tester.widget<PieChart>(find.byType(PieChart));
      final cb = chart.data.pieTouchData.touchCallback!;
      PieTouchResponse resp(int idx) => PieTouchResponse(
            touchLocation: Offset.zero,
            touchedSection: PieTouchedSection(
                chart.data.sections.first, idx, 0, 0),
          );
      cb(_tap, null);
      cb(_tap, resp(42));
      cb(_tap, resp(1));
      expect(tapped!.endpoint, 'feed');
    });
  });

  group('telemetry error handlers', () {
    test('install wires FlutterError and PlatformDispatcher handlers', () {
      final oldFlutter = FlutterError.onError;
      final oldPlatform = PlatformDispatcher.instance.onError;
      final oldPresent = FlutterError.presentError;
      try {
        FlutterError.presentError = (_) {};
        installTelemetryErrorHandlers();
        FlutterError.onError!(
            FlutterErrorDetails(exception: Exception('boom')));
        expect(PlatformDispatcher.instance.onError!(
            Exception('x'), StackTrace.empty), isFalse);
        recordZoneUncaughtError(Exception('zone'));
      } finally {
        FlutterError.onError = oldFlutter;
        PlatformDispatcher.instance.onError = oldPlatform;
        FlutterError.presentError = oldPresent;
      }
    });
  });
}
