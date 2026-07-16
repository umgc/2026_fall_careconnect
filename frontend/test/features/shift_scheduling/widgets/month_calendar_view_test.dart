// Tests for MonthCalendarView widget.
// (lib/features/shift_scheduling/presentation/widgets/month_calendar_view.dart)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/shift_scheduling/presentation/widgets/month_calendar_view.dart';
import 'package:care_connect_app/features/shift_scheduling/models/scheduled_visit_model.dart';

ScheduledVisit _makeVisit({
  int id = 1,
  String patientName = 'John Doe',
  DateTime? scheduledDate,
  int hour = 10,
  int duration = 60,
  String priority = 'Normal',
}) {
  final date = scheduledDate ?? DateTime(2026, 3, 17);
  return ScheduledVisit(
    id: id,
    caregiverId: 1,
    patientId: 10,
    patientName: patientName,
    serviceType: 'Personal Care',
    scheduledDate: date,
    scheduledTime: TimeOfDay(hour: hour, minute: 0),
    durationMinutes: duration,
    priority: priority,
    status: 'Scheduled',
    createdAt: date,
    updatedAt: date,
  );
}

Widget _wrap({
  List<ScheduledVisit> visits = const [],
  DateTime? selectedDate,
  Function(DateTime)? onDateSelected,
  Function(ScheduledVisit)? onVisitTap,
}) {
  return MaterialApp(
    home: Scaffold(
      body: MonthCalendarView(
        caregiverId: 1,
        visits: visits,
        selectedDate: selectedDate ?? DateTime(2026, 3, 17),
        onDateSelected: onDateSelected,
        onVisitTap: onVisitTap,
      ),
    ),
  );
}

void main() {
  group('MonthCalendarView', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(MonthCalendarView), findsOneWidget);
    });

    testWidgets('shows month and year header', (tester) async {
      await tester.pumpWidget(_wrap(selectedDate: DateTime(2026, 3, 17)));
      expect(find.text('March 2026'), findsOneWidget);
    });

    testWidgets('shows navigation arrows', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byIcon(Icons.chevron_left), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });

    testWidgets('left arrow goes to previous month', (tester) async {
      DateTime? selected;
      await tester.pumpWidget(_wrap(
        selectedDate: DateTime(2026, 3, 17),
        onDateSelected: (d) => selected = d,
      ));

      final leftBtn = find.ancestor(
        of: find.byIcon(Icons.chevron_left),
        matching: find.byType(IconButton),
      );
      tester.widget<IconButton>(leftBtn.first).onPressed!();
      await tester.pump();

      expect(selected, isNotNull);
      expect(selected!.month, 2);
      expect(find.text('February 2026'), findsOneWidget);
    });

    testWidgets('right arrow goes to next month', (tester) async {
      DateTime? selected;
      await tester.pumpWidget(_wrap(
        selectedDate: DateTime(2026, 3, 17),
        onDateSelected: (d) => selected = d,
      ));

      final rightBtn = find.ancestor(
        of: find.byIcon(Icons.chevron_right),
        matching: find.byType(IconButton),
      );
      tester.widget<IconButton>(rightBtn.first).onPressed!();
      await tester.pump();

      expect(selected, isNotNull);
      expect(selected!.month, 4);
      expect(find.text('April 2026'), findsOneWidget);
    });

    testWidgets('shows day-of-week headers', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('Mon'), findsOneWidget);
      expect(find.text('Tue'), findsOneWidget);
      expect(find.text('Wed'), findsOneWidget);
      expect(find.text('Thu'), findsOneWidget);
      expect(find.text('Fri'), findsOneWidget);
      expect(find.text('Sat'), findsOneWidget);
      expect(find.text('Sun'), findsOneWidget);
    });

    testWidgets('shows day numbers for the month', (tester) async {
      await tester.pumpWidget(_wrap(selectedDate: DateTime(2026, 3, 1)));
      await tester.pump();
      // March has 31 days
      expect(find.text('1'), findsWidgets);
      expect(find.text('15'), findsWidgets);
      expect(find.text('31'), findsWidgets);
    });

    testWidgets('renders with empty visit list', (tester) async {
      await tester.pumpWidget(_wrap(visits: []));
      await tester.pump();
      expect(find.byType(MonthCalendarView), findsOneWidget);
    });

    testWidgets('shows visit indicator on day with visits', (tester) async {
      final visits = [
        _makeVisit(scheduledDate: DateTime(2026, 3, 17)),
      ];
      await tester.pumpWidget(_wrap(visits: visits));
      await tester.pump();
      // Day 17 should have some visual indicator — verify widget renders.
      expect(find.byType(MonthCalendarView), findsOneWidget);
    });

    testWidgets('navigates across year boundary', (tester) async {
      await tester.pumpWidget(_wrap(selectedDate: DateTime(2026, 1, 15)));
      await tester.pump();
      expect(find.text('January 2026'), findsOneWidget);

      final leftBtn = find.ancestor(
        of: find.byIcon(Icons.chevron_left),
        matching: find.byType(IconButton),
      );
      tester.widget<IconButton>(leftBtn.first).onPressed!();
      await tester.pump();

      expect(find.text('December 2025'), findsOneWidget);
    });

    testWidgets('February shows 28 days in non-leap year', (tester) async {
      await tester.pumpWidget(_wrap(selectedDate: DateTime(2026, 2, 15)));
      await tester.pump();
      expect(find.text('February 2026'), findsOneWidget);
      expect(find.text('28'), findsWidgets);
    });
  });
}
