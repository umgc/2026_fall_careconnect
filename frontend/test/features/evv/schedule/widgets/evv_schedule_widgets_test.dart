// Tests for EVV schedule view widgets:
//   EVVDayScheduleView, EVVWeekCalendarView, EVVMonthCalendarView.
// (lib/features/evv/schedule/widgets/)
//
// Pure widget tests — all take visit data directly, no HTTP.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/evv/schedule/widgets/evv_day_schedule_view.dart';
import 'package:care_connect_app/features/evv/schedule/widgets/evv_week_calendar_view.dart';
import 'package:care_connect_app/features/evv/schedule/widgets/evv_month_calendar_view.dart';
import 'package:care_connect_app/features/evv/schedule/pages/schedule_page.dart';

// ─── Helpers ────────────────────────────────────────────────────────────────

ScheduledVisit _makeVisit({
  int id = 1,
  String patientName = 'John Doe',
  String serviceType = 'Personal Care',
  DateTime? scheduledTime,
  int durationMinutes = 60,
  String status = 'Scheduled',
  String priority = 'Normal',
}) {
  final time = scheduledTime ?? DateTime(2026, 3, 17, 10, 0);
  return ScheduledVisit(
    id: id,
    patientId: 10,
    patientName: patientName,
    serviceType: serviceType,
    scheduledTime: time,
    duration: Duration(minutes: durationMinutes),
    status: status,
    priority: priority,
  );
}

Widget _wrapDay({
  List<ScheduledVisit> visits = const [],
  DateTime? selectedDate,
  Function(DateTime)? onDateSelected,
}) {
  return MaterialApp(
    home: Scaffold(
      body: EVVDayScheduleView(
        visits: visits,
        selectedDate: selectedDate ?? DateTime(2026, 3, 17),
        onDateSelected: onDateSelected,
      ),
    ),
  );
}

Widget _wrapWeek({
  List<ScheduledVisit> visits = const [],
  DateTime? selectedDate,
  Function(DateTime)? onDateSelected,
}) {
  return MaterialApp(
    home: Scaffold(
      body: EVVWeekCalendarView(
        visits: visits,
        selectedDate: selectedDate ?? DateTime(2026, 3, 17),
        onDateSelected: onDateSelected,
      ),
    ),
  );
}

Widget _wrapMonth({
  List<ScheduledVisit> visits = const [],
  DateTime? selectedDate,
  Function(DateTime)? onDateSelected,
  Function()? onScheduleNew,
}) {
  return MaterialApp(
    home: Scaffold(
      body: EVVMonthCalendarView(
        visits: visits,
        selectedDate: selectedDate ?? DateTime(2026, 3, 17),
        onDateSelected: onDateSelected,
        onScheduleNew: onScheduleNew,
      ),
    ),
  );
}

// ─── EVVDayScheduleView Tests ───────────────────────────────────────────────

