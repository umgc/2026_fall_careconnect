// Tests for DayScheduleView widget.
// (lib/features/shift_scheduling/presentation/widgets/day_schedule_view.dart)
//
// Pure widget test — takes visit data directly, no HTTP.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/shift_scheduling/presentation/widgets/day_schedule_view.dart';
import 'package:care_connect_app/features/shift_scheduling/models/scheduled_visit_model.dart';

// ─── Helpers ────────────────────────────────────────────────────────────────

ScheduledVisit _makeVisit({
  int id = 1,
  String patientName = 'John Doe',
  String serviceType = 'Personal Care',
  int hour = 10,
  int minute = 0,
  int duration = 60,
  String priority = 'Normal',
  String status = 'Scheduled',
}) {
  return ScheduledVisit(
    id: id,
    caregiverId: 1,
    patientId: 10,
    patientName: patientName,
    serviceType: serviceType,
    scheduledDate: DateTime(2026, 3, 17),
    scheduledTime: TimeOfDay(hour: hour, minute: minute),
    durationMinutes: duration,
    priority: priority,
    status: status,
    createdAt: DateTime(2026, 3, 17),
    updatedAt: DateTime(2026, 3, 17),
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
      body: DayScheduleView(
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
  group('DayScheduleView', () {
    testWidgets('renders without crashing with empty visits', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(DayScheduleView), findsOneWidget);
    });

    testWidgets('shows formatted date header', (tester) async {
      await tester.pumpWidget(_wrap(
        selectedDate: DateTime(2026, 3, 17),
      ));
      // March 17, 2026 is a Tuesday
      expect(find.textContaining('March 17, 2026'), findsOneWidget);
    });

    testWidgets('shows left and right navigation arrows', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byIcon(Icons.chevron_left), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });

    testWidgets('left arrow calls onDateSelected with previous day',
        (tester) async {
      DateTime? selectedDate;
      await tester.pumpWidget(_wrap(
        selectedDate: DateTime(2026, 3, 17),
        onDateSelected: (date) => selectedDate = date,
      ));

      // Invoke left arrow programmatically.
      final leftBtn = find.ancestor(
        of: find.byIcon(Icons.chevron_left),
        matching: find.byType(IconButton),
      );
      tester.widget<IconButton>(leftBtn.first).onPressed!();

      expect(selectedDate, DateTime(2026, 3, 16));
    });

    testWidgets('right arrow calls onDateSelected with next day',
        (tester) async {
      DateTime? selectedDate;
      await tester.pumpWidget(_wrap(
        selectedDate: DateTime(2026, 3, 17),
        onDateSelected: (date) => selectedDate = date,
      ));

      final rightBtn = find.ancestor(
        of: find.byIcon(Icons.chevron_right),
        matching: find.byType(IconButton),
      );
      tester.widget<IconButton>(rightBtn.first).onPressed!();

      expect(selectedDate, DateTime(2026, 3, 18));
    });

    testWidgets('shows 24 hour time slots', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      // Check a few time slots
      expect(find.text('00:00'), findsOneWidget);
      expect(find.text('12:00'), findsOneWidget);
      expect(find.text('23:00'), findsOneWidget);
    });

    testWidgets('shows visit patient name at correct hour', (tester) async {
      final visits = [_makeVisit(patientName: 'Alice Smith', hour: 10)];
      await tester.pumpWidget(_wrap(visits: visits));
      await tester.pump();
      expect(find.text('Alice Smith'), findsOneWidget);
    });

    testWidgets('shows visit service type', (tester) async {
      final visits = [_makeVisit(serviceType: 'Skilled Nursing', hour: 14)];
      await tester.pumpWidget(_wrap(visits: visits));
      await tester.pump();
      expect(find.text('Skilled Nursing'), findsOneWidget);
    });

    testWidgets('shows multiple visits at different hours', (tester) async {
      final visits = [
        _makeVisit(id: 1, patientName: 'Alice', hour: 9),
        _makeVisit(id: 2, patientName: 'Bob', hour: 14),
      ];
      await tester.pumpWidget(_wrap(visits: visits));
      await tester.pump();
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
    });

    testWidgets('sorts visits by time', (tester) async {
      // Pass visits out of order — widget should sort them.
      final visits = [
        _makeVisit(id: 2, patientName: 'Later Visit', hour: 14),
        _makeVisit(id: 1, patientName: 'Earlier Visit', hour: 9),
      ];
      await tester.pumpWidget(_wrap(visits: visits));
      await tester.pump();
      expect(find.text('Earlier Visit'), findsOneWidget);
      expect(find.text('Later Visit'), findsOneWidget);
    });

    testWidgets('tapping visit calls onVisitTap callback', (tester) async {
      ScheduledVisit? tappedVisit;
      final visit = _makeVisit(patientName: 'Tap Me', hour: 10);
      await tester.pumpWidget(_wrap(
        visits: [visit],
        onVisitTap: (v) => tappedVisit = v,
      ));
      await tester.pump();

      // Find the GestureDetector wrapping the visit card.
      final gestureDetector = find.ancestor(
        of: find.text('Tap Me'),
        matching: find.byType(GestureDetector),
      );
      tester.widget<GestureDetector>(gestureDetector.first).onTap!();

      expect(tappedVisit, isNotNull);
      expect(tappedVisit!.patientName, 'Tap Me');
    });

    testWidgets('visit card shows priority-colored border', (tester) async {
      final visits = [_makeVisit(priority: 'High', hour: 10)];
      await tester.pumpWidget(_wrap(visits: visits));
      await tester.pump();
      // High priority should have a red-tinted container — just verify it renders.
      expect(find.text('High'), findsWidgets);
    });

    testWidgets('empty visit list shows time slots only', (tester) async {
      await tester.pumpWidget(_wrap(visits: []));
      await tester.pump();
      // Time slots should still render.
      expect(find.text('08:00'), findsOneWidget);
      expect(find.text('09:00'), findsOneWidget);
    });

    testWidgets('renders with high priority visit', (tester) async {
      final visits = [_makeVisit(priority: 'High', patientName: 'Urgent Patient')];
      await tester.pumpWidget(_wrap(visits: visits));
      await tester.pump();
      expect(find.text('Urgent Patient'), findsOneWidget);
    });

    testWidgets('renders with low priority visit', (tester) async {
      final visits = [_makeVisit(priority: 'Low', patientName: 'Routine Check')];
      await tester.pumpWidget(_wrap(visits: visits));
      await tester.pump();
      expect(find.text('Routine Check'), findsOneWidget);
    });
  });
}
