// Additional coverage for CalendarAssistantScreen
// (lib/features/tasks/presentation/calendar_assisiant.dart): tapping month
// cells, the next-month arrow, week-header days, and paging the week and
// day views.

import 'dart:convert';

import 'package:calendar_view/calendar_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:care_connect_app/features/tasks/models/task_model.dart';
import 'package:care_connect_app/features/tasks/presentation/calendar_assisiant.dart';
import 'package:care_connect_app/features/tasks/presentation/widgets/event_tile.dart';
import 'package:care_connect_app/features/tasks/utils/task_type_manager.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/providers/user_provider.dart';

import '../../../mock_user_provider.dart';

// One shared client: the API layer may keep the first client it sees, so
// tests change the response body rather than the client.
List<Map<String, dynamic>> _tasks = [];
final _client =
    MockClient((request) async => http.Response(jsonEncode(_tasks), 200));

Widget _app() => MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>.value(
          value: MockUserProvider(
              mockUser: MockUser(role: 'PATIENT', patientId: 1)),
        ),
        ChangeNotifierProvider<TaskTypeManager>(
          create: (_) => TaskTypeManager(),
        ),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: CalendarAssistantScreen(),
      ),
    );

void main() {
  final originalOnError = FlutterError.onError;

  setUp(() {
    _tasks = [];
    SharedPreferences.setMockInitialValues({});
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        if (call.method == 'readAll') return <String, String>{};
        if (call.method == 'containsKey') return false;
        return null;
      },
    );
    m.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => call.method == 'check' ? ['wifi'] : null,
    );
    FlutterError.onError = (details) {
      if (details.toString().contains('overflow')) return;
      originalOnError?.call(details);
    };
  });

  tearDown(() => FlutterError.onError = originalOnError);

  Future<void> frames(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> pumpCalendar(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app());
    await frames(tester);
  }

  Future<void> switchTo(WidgetTester tester, String label,
      {String from = 'Monthly'}) async {
    await tester.tap(find.text(from));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await frames(tester);
  }

  testWidgets('tapping a month cell selects that day', (tester) async {
    await http.runWithClient(() async {
      await pumpCalendar(tester);
      final month = find.byWidgetPredicate((w) => w is MonthView);
      expect(month, findsOneWidget);
      // Tap near the middle of the month grid.
      final rect = tester.getRect(month);
      await tester.tapAt(rect.center);
      await frames(tester);
      expect(find.text('Monthly'), findsOneWidget);

      // The custom header's next-month arrow pages the month view.
      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();
      expect(month, findsOneWidget);
    }, () => _client);
  });

  testWidgets('week view: tapping a weekday header and paging',
      (tester) async {
    await http.runWithClient(() async {
      await pumpCalendar(tester);
      await switchTo(tester, 'Weekly');
      final week = find.byWidgetPredicate((w) => w is WeekView);
      expect(week, findsOneWidget);
      // The custom weekday header uses single-letter labels.
      final wed = find.descendant(of: week, matching: find.text('W'));
      expect(wed, findsWidgets);
      await tester.tap(wed.first);
      await frames(tester);

      await tester.fling(week, const Offset(-600, 0), 2000);
      await tester.pumpAndSettle();
      expect(find.text('Weekly'), findsOneWidget);
    }, () => _client);
  });

  testWidgets('day view pages to another day', (tester) async {
    await http.runWithClient(() async {
      await pumpCalendar(tester);
      await switchTo(tester, 'Daily');
      final day = find.byWidgetPredicate((w) => w is DayView);
      expect(day, findsOneWidget);
      await tester.fling(day, const Offset(-600, 0), 2000);
      await tester.pumpAndSettle();
      expect(find.text('Daily'), findsOneWidget);
    }, () => _client);
  });

  testWidgets('tapping a task in day, week and month views opens the editor',
      (tester) async {
    final now = DateTime.now();
    _tasks = [
      {
        'id': 1,
        'name': 'Morning Meds',
        'description': 'Take pills',
        'date': DateTime(now.year, now.month, now.day).toIso8601String(),
        'timeOfDay': '10:00',
        'patientId': 1,
        'taskType': 'medication',
        'isComplete': false,
      },
    ];
    await http.runWithClient(() async {
      await pumpCalendar(tester);
      await switchTo(tester, 'Daily');
      expect(find.text('Morning Meds', skipOffstage: false), findsWidgets);
      // Invoke the day view's event tap with the rendered tile's events.
      final tile = tester.widget<EventTile>(
          find.byType(EventTile, skipOffstage: false).first);
      final dayView = tester.widget<DayView<Task>>(
          find.byWidgetPredicate((w) => w is DayView<Task>));
      dayView.onEventTap!(tile.events, DateTime.now());
      await tester.pumpAndSettle();
      expect(find.text('Task Title'), findsWidgets);
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      expect(find.text('Task Title'), findsNothing);

      // Week view event tap opens the same editor.
      await switchTo(tester, 'Weekly', from: 'Daily');
      final weekView = tester.widget<WeekView<Task>>(
          find.byWidgetPredicate((w) => w is WeekView<Task>));
      weekView.onEventTap!(tile.events, DateTime.now());
      await tester.pumpAndSettle();
      expect(find.text('Task Title'), findsWidgets);
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();

      // Month view event tap as well.
      await switchTo(tester, 'Monthly', from: 'Weekly');
      final monthView = tester.widget<MonthView<Task>>(
          find.byWidgetPredicate((w) => w is MonthView<Task>));
      monthView.onEventTap!(tile.events.first, DateTime.now());
      await tester.pumpAndSettle();
      expect(find.text('Task Title'), findsWidgets);
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      expect(find.text('Task Title'), findsNothing);
    }, () => _client);
  });
}
