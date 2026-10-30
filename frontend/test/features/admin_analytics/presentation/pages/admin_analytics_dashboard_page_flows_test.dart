// Flow tests for AdminAnalyticsDashboardPage
// (lib/features/admin_analytics/presentation/pages/admin_analytics_dashboard_page.dart)
// on a narrow layout: feature-list and error-table detail sheets, feature
// sort toggle and feature-trend selection and errors. AdminAnalyticsApi uses top-level http calls
// (http.runWithClient).

import 'dart:convert';

import 'package:care_connect_app/features/admin_analytics/presentation/pages/admin_analytics_dashboard_page.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../mock_user_provider.dart';

final _summary = jsonEncode({
  'periodStart': '2026-07-01T00:00:00Z',
  'periodEnd': '2026-07-08T00:00:00Z',
  'totalEvents': 120,
  'sessionCount': 15,
  'eventCountsByName': [
    {'eventName': 'screen_view', 'count': 50},
  ],
  'topFeatures': [
    {'feature': 'dashboard', 'count': 20},
    {'feature': 'tasks', 'count': 10},
  ],
  'syncMetrics': {'started': 1, 'completed': 1, 'successRate': null},
  'errorMetrics': {
    'totalErrors': 3,
    'byEndpointBucket': [
      {'endpoint': '', 'count': 2, 'rate': 0.6667},
      {'endpoint': '/api/users', 'count': 1, 'rate': 0.3333},
    ],
  },
});

MockClient _client({int trendStatus = 200, bool throwTrend = false}) =>
    MockClient((req) async {
      final url = req.url.toString();
      if (url.contains('feature-trends')) {
        if (throwTrend) throw StateError('trend down');
        return http.Response(
          jsonEncode({
            'feature': req.url.queryParameters['feature'],
            'periodStart': '2026-07-01T00:00:00Z',
            'periodEnd': '2026-07-08T00:00:00Z',
            'dailyCounts': [
              {'date': '2026-07-01', 'count': 4},
            ],
          }),
          trendStatus,
        );
      }
      if (url.contains('admin/analytics/summary')) {
        return http.Response(_summary, 200);
      }
      return http.Response('{}', 200);
    });

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(600, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ChangeNotifierProvider<UserProvider>.value(
    value: MockUserProvider(mockUser: MockUser(role: 'ADMIN')),
    child: const MaterialApp(home: AdminAnalyticsDashboardPage()),
  ));
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _closeSheet(WidgetTester tester) async {
  await tester.tapAt(const Offset(10, 10));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
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

  testWidgets('feature and error rows open detail sheets', (tester) async {
    await http.runWithClient(() async {
      await _pump(tester);
      expect(find.text('Total errors: 3'), findsOneWidget);

      await tester.tap(find.widgetWithText(ListTile, 'tasks'));
      await tester.pumpAndSettle();
      expect(find.text('Feature Usage'), findsOneWidget);
      await _closeSheet(tester);

      await tester.tap(find.text('/api/users'));
      await tester.pumpAndSettle();
      expect(find.text('HTTP Error Bucket'), findsOneWidget);
      await _closeSheet(tester);

      // Sort toggle flips the order.
      await tester.ensureVisible(find.byIcon(Icons.arrow_downward));
      await tester.tap(find.byIcon(Icons.arrow_downward));
      await tester.pump();
      expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
    }, () => _client());
  });

  testWidgets('selecting another trend feature refetches; errors show',
      (tester) async {
    await http.runWithClient(() async {
      await _pump(tester);
      await tester.tap(find.text('dashboard (20)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('tasks (10)').last);
      await tester.pumpAndSettle();
      expect(find.text('tasks (10)'), findsWidgets);
    }, () => _client());

    await http.runWithClient(() async {
      await tester.pumpWidget(const SizedBox());
      await _pump(tester);
      expect(find.textContaining('Retry'), findsWidgets);
    }, () => _client(trendStatus: 500));

    await http.runWithClient(() async {
      await tester.pumpWidget(const SizedBox());
      await _pump(tester);
      expect(find.textContaining('Error:'), findsWidgets);
    }, () => _client(throwTrend: true));
  });
}
