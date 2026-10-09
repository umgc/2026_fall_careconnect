// Tests for AdminAnalyticsDashboardPage
// (lib/features/admin_analytics/presentation/pages/admin_analytics_dashboard_page.dart).
//
// Coverage strategy:
//   AdminAnalyticsApi uses top-level http.get, interceptable via
//   http.runWithClient + MockClient. SharedPreferences and secure storage
//   are mocked via setMockInitialValues / MethodChannel handlers.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fl_chart/fl_chart.dart';

import 'package:care_connect_app/features/admin_analytics/presentation/pages/admin_analytics_dashboard_page.dart';
import 'package:care_connect_app/providers/user_provider.dart';

// ---------- helpers ----------

void _setupMocks() {
  SharedPreferences.setMockInitialValues({});
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    (call) async {
      if (call.method == 'readAll') {
        return <String, String>{'jwt_token': 'mock_token'};
      }
      if (call.method == 'read') return 'mock_token';
      if (call.method == 'containsKey') return true;
      return null;
    },
  );
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('dev.fluttercommunity.plus/connectivity'),
    (call) async {
      if (call.method == 'check') return ['wifi'];
      return null;
    },
  );
}

Widget _wrap() {
  final provider = UserProvider();
  provider.setUser(
    UserSession(
      id: 1,
      email: 'admin@test.com',
      role: 'ADMIN',
      token: 'mock_token',
      name: 'Test Admin',
    ),
  );
  provider.userSession = provider.user;

  return MaterialApp(
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en')],
    home: ChangeNotifierProvider<UserProvider>.value(
      value: provider,
      child: const AdminAnalyticsDashboardPage(),
    ),
  );
}

Future<void> _openDateRangePicker(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.date_range));
  await tester.pumpAndSettle();
  expect(find.byType(DateRangePickerDialog), findsOneWidget);
}

Future<void> _selectCalendarDay(WidgetTester tester, String day) async {
  final dayCells = find.descendant(
    of: find.byType(DateRangePickerDialog),
    matching: find.text(day, skipOffstage: false),
  );
  expect(dayCells, findsWidgets);
  await tester.tap(dayCells.first);
  await tester.pumpAndSettle();
}

Future<void> _confirmDateRangePicker(WidgetTester tester) async {
  final saveButton = find.widgetWithText(TextButton, 'Save');
  if (saveButton.evaluate().isNotEmpty) {
    await tester.tap(saveButton);
  } else {
    await tester.tap(find.widgetWithText(TextButton, 'OK'));
  }
  await tester.pumpAndSettle();
  expect(find.byType(DateRangePickerDialog), findsNothing);
}

Future<void> _pumpN(WidgetTester tester, {int n = 15}) async {
  for (int i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void _setLargeViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1600, 2400);
  tester.view.devicePixelRatio = 1.0;
}

String _summaryJson({
  int totalEvents = 120,
  int sessionCount = 15,
  bool withEvents = true,
  bool withFeatures = true,
  bool withErrors = true,
  double? successRate = 0.8,
}) {
  return jsonEncode({
    'periodStart': '2026-07-01T00:00:00Z',
    'periodEnd': '2026-07-08T00:00:00Z',
    'totalEvents': totalEvents,
    'sessionCount': sessionCount,
    'eventCountsByName': withEvents
        ? [
            {'eventName': 'screen_view', 'count': 50},
            {'eventName': 'feature_use', 'count': 30},
          ]
        : [],
    'topFeatures': withFeatures
        ? [
            {'feature': 'dashboard', 'count': 20},
            {'feature': 'tasks', 'count': 10},
          ]
        : [],
    'syncMetrics': {
      'started': 5,
      'completed': 4,
      'failedEvents': 1,
      'attempted': 10,
      'succeeded': 8,
      'failed': 2,
      'successRate': successRate,
    },
    'errorMetrics': {
      'totalErrors': withErrors ? 3 : 0,
      'byEndpointBucket': withErrors
          ? [
              {'endpoint': '/api/tasks', 'count': 2, 'rate': 0.6667},
              {'endpoint': '/api/users', 'count': 1, 'rate': 0.3333},
            ]
          : [],
    },
  });
}

String _featureTrendJson({String feature = 'dashboard'}) {
  return jsonEncode({
    'feature': feature,
    'periodStart': '2026-07-01T00:00:00Z',
    'periodEnd': '2026-07-08T00:00:00Z',
    'dailyCounts': [
      {'date': '2026-07-01', 'count': 4},
      {'date': '2026-07-02', 'count': 2},
    ],
  });
}

