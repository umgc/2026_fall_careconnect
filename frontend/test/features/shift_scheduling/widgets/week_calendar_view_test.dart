// Tests for WeekCalendarView widget.
// (lib/features/shift_scheduling/presentation/widgets/week_calendar_view.dart)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/shift_scheduling/presentation/widgets/week_calendar_view.dart';
import 'package:care_connect_app/features/shift_scheduling/models/scheduled_visit_model.dart';

// ─── Helpers ────────────────────────────────────────────────────────────────

ScheduledVisit _makeVisit({
  int id = 1,
  String patientName = 'John Doe',
  String serviceType = 'Personal Care',
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
    serviceType: serviceType,
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
      body: WeekCalendarView(
        caregiverId: 1,
        visits: visits,
        selectedDate: selectedDate ?? DateTime(2026, 3, 17),
        onDateSelected: onDateSelected,
        onVisitTap: onVisitTap,
      ),
    ),
  );
}

// ─── Tests ──────────────────────────────────────────────────────────────────

void main() {
  group('WeekCalendarView', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(WeekCalendarView), findsOneWidget);
    });

    testWidgets('shows week date range header', (tester) async {
      // March 17, 2026 is Tuesday — week starts Monday March 16
      await tester.pumpWidget(_wrap(selectedDate: DateTime(2026, 3, 17)));
      expect(find.textContaining('Mar 16'), findsWidgets);
      expect(find.textContaining('Mar 22'), findsWidgets);
    });

    testWidgets('shows navigation arrows', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byIcon(Icons.chevron_left), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });

    testWidgets('shows 7 day columns', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      // Should show day abbreviations for all 7 days
      expect(find.textContaining('Mon'), findsWidgets);
      expect(find.textContaining('Sun'), findsWidgets);
    });

    testWidgets('shows visit patient name on correct day', (tester) async {
      final visits = [
        _makeVisit(
          patientName: 'Alice',
          scheduledDate: DateTime(2026, 3, 17),
        ),
      ];
      await tester.pumpWidget(_wrap(visits: visits));
      await tester.pump();
      expect(find.text('Alice'), findsOneWidget);
    });

    testWidgets('shows multiple visits on different days', (tester) async {
      final visits = [
        _makeVisit(id: 1, patientName: 'Monday Visit',
            scheduledDate: DateTime(2026, 3, 16)),
        _makeVisit(id: 2, patientName: 'Wednesday Visit',
            scheduledDate: DateTime(2026, 3, 18)),
      ];
      await tester.pumpWidget(_wrap(
        visits: visits,
        selectedDate: DateTime(2026, 3, 17),
      ));
      await tester.pump();
      expect(find.text('Monday Visit'), findsOneWidget);
      expect(find.text('Wednesday Visit'), findsOneWidget);
    });

    testWidgets('left arrow navigates to previous week', (tester) async {
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
      // Previous week starts March 9
      expect(selected!.day, 9);
    });

    testWidgets('right arrow navigates to next week', (tester) async {
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
      // Next week starts March 23
      expect(selected!.day, 23);
    });

    testWidgets('renders with empty visit list', (tester) async {
      await tester.pumpWidget(_wrap(visits: []));
      await tester.pump();
      expect(find.byType(WeekCalendarView), findsOneWidget);
    });

    testWidgets('visit outside current week is not shown', (tester) async {
      final visits = [
        _makeVisit(
          patientName: 'Wrong Week',
          scheduledDate: DateTime(2026, 4, 1),
        ),
      ];
      await tester.pumpWidget(_wrap(
        visits: visits,
        selectedDate: DateTime(2026, 3, 17),
      ));
      await tester.pump();
      expect(find.text('Wrong Week'), findsNothing);
    });
  });
}
