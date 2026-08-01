// Tests for CalendarView
// (lib/features/shift_scheduling/presentation/widgets/calendar_view.dart)
//
// CalendarView loads a caregiver's schedule through ScheduleApiService /
// ApiClient on init, renders the month view by default, and offers a
// PopupMenuButton to switch between month, week, and day views. A fake Dio
// adapter is injected via ApiClient.debugSetHttpClientAdapter so network calls
// resolve immediately with a controllable calendar payload.

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/services/api_client.dart';
import 'package:care_connect_app/features/shift_scheduling/presentation/widgets/calendar_view.dart';
import 'package:care_connect_app/features/shift_scheduling/presentation/widgets/month_calendar_view.dart';
import 'package:care_connect_app/features/shift_scheduling/presentation/widgets/week_calendar_view.dart';
import 'package:care_connect_app/features/shift_scheduling/presentation/widgets/day_schedule_view.dart';

/// Returns a canned JSON body for every request without touching the network.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.body, {this.statusCode = 200});
  final String body;
  final int statusCode;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    return ResponseBody.fromString(body, statusCode, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

Widget _wrap(Widget child) => MaterialApp(home: child);

const MethodChannel _secureStorageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
const MethodChannel _connectivityChannel =
    MethodChannel('dev.fluttercommunity.plus/connectivity');

void _setupStubs() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_secureStorageChannel, (call) async {
    if (call.method == 'readAll') return <String, String>{};
    return null; // read/containsKey/write/delete → no stored token
  });
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_connectivityChannel, (call) async {
    if (call.method == 'check') return ['wifi'];
    return null;
  });
}

void _teardownStubs() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_secureStorageChannel, null);
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_connectivityChannel, null);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void useEmptyCalendar() => ApiClient.instance
      .debugSetHttpClientAdapter(_FakeAdapter(jsonEncode({'days': {}})));

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _setupStubs();
    useEmptyCalendar();
  });

  tearDown(_teardownStubs);

  group('CalendarView rendering', () {
    testWidgets('shows a loading indicator on the first frame',
        (tester) async {
      await tester.pumpWidget(_wrap(const CalendarView(caregiverId: 1)));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('renders the Schedule Calendar app bar and title',
        (tester) async {
      await tester.pumpWidget(_wrap(const CalendarView(caregiverId: 1)));
      await tester.pumpAndSettle();
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.text('Schedule Calendar'), findsOneWidget);
    });

    testWidgets('hides the loading indicator once the schedule loads',
        (tester) async {
      await tester.pumpWidget(_wrap(const CalendarView(caregiverId: 1)));
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('defaults to the month view', (tester) async {
      await tester.pumpWidget(_wrap(const CalendarView(caregiverId: 1)));
      await tester.pumpAndSettle();
      expect(find.byType(MonthCalendarView), findsOneWidget);
      expect(find.byType(WeekCalendarView), findsNothing);
      expect(find.byType(DayScheduleView), findsNothing);
    });

    testWidgets('exposes a view-mode popup menu', (tester) async {
      await tester.pumpWidget(_wrap(const CalendarView(caregiverId: 1)));
      await tester.pumpAndSettle();
      expect(find.byType(PopupMenuButton<String>), findsOneWidget);
    });
  });

  group('CalendarView view switching', () {
    Future<void> openMenuAndSelect(WidgetTester tester, String label) async {
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    testWidgets('menu lists Month, Week, and Day options', (tester) async {
      await tester.pumpWidget(_wrap(const CalendarView(caregiverId: 1)));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      expect(find.text('Month View'), findsOneWidget);
      expect(find.text('Week View'), findsOneWidget);
      expect(find.text('Day View'), findsOneWidget);
    });

    testWidgets('switching to Week View renders the week calendar',
        (tester) async {
      await tester.pumpWidget(_wrap(const CalendarView(caregiverId: 1)));
      await tester.pumpAndSettle();
      await openMenuAndSelect(tester, 'Week View');
      expect(find.byType(WeekCalendarView), findsOneWidget);
      expect(find.byType(MonthCalendarView), findsNothing);
    });

    testWidgets('switching to Day View renders the day schedule',
        (tester) async {
      await tester.pumpWidget(_wrap(const CalendarView(caregiverId: 1)));
      await tester.pumpAndSettle();
      await openMenuAndSelect(tester, 'Day View');
      expect(find.byType(DayScheduleView), findsOneWidget);
      expect(find.byType(MonthCalendarView), findsNothing);
    });

    testWidgets('switching back to Month View restores the month calendar',
        (tester) async {
      await tester.pumpWidget(_wrap(const CalendarView(caregiverId: 1)));
      await tester.pumpAndSettle();
      await openMenuAndSelect(tester, 'Day View');
      await openMenuAndSelect(tester, 'Month View');
      expect(find.byType(MonthCalendarView), findsOneWidget);
      expect(find.byType(DayScheduleView), findsNothing);
    });
  });

  group('CalendarView resilience', () {
    testWidgets('renders with a caregiver that has no visits', (tester) async {
      await tester.pumpWidget(_wrap(const CalendarView(caregiverId: 999)));
      await tester.pumpAndSettle();
      expect(find.byType(MonthCalendarView), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('handles a server error without crashing', (tester) async {
      ApiClient.instance.debugSetHttpClientAdapter(
          _FakeAdapter('{"error":"boom"}', statusCode: 500));
      await tester.pumpWidget(_wrap(const CalendarView(caregiverId: 1)));
      await tester.pumpAndSettle();
      expect(find.byType(CalendarView), findsOneWidget);
      expect(find.byType(MonthCalendarView), findsOneWidget);
    });
  });

  group('CalendarView date selection reloads the schedule', () {
    Future<void> openMenuAndSelect(WidgetTester tester, String label) async {
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    testWidgets('tapping a day in month view triggers a reload', (tester) async {
      await tester.pumpWidget(_wrap(const CalendarView(caregiverId: 1)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('15').first);
      await tester.pumpAndSettle();
      expect(find.byType(MonthCalendarView), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('navigating weeks in week view triggers a reload',
        (tester) async {
      await tester.pumpWidget(_wrap(const CalendarView(caregiverId: 1)));
      await tester.pumpAndSettle();
      await openMenuAndSelect(tester, 'Week View');

      await tester.tap(find.byIcon(Icons.chevron_right).last);
      await tester.pumpAndSettle();
      expect(find.byType(WeekCalendarView), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('navigating days in day view triggers a reload', (tester) async {
      await tester.pumpWidget(_wrap(const CalendarView(caregiverId: 1)));
      await tester.pumpAndSettle();
      await openMenuAndSelect(tester, 'Day View');

      await tester.tap(find.byIcon(Icons.chevron_right).last);
      await tester.pumpAndSettle();
      expect(find.byType(DayScheduleView), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
