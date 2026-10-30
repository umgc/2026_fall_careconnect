// Interaction tests for the EVV schedule calendar widgets
// (lib/features/evv/schedule/widgets/): date-cell and visit taps,
// the month view empty state, and priority colour branches.

import 'package:care_connect_app/features/evv/schedule/pages/schedule_page.dart';
import 'package:care_connect_app/features/evv/schedule/widgets/evv_day_schedule_view.dart';
import 'package:care_connect_app/features/evv/schedule/widgets/evv_month_calendar_view.dart';
import 'package:care_connect_app/features/evv/schedule/widgets/evv_week_calendar_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ScheduledVisit _visit({
  int id = 1,
  String patientName = 'Jane Roe',
  DateTime? at,
  String priority = 'Normal',
}) =>
    ScheduledVisit(
      id: id,
      patientId: 10,
      patientName: patientName,
      serviceType: 'Personal Care',
      scheduledTime: at ?? DateTime(2026, 3, 18, 10),
      duration: const Duration(minutes: 30),
      status: 'Scheduled',
      priority: priority,
    );

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
}

void main() {
  group('EVVMonthCalendarView interactions', () {
    testWidgets('shows empty state when there are no visits', (tester) async {
      await _pump(
        tester,
        EVVMonthCalendarView(visits: const [], selectedDate: DateTime(2026, 3, 1)),
      );
      expect(find.text('No visits scheduled'), findsOneWidget);
      expect(
        find.text('Tap the + button to schedule a new visit'),
        findsOneWidget,
      );
    });

    testWidgets('tapping a day cell reports the selected date',
        (tester) async {
      DateTime? selected;
      await _pump(
        tester,
        EVVMonthCalendarView(
          visits: const [],
          selectedDate: DateTime(2026, 3, 1),
          onDateSelected: (d) => selected = d,
        ),
      );
      await tester.tap(find.text('20'));
      await tester.pump();
      expect(selected, DateTime(2026, 3, 20));
    });

    testWidgets('tapping a visit chip reports the visit', (tester) async {
      ScheduledVisit? tapped;
      await _pump(
        tester,
        EVVMonthCalendarView(
          visits: [_visit(patientName: 'Jane Roe', priority: 'Low')],
          selectedDate: DateTime(2026, 3, 1),
          onVisitTap: (v) => tapped = v,
        ),
      );
      expect(find.text('No visits scheduled'), findsNothing);
      await tester.tap(find.text('Jane'));
      await tester.pump();
      expect(tapped?.patientName, 'Jane Roe');
    });
  });

  group('EVVWeekCalendarView interactions', () {
    testWidgets('tapping a visit card reports the visit', (tester) async {
      ScheduledVisit? tapped;
      await _pump(
        tester,
        EVVWeekCalendarView(
          visits: [_visit(patientName: 'Week Visitor', priority: 'Medium')],
          selectedDate: DateTime(2026, 3, 18),
          onVisitTap: (v) => tapped = v,
        ),
      );
      await tester.tap(find.text('Week Visitor'));
      await tester.pump();
      expect(tapped?.patientName, 'Week Visitor');
    });
  });

  group('EVVDayScheduleView priority colours', () {
    testWidgets('renders medium and low priority visits', (tester) async {
      await _pump(
        tester,
        EVVDayScheduleView(
          visits: [
            _visit(id: 1, patientName: 'Med P', priority: 'Medium'),
            _visit(
              id: 2,
              patientName: 'Low P',
              priority: 'Low',
              at: DateTime(2026, 3, 18, 11),
            ),
          ],
          selectedDate: DateTime(2026, 3, 18),
        ),
      );
      expect(find.text('Medium'), findsOneWidget);
      expect(find.text('Low'), findsOneWidget);
      final medium = tester.widget<Text>(find.text('Medium'));
      final low = tester.widget<Text>(find.text('Low'));
      expect(medium.style?.color, Colors.orange);
      expect(low.style?.color, Colors.green);
    });
  });
}