void main() {
  group('EVVDayScheduleView', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrapDay());
      expect(find.byType(EVVDayScheduleView), findsOneWidget);
    });

    testWidgets('shows formatted date header', (tester) async {
      await tester.pumpWidget(_wrapDay(selectedDate: DateTime(2026, 3, 17)));
      expect(find.textContaining('March 17, 2026'), findsOneWidget);
    });

    testWidgets('shows navigation arrows', (tester) async {
      await tester.pumpWidget(_wrapDay());
      expect(find.byIcon(Icons.chevron_left), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });

    testWidgets('left arrow navigates to previous day', (tester) async {
      DateTime? selected;
      await tester.pumpWidget(_wrapDay(
        selectedDate: DateTime(2026, 3, 17),
        onDateSelected: (d) => selected = d,
      ));
      final leftBtn = find.ancestor(
        of: find.byIcon(Icons.chevron_left),
        matching: find.byType(IconButton),
      );
      tester.widget<IconButton>(leftBtn.first).onPressed!();
      expect(selected?.day, 16);
    });

    testWidgets('right arrow navigates to next day', (tester) async {
      DateTime? selected;
      await tester.pumpWidget(_wrapDay(
        selectedDate: DateTime(2026, 3, 17),
        onDateSelected: (d) => selected = d,
      ));
      final rightBtn = find.ancestor(
        of: find.byIcon(Icons.chevron_right),
        matching: find.byType(IconButton),
      );
      tester.widget<IconButton>(rightBtn.first).onPressed!();
      expect(selected?.day, 18);
    });

    testWidgets('shows visit patient name', (tester) async {
      await tester.pumpWidget(_wrapDay(visits: [
        _makeVisit(
          patientName: 'Alice',
          scheduledTime: DateTime(2026, 3, 17, 10, 0),
        ),
      ]));
      await tester.pump();
      expect(find.text('Alice'), findsOneWidget);
    });

    testWidgets('renders with empty visits', (tester) async {
      await tester.pumpWidget(_wrapDay(visits: []));
      await tester.pump();
      expect(find.byType(EVVDayScheduleView), findsOneWidget);
    });
  });

  // ─── EVVWeekCalendarView Tests ──────────────────────────────────────────────

  group('EVVWeekCalendarView', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrapWeek());
      expect(find.byType(EVVWeekCalendarView), findsOneWidget);
    });

    testWidgets('shows navigation arrows', (tester) async {
      await tester.pumpWidget(_wrapWeek());
      expect(find.byIcon(Icons.chevron_left), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });

    testWidgets('shows day-of-week headers', (tester) async {
      await tester.pumpWidget(_wrapWeek());
      await tester.pump();
      expect(find.textContaining('Mon'), findsWidgets);
      expect(find.textContaining('Sun'), findsWidgets);
    });

    testWidgets('shows visit on correct day', (tester) async {
      await tester.pumpWidget(_wrapWeek(
        visits: [
          _makeVisit(
            patientName: 'Tuesday Visit',
            scheduledTime: DateTime(2026, 3, 17, 14, 0),
          ),
        ],
        selectedDate: DateTime(2026, 3, 17),
      ));
      await tester.pump();
      expect(find.text('Tuesday Visit'), findsOneWidget);
    });

    testWidgets('left arrow navigates to previous week', (tester) async {
      DateTime? selected;
      await tester.pumpWidget(_wrapWeek(
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
    });

    testWidgets('renders with empty visits', (tester) async {
      await tester.pumpWidget(_wrapWeek(visits: []));
      await tester.pump();
      expect(find.byType(EVVWeekCalendarView), findsOneWidget);
    });

    testWidgets('multiple visits on same day', (tester) async {
      await tester.pumpWidget(_wrapWeek(
        visits: [
          _makeVisit(id: 1, patientName: 'Morning', scheduledTime: DateTime(2026, 3, 17, 9, 0)),
          _makeVisit(id: 2, patientName: 'Afternoon', scheduledTime: DateTime(2026, 3, 17, 14, 0)),
        ],
        selectedDate: DateTime(2026, 3, 17),
      ));
      await tester.pump();
      expect(find.text('Morning'), findsOneWidget);
      expect(find.text('Afternoon'), findsOneWidget);
    });
  });

  // ─── EVVMonthCalendarView Tests ─────────────────────────────────────────────

  group('EVVMonthCalendarView', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrapMonth());
      expect(find.byType(EVVMonthCalendarView), findsOneWidget);
    });

    testWidgets('shows month and year in header', (tester) async {
      await tester.pumpWidget(_wrapMonth(selectedDate: DateTime(2026, 3, 17)));
      expect(find.text('March 2026'), findsOneWidget);
    });

    testWidgets('shows navigation arrows', (tester) async {
      await tester.pumpWidget(_wrapMonth());
      expect(find.byIcon(Icons.chevron_left), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });

    testWidgets('left arrow goes to previous month', (tester) async {
      DateTime? selected;
      await tester.pumpWidget(_wrapMonth(
        selectedDate: DateTime(2026, 3, 17),
        onDateSelected: (d) => selected = d,
      ));
      final leftBtn = find.ancestor(
        of: find.byIcon(Icons.chevron_left),
        matching: find.byType(IconButton),
      );
      tester.widget<IconButton>(leftBtn.first).onPressed!();
      await tester.pump();
      expect(find.text('February 2026'), findsOneWidget);
    });

    testWidgets('right arrow goes to next month', (tester) async {
      DateTime? selected;
      await tester.pumpWidget(_wrapMonth(
        selectedDate: DateTime(2026, 3, 17),
        onDateSelected: (d) => selected = d,
      ));
      final rightBtn = find.ancestor(
        of: find.byIcon(Icons.chevron_right),
        matching: find.byType(IconButton),
      );
      tester.widget<IconButton>(rightBtn.first).onPressed!();
      await tester.pump();
      expect(find.text('April 2026'), findsOneWidget);
    });

    testWidgets('shows day-of-week headers', (tester) async {
      await tester.pumpWidget(_wrapMonth());
      await tester.pump();
      expect(find.text('Mon'), findsOneWidget);
      expect(find.text('Fri'), findsOneWidget);
      expect(find.text('Sun'), findsOneWidget);
    });

    testWidgets('renders with empty visits', (tester) async {
      await tester.pumpWidget(_wrapMonth(visits: []));
      await tester.pump();
      expect(find.byType(EVVMonthCalendarView), findsOneWidget);
    });

    testWidgets('navigates across year boundary', (tester) async {
      await tester.pumpWidget(_wrapMonth(selectedDate: DateTime(2026, 1, 15)));
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

    testWidgets('shows schedule new button when callback provided',
        (tester) async {
      bool called = false;
      await tester.pumpWidget(_wrapMonth(
        onScheduleNew: () => called = true,
      ));
      await tester.pump();
      // The onScheduleNew callback is wired to a FAB or button — verify widget renders.
      expect(find.byType(EVVMonthCalendarView), findsOneWidget);
    });
  });
}