MockClient _createSuccessMockClient({String Function(Uri url)? bodyForUrl}) {
  return MockClient((request) async {
    final url = request.url.toString();
    if (url.contains('admin/analytics/feature-trends')) {
      final feature = request.url.queryParameters['feature'] ?? 'dashboard';
      return http.Response(_featureTrendJson(feature: feature), 200);
    }
    if (url.contains('admin/analytics/summary')) {
      final body = bodyForUrl?.call(request.url) ?? _summaryJson();
      return http.Response(body, 200);
    }
    return http.Response('{}', 200);
  });
}

MockClient _createErrorMockClient({int statusCode = 500, String? message}) {
  return MockClient((request) async {
    if (request.url.path.contains('admin/analytics/summary')) {
      return http.Response(
        jsonEncode({'error': message ?? 'Server error'}),
        statusCode,
      );
    }
    return http.Response('{}', 200);
  });
}

// ---------- tests ----------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(_setupMocks);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      null,
    );
  });

  // ─── Loading state ────────────────────────────────────────────────────────

  group('AdminAnalyticsDashboardPage - loading state', () {
    testWidgets('shows CircularProgressIndicator before data loads',
        (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows Product Analytics title during loading', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Product Analytics'), findsOneWidget);
    });
  });

  // ─── API error state ──────────────────────────────────────────────────────

  group('AdminAnalyticsDashboardPage - API error state', () {
    testWidgets('shows error icon and Retry on 500', (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.reset);

      final mockClient = _createErrorMockClient();
      await http.runWithClient(() async {
        await tester.pumpWidget(_wrap());
        await _pumpN(tester);
        expect(find.byIcon(Icons.error_outline), findsOneWidget);
        expect(find.text('Retry'), findsOneWidget);
      }, () => mockClient);
    });

    testWidgets('shows Admin access required on 403', (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.reset);

      final mockClient = _createErrorMockClient(
        statusCode: 403,
        message: 'Forbidden',
      );
      await http.runWithClient(() async {
        await tester.pumpWidget(_wrap());
        await _pumpN(tester);
        expect(find.text('Admin access required'), findsOneWidget);
      }, () => mockClient);
    });
  });

  // ─── Success state ────────────────────────────────────────────────────────

  group('AdminAnalyticsDashboardPage - success state', () {
    testWidgets('renders overview heading and subtitle', (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.reset);

      final mockClient = _createSuccessMockClient();
      await http.runWithClient(() async {
        await tester.pumpWidget(_wrap());
        await _pumpN(tester);
        expect(find.text('Product Analytics'), findsWidgets);
        expect(
          find.text('Anonymous telemetry summary (no PII)'),
          findsOneWidget,
        );
      }, () => mockClient);
    });

    testWidgets('renders KPI values from summary', (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.reset);

      final mockClient = _createSuccessMockClient();
      await http.runWithClient(() async {
        await tester.pumpWidget(_wrap());
        await _pumpN(tester);
        expect(find.text('Total Events'), findsOneWidget);
        expect(find.text('120'), findsOneWidget);
        expect(find.text('Sessions'), findsOneWidget);
        expect(find.text('Sync Success'), findsOneWidget);
        expect(find.text('80.0%'), findsWidgets);
        expect(find.text('Total errors: 3'), findsOneWidget);
      }, () => mockClient);
    });

    testWidgets('renders section cards and charts', (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.reset);

      final mockClient = _createSuccessMockClient();
      await http.runWithClient(() async {
        await tester.pumpWidget(_wrap());
        await _pumpN(tester);
        expect(find.text('Event Counts'), findsOneWidget);
        expect(find.text('Top Features'), findsOneWidget);
        expect(find.text('Feature Trend'), findsOneWidget);
        expect(find.text('Sync Metrics'), findsOneWidget);
        expect(find.text('Error Metrics'), findsOneWidget);
        expect(find.byType(BarChart), findsWidgets);
        expect(find.textContaining('Period:'), findsOneWidget);
      }, () => mockClient);
    });

    testWidgets('renders date range selector button', (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.reset);

      final mockClient = _createSuccessMockClient();
      await http.runWithClient(() async {
        await tester.pumpWidget(_wrap());
        await _pumpN(tester);
        expect(find.byIcon(Icons.date_range), findsOneWidget);
        expect(find.byType(OutlinedButton), findsOneWidget);
      }, () => mockClient);
    });

    testWidgets('initial fetch uses from and to query params', (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.reset);

      final requestedUrls = <Uri>[];
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('admin/analytics/summary')) {
          requestedUrls.add(request.url);
          return http.Response(_summaryJson(), 200);
        }
        if (request.url.path.contains('admin/analytics/feature-trends')) {
          return http.Response(_featureTrendJson(), 200);
        }
        return http.Response('{}', 200);
      });

      await http.runWithClient(() async {
        await tester.pumpWidget(_wrap());
        await _pumpN(tester, n: 20);

        expect(requestedUrls, isNotEmpty);
        final params = requestedUrls.first.queryParameters;
        expect(params.containsKey('from'), isTrue);
        expect(params.containsKey('to'), isTrue);
        expect(params.containsKey('days'), isFalse);
      }, () => mockClient);
    });

    testWidgets('loads feature trend after summary', (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.reset);

      final requestedPaths = <String>[];
      final mockClient = MockClient((request) async {
        requestedPaths.add(request.url.path);
        if (request.url.path.contains('admin/analytics/feature-trends')) {
          return http.Response(_featureTrendJson(), 200);
        }
        if (request.url.path.contains('admin/analytics/summary')) {
          return http.Response(_summaryJson(), 200);
        }
        return http.Response('{}', 200);
      });

      await http.runWithClient(() async {
        await tester.pumpWidget(_wrap());
        await _pumpN(tester, n: 20);
        expect(requestedPaths.any((path) => path.contains('feature-trends')),
            isTrue);
        expect(find.byType(LineChart), findsWidgets);
      }, () => mockClient);
    });
  });

  // ─── Date range picker interactions ───────────────────────────────────────

  group('AdminAnalyticsDashboardPage - date range picker interactions', () {
    testWidgets('selecting a new range reloads with updated from/to',
        (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.reset);

      final requestedUrls = <Uri>[];
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('admin/analytics/summary')) {
          requestedUrls.add(request.url);
          return http.Response(_summaryJson(), 200);
        }
        return http.Response('{}', 200);
      });

      await http.runWithClient(() async {
        await tester.pumpWidget(_wrap());
        await _pumpN(tester);
        expect(requestedUrls.length, 1);
        final initialFrom = requestedUrls.first.queryParameters['from'];

        await _openDateRangePicker(tester);

        // Pick a fixed range earlier in the current month (differs from default last-7-days).
        await _selectCalendarDay(tester, '1');
        await _selectCalendarDay(tester, '7');
        await _confirmDateRangePicker(tester);
        await _pumpN(tester);

        expect(requestedUrls.length, greaterThan(1));
        expect(requestedUrls.last.queryParameters['from'], isNotNull);
        expect(requestedUrls.last.queryParameters['to'], isNotNull);
        expect(
          requestedUrls.last.queryParameters['from'],
          isNot(equals(initialFrom)),
        );
      }, () => mockClient);
    });
  });

  // ─── Empty data state ─────────────────────────────────────────────────────

  group('AdminAnalyticsDashboardPage - empty data state', () {
    testWidgets('shows empty-state messages when lists are empty',
        (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.reset);

      final mockClient = _createSuccessMockClient(
        bodyForUrl: (_) => _summaryJson(
          totalEvents: 0,
          sessionCount: 0,
          withEvents: false,
          withFeatures: false,
          withErrors: false,
          successRate: null,
        ),
      );

      await http.runWithClient(() async {
        await tester.pumpWidget(_wrap());
        await _pumpN(tester);
        expect(
          find.text('No telemetry events in this period.'),
          findsOneWidget,
        );
        expect(
          find.text('No feature usage in this period.'),
          findsOneWidget,
        );
        expect(
          find.text('No errors recorded in this period.'),
          findsOneWidget,
        );
        expect(find.text('—'), findsWidgets);
      }, () => mockClient);
    });
  });

  // ─── Retry ────────────────────────────────────────────────────────────────

  group('AdminAnalyticsDashboardPage - retry', () {
    testWidgets('Retry button triggers another fetch', (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.reset);

      var callCount = 0;
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('admin/analytics/summary')) {
          callCount++;
          return http.Response(
            jsonEncode({'error': 'fail'}),
            500,
          );
        }
        return http.Response('{}', 200);
      });

      await http.runWithClient(() async {
        await tester.pumpWidget(_wrap());
        await _pumpN(tester);
        expect(find.text('Retry'), findsOneWidget);

        final initialCount = callCount;
        await tester.tap(find.text('Retry'));
        await _pumpN(tester);

        expect(callCount, greaterThan(initialCount));
      }, () => mockClient);
    });
  });

  group('AdminAnalyticsDashboardPage - sync help', () {
    testWidgets('info icon opens sync events explanation sheet', (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.reset);

      final mockClient = _createSuccessMockClient();
      await http.runWithClient(() async {
        await tester.pumpWidget(_wrap());
        await _pumpN(tester);

        expect(find.text('Sync Metrics'), findsOneWidget);
        await tester.tap(find.byTooltip('About sync events'));
        await tester.pumpAndSettle();

        expect(find.text('About sync events'), findsOneWidget);
        expect(find.text('What are sync events?'), findsOneWidget);
        expect(find.text('Why might everything be zero?'), findsOneWidget);
        expect(find.text('How to trigger sync events'), findsOneWidget);
      }, () => mockClient);
    });
  });
}
