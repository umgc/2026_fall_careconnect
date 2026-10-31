import 'package:care_connect_app/features/admin_analytics/models/admin_analytics_summary_model.dart';
import 'package:care_connect_app/features/admin_analytics/presentation/widgets/admin_event_counts_chart.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<BarChartData> _pump(
  WidgetTester tester,
  List<EventNameCount> events, {
  ValueChanged<EventNameCount>? onTap,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: AdminEventCountsChart(
            events: events,
            totalEvents: events.fold(0, (s, e) => s + e.count),
            onEventTap: onTap,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return tester.widget<BarChart>(find.byType(BarChart)).data;
}

BarTouchResponse _response(int index) {
  final group = BarChartGroupData(x: index);
  final rod = BarChartRodData(toY: 1);
  return BarTouchResponse(
    touchLocation: Offset.zero,
    touchChartCoordinate: Offset.zero,
    spot: BarTouchedSpot(group, index, rod, 0, null, -1,
        const FlSpot(0, 1), Offset.zero),
  );
}

final _tapUp = FlTapUpEvent(TapUpDetails(kind: PointerDeviceKind.touch));

void main() {
  testWidgets('empty list shows placeholder text', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AdminEventCountsChart(events: [], totalEvents: 0),
        ),
      ),
    );
    expect(find.text('Event Counts'), findsOneWidget);
    expect(find.text('No telemetry events in this period.'), findsOneWidget);
  });

  testWidgets('touch callback routes taps to onEventTap', (tester) async {
    final tapped = <String>[];
    final data = await _pump(
      tester,
      const [
        EventNameCount(eventName: 'screen_view_long_name', count: 37),
        EventNameCount(eventName: 'login', count: 3),
      ],
      onTap: (e) => tapped.add(e.eventName),
    );

    final cb = data.barTouchData.touchCallback!;
    cb(_tapUp, _response(0));
    cb(_tapUp, _response(9)); // out of range ignored
    cb(_tapUp, null); // no spot ignored
    expect(tapped, ['screen_view_long_name']);

    final tooltip = data.barTouchData.touchTooltipData.getTooltipItem(
      BarChartGroupData(x: 1),
      1,
      BarChartRodData(toY: 3),
      0,
    );
    expect(tooltip!.text, 'login\n3');
  });

  testWidgets('without onEventTap, callback is a no-op; varied magnitudes',
      (tester) async {
    for (final count in [0, 7, 13, 70, 900]) {
      final data = await _pump(
        tester,
        [EventNameCount(eventName: 'e$count', count: count)],
      );
      data.barTouchData.touchCallback!(_tapUp, _response(0));
      expect(find.text('Event Counts'), findsOneWidget);
    }
  });
}
