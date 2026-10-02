// Tests for the three client report screens in lib/features/dashboards/:
// ParticipationScreen, CompetencyTrendScreen and BehavioralTrendScreen.
// Each one loads a report through ApiService in initState, so HTTP is driven
// through the ApiService.debugSetHttpClient test seam with a MockClient.

import 'dart:convert';

import 'package:care_connect_app/features/dashboards/behavioral_trend_screen.dart';
import 'package:care_connect_app/features/dashboards/competency_trend_screen.dart';
import 'package:care_connect_app/features/dashboards/participation_screen.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Widget _wrap(Widget screen) => MaterialApp(home: screen);

void _setLargeViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Routes every request to [body] / [status] and counts the calls.
class _Backend {
  _Backend(this.body, {this.status = 200});

  Object body;
  int status;
  int calls = 0;
  Uri? lastUri;

  void install() {
    ApiService.debugSetHttpClient(MockClient((req) async {
      calls++;
      lastUri = req.url;
      return http.Response(jsonEncode(body), status);
    }));
    addTearDown(ApiService.debugResetHttpClient);
  }
}

/// Lets the MockClient future and the resulting setState land.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _openAndCloseDateDialog(
  WidgetTester tester, {
  required String button,
}) async {
  await tester.tap(find.byIcon(Icons.calendar_month));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  expect(find.text('Select date range'), findsOneWidget);
  expect(find.text('From'), findsOneWidget);
  expect(find.text('To'), findsOneWidget);
  await tester.tap(find.text(button));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

const _weeks = ['2026-09-07', '2026-09-14', '2026-09-21', '2026-09-28'];

Map<String, dynamic> _participation({String status = 'IMPROVING'}) => {
      'status': status,
      'weeklyCounts': [
        for (var i = 0; i < _weeks.length; i++)
          {'weekStartDate': _weeks[i], 'totalLogs': 2 + i},
      ],
      'activities': [
        {
          'activityId': 1,
          'activityName': 'Bathing',
          'category': 'adl',
          'totalLogsInPeriod': 6,
          'lastLoggedAt': '2026-09-29T10:15:00',
          'noRecentActivity': false,
        },
        {
          'activityId': 2,
          'activityName': 'Meal prep',
          'category': 'IADL',
          'totalLogsInPeriod': 0,
          'lastLoggedAt': [2026, 9, 1, 8, 30, 0],
          'noRecentActivity': true,
        },
        {
          'activityId': 3,
          'activityName': 'Laundry',
          'category': 'IADL',
          'totalLogsInPeriod': 1,
          'lastLoggedAt': null,
          'noRecentActivity': false,
        },
      ],
    };

Map<String, dynamic> _competency({String status = 'IMPROVING'}) => {
      'status': status,
      'weekLabels': _weeks,
      'activityTrends': [
        {
          'activityId': 1,
          'activityName': 'Bathing',
          'dataPoints': [
            for (var i = 0; i < _weeks.length; i++)
              {
                'weekStartDate': _weeks[i],
                'averageCompetencyScore': 2.0 + i * 0.5,
                'logCount': 1 + i,
              },
          ],
        },
        {
          'activityId': 2,
          'activityName': 'Dressing',
          'dataPoints': [
            {
              'weekStartDate': _weeks[0],
              'averageCompetencyScore': 4,
              'logCount': 2,
            },
            {
              'weekStartDate': _weeks[2],
              'averageCompetencyScore': 3.5,
              'logCount': '3',
            },
          ],
        },
      ],
    };

Map<String, dynamic> _behavioral({String trend = 'UP'}) => {
      'trend': trend,
      'weeklyCounts': [
        for (var i = 0; i < _weeks.length; i++)
          {'weekStartDate': _weeks[i], 'incidentCount': i},
      ],
      'topKeywords': ['agitation', 'wandering', 'refusal'],
    };

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // AuthTokenManager reads the JWT from flutter_secure_storage.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        if (call.method == 'readAll') return <String, String>{};
        if (call.method == 'containsKey') return false;
        return null;
      },
    );
  });

  // =========================================================================
  // ParticipationScreen
  // =========================================================================
  group('ParticipationScreen', () {
    Widget screen() =>
        const ParticipationScreen(clientId: 7, clientName: 'Jane Doe');

    testWidgets('shows a spinner before the report loads', (tester) async {
      _setLargeViewport(tester);
      _Backend(_participation()).install();
      await tester.pumpWidget(_wrap(screen()));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await _settle(tester);
    });

    testWidgets('renders title, client name and report data', (tester) async {
      _setLargeViewport(tester);
      final backend = _Backend(_participation())..install();
      await tester.pumpWidget(_wrap(screen()));
      await _settle(tester);

      expect(find.text('Participation'), findsOneWidget);
      expect(find.text('Jane Doe'), findsOneWidget);
      expect(find.text('Date range:'), findsOneWidget);
      expect(find.byIcon(Icons.trending_up), findsWidgets);
      expect(find.textContaining('Bathing'), findsWidgets);
      expect(backend.calls, 1);
      expect(backend.lastUri!.path, endsWith('/7/reports/participation'));
      expect(backend.lastUri!.queryParameters, contains('startDate'));
      expect(backend.lastUri!.queryParameters, contains('endDate'));
    });

    testWidgets('shows the declining and stable status icons', (tester) async {
      _setLargeViewport(tester);
      final backend = _Backend(_participation(status: 'DECLINING'))..install();
      await tester.pumpWidget(_wrap(screen()));
      await _settle(tester);
      expect(find.byIcon(Icons.trending_down), findsWidgets);

      backend.body = _participation(status: 'STABLE');
      await tester.pumpWidget(_wrap(const SizedBox()));
      await tester.pumpWidget(_wrap(screen()));
      await _settle(tester);
      expect(find.byIcon(Icons.trending_flat), findsWidgets);
    });

    testWidgets('shows the empty-period message for an empty report',
        (tester) async {
      _setLargeViewport(tester);
      _Backend({'status': 'STABLE', 'weeklyCounts': [], 'activities': []})
          .install();
      await tester.pumpWidget(_wrap(screen()));
      await _settle(tester);
      expect(find.textContaining('No activity logs in this period'),
          findsOneWidget);
    });

    testWidgets('shows "No weekly data" when only activities are present',
        (tester) async {
      _setLargeViewport(tester);
      _Backend({..._participation(), 'weeklyCounts': []}).install();
      await tester.pumpWidget(_wrap(screen()));
      await _settle(tester);
      expect(find.text('No weekly data'), findsOneWidget);
      expect(find.textContaining('Bathing'), findsWidgets);
    });

    testWidgets('shows the status code and retries on failure', (tester) async {
      _setLargeViewport(tester);
      final backend = _Backend({'error': 'boom'}, status: 500)..install();
      await tester.pumpWidget(_wrap(screen()));
      await _settle(tester);

      expect(find.text('Failed to load: 500'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      backend
        ..status = 200
        ..body = _participation();
      await tester.tap(find.text('Retry'));
      await _settle(tester);
      expect(backend.calls, 2);
      expect(find.text('Failed to load: 500'), findsNothing);
      expect(find.text('Date range:'), findsOneWidget);
    });

    testWidgets('shows the exception text when the body is not JSON',
        (tester) async {
      _setLargeViewport(tester);
      ApiService.debugSetHttpClient(
          MockClient((req) async => http.Response('not json', 200)));
      addTearDown(ApiService.debugResetHttpClient);
      await tester.pumpWidget(_wrap(screen()));
      await _settle(tester);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('date range dialog: Cancel keeps, Apply reloads',
        (tester) async {
      _setLargeViewport(tester);
      final backend = _Backend(_participation())..install();
      await tester.pumpWidget(_wrap(screen()));
      await _settle(tester);

      await _openAndCloseDateDialog(tester, button: 'Cancel');
      await _settle(tester);
      expect(backend.calls, 1);

      await _openAndCloseDateDialog(tester, button: 'Apply');
      await _settle(tester);
      expect(backend.calls, 2);
    });
  });

  // =========================================================================
  // CompetencyTrendScreen
  // =========================================================================
  group('CompetencyTrendScreen', () {
    Widget screen() =>
        const CompetencyTrendScreen(clientId: 9, clientName: 'Sam Lee');

    testWidgets('renders title, client name and trend data', (tester) async {
      _setLargeViewport(tester);
      final backend = _Backend(_competency())..install();
      await tester.pumpWidget(_wrap(screen()));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await _settle(tester);

      expect(find.text('Competency Trends'), findsOneWidget);
      expect(find.text('Sam Lee'), findsOneWidget);
      expect(find.text('Date range:'), findsOneWidget);
      expect(find.byIcon(Icons.trending_up), findsWidgets);
      expect(find.textContaining('Bathing'), findsWidgets);
      expect(backend.lastUri!.path, endsWith('/9/reports/competency-trends'));
    });

    testWidgets('shows the declining and stable status icons', (tester) async {
      _setLargeViewport(tester);
      final backend = _Backend(_competency(status: 'DECLINING'))..install();
      await tester.pumpWidget(_wrap(screen()));
      await _settle(tester);
      expect(find.byIcon(Icons.trending_down), findsWidgets);

      backend.body = _competency(status: 'STABLE');
      await tester.pumpWidget(_wrap(const SizedBox()));
      await tester.pumpWidget(_wrap(screen()));
      await _settle(tester);
      expect(find.byIcon(Icons.trending_flat), findsWidgets);
    });

    testWidgets('shows the no-data message for an empty report',
        (tester) async {
      _setLargeViewport(tester);
      _Backend({'status': 'STABLE', 'weekLabels': [], 'activityTrends': []})
          .install();
      await tester.pumpWidget(_wrap(screen()));
      await _settle(tester);
      expect(find.textContaining('No competency data yet'), findsOneWidget);
    });

    testWidgets('shows "No weekly data" when week labels are missing',
        (tester) async {
      _setLargeViewport(tester);
      _Backend({..._competency(), 'weekLabels': []}).install();
      await tester.pumpWidget(_wrap(screen()));
      await _settle(tester);
      expect(find.text('No weekly data'), findsOneWidget);
    });

    testWidgets('shows "No activity data in this range" with no data points',
        (tester) async {
      _setLargeViewport(tester);
      _Backend({
        'status': 'STABLE',
        'weekLabels': _weeks,
        'activityTrends': [
          {'activityId': 1, 'activityName': 'Bathing', 'dataPoints': []},
        ],
      }).install();
      await tester.pumpWidget(_wrap(screen()));
      await _settle(tester);
      expect(find.text('No activity data in this range'), findsOneWidget);
    });

    testWidgets('shows the status code and retries on failure', (tester) async {
      _setLargeViewport(tester);
      final backend = _Backend({'error': 'boom'}, status: 503)..install();
      await tester.pumpWidget(_wrap(screen()));
      await _settle(tester);
      expect(find.text('Failed to load: 503'), findsOneWidget);

      backend
        ..status = 200
        ..body = _competency();
      await tester.tap(find.text('Retry'));
      await _settle(tester);
      expect(backend.calls, 2);
      expect(find.text('Date range:'), findsOneWidget);
    });

    testWidgets('date range dialog: Cancel keeps, Apply reloads',
        (tester) async {
      _setLargeViewport(tester);
      final backend = _Backend(_competency())..install();
      await tester.pumpWidget(_wrap(screen()));
      await _settle(tester);

      await _openAndCloseDateDialog(tester, button: 'Cancel');
      await _settle(tester);
      expect(backend.calls, 1);

      await _openAndCloseDateDialog(tester, button: 'Apply');
      await _settle(tester);
      expect(backend.calls, 2);
    });
  });

  // =========================================================================
  // BehavioralTrendScreen
  // =========================================================================
  group('BehavioralTrendScreen', () {
    Widget screen() =>
        const BehavioralTrendScreen(clientId: 11, clientName: 'Pat Kim');

    testWidgets('renders title, client name, chart and keywords',
        (tester) async {
      _setLargeViewport(tester);
      final backend = _Backend(_behavioral())..install();
      await tester.pumpWidget(_wrap(screen()));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await _settle(tester);

      expect(find.text('Behavioral Frequency'), findsOneWidget);
      expect(find.text('Pat Kim'), findsOneWidget);
      expect(find.text('Date range:'), findsOneWidget);
      expect(find.byIcon(Icons.trending_up), findsWidgets);
      expect(find.text('Most frequently observed behavior keywords'),
          findsOneWidget);
      // Keywords are shown capitalized.
      expect(find.text('Agitation'), findsOneWidget);
      expect(find.text('Wandering'), findsOneWidget);
      expect(backend.lastUri!.path, endsWith('/11/reports/behavioral-trends'));
    });

    testWidgets('shows the down and stable trend icons', (tester) async {
      _setLargeViewport(tester);
      final backend = _Backend(_behavioral(trend: 'DOWN'))..install();
      await tester.pumpWidget(_wrap(screen()));
      await _settle(tester);
      expect(find.byIcon(Icons.trending_down), findsWidgets);

      backend.body = _behavioral(trend: 'STABLE');
      await tester.pumpWidget(_wrap(const SizedBox()));
      await tester.pumpWidget(_wrap(screen()));
      await _settle(tester);
      expect(find.byIcon(Icons.trending_flat), findsWidgets);
    });

    testWidgets('shows the no-data message for an empty report',
        (tester) async {
      _setLargeViewport(tester);
      _Backend({'trend': 'STABLE', 'weeklyCounts': [], 'topKeywords': []})
          .install();
      await tester.pumpWidget(_wrap(screen()));
      await _settle(tester);
      expect(find.textContaining('No behavioral incident data yet'),
          findsOneWidget);
    });

    testWidgets('shows "No weekly data" when only keywords are present',
        (tester) async {
      _setLargeViewport(tester);
      _Backend({..._behavioral(), 'weeklyCounts': []}).install();
      await tester.pumpWidget(_wrap(screen()));
      await _settle(tester);
      expect(find.text('No weekly data'), findsOneWidget);
      expect(find.text('Refusal'), findsOneWidget);
    });

    testWidgets('shows the status code and retries on failure', (tester) async {
      _setLargeViewport(tester);
      final backend = _Backend({'error': 'boom'}, status: 404)..install();
      await tester.pumpWidget(_wrap(screen()));
      await _settle(tester);
      expect(find.text('Failed to load: 404'), findsOneWidget);

      backend
        ..status = 200
        ..body = _behavioral();
      await tester.tap(find.text('Retry'));
      await _settle(tester);
      expect(backend.calls, 2);
      expect(find.text('Date range:'), findsOneWidget);
    });

    testWidgets('date range dialog: Cancel keeps, Apply reloads',
        (tester) async {
      _setLargeViewport(tester);
      final backend = _Backend(_behavioral())..install();
      await tester.pumpWidget(_wrap(screen()));
      await _settle(tester);

      await _openAndCloseDateDialog(tester, button: 'Cancel');
      await _settle(tester);
      expect(backend.calls, 1);

      await _openAndCloseDateDialog(tester, button: 'Apply');
      await _settle(tester);
      expect(backend.calls, 2);
    });
  });
}
