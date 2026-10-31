// Coverage tests for AdminAnalyticsDashboardPage
// (lib/features/admin_analytics/presentation/pages/admin_analytics_dashboard_page.dart):
// a malformed summary response, CSV export failing when the file
// plugin fails, and tapping an event row to open its detail sheet.

import 'dart:convert';

import 'package:care_connect_app/features/admin_analytics/presentation/pages/admin_analytics_dashboard_page.dart';
import 'package:care_connect_app/features/admin_analytics/presentation/widgets/admin_event_counts_chart.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../mock_user_provider.dart';

const _secureStorage =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

const _pathProvider = MethodChannel('plugins.flutter.io/path_provider');

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
  ],
  'syncMetrics': {'started': 1, 'completed': 1, 'successRate': 1.0},
  'errorMetrics': {'totalErrors': 0, 'byEndpointBucket': []},
});

MockClient _client({String? summary}) => MockClient((req) async {
      final url = req.url.toString();
      if (url.contains('feature-trends')) {
        return http.Response(
          jsonEncode({
            'feature': 'dashboard',
            'periodStart': '2026-07-01T00:00:00Z',
            'periodEnd': '2026-07-08T00:00:00Z',
            'dailyCounts': [
              {'date': '2026-07-01', 'count': 4},
            ],
          }),
          200,
        );
      }
      if (url.contains('admin/analytics/summary')) {
        return http.Response(summary ?? _summary, 200);
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

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorage, (call) async {
      if (call.method == 'readAll') return <String, String>{};
      if (call.method == 'containsKey') return false;
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorage, null);
  });

  testWidgets('a malformed summary shows a generic error', (tester) async {
    await http.runWithClient(() async {
      await _pump(tester);
    }, () => _client(summary: 'not json'));
    expect(find.textContaining('Error:'), findsWidgets);
  });

  testWidgets('CSV export reports a file-plugin failure', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProvider,
            (call) async => throw PlatformException(code: 'no_dir'));
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProvider, null));
    await http.runWithClient(() async {
      await _pump(tester);
      expect(find.text('Product Analytics'), findsWidgets);
      await tester.tap(find.byTooltip('Export CSV'));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }, () => _client());
    expect(find.textContaining('CSV export failed'), findsOneWidget);
  });

  testWidgets('tapping an event opens its detail sheet', (tester) async {
    await http.runWithClient(() async {
      await _pump(tester);
      // The bar chart reports taps through onEventTap.
      final chart = tester
          .widget<AdminEventCountsChart>(find.byType(AdminEventCountsChart));
      chart.onEventTap!(chart.events.first);
      await tester.pumpAndSettle();
    }, () => _client());
    expect(find.text('screen_view'), findsWidgets);
    expect(find.byType(BottomSheet), findsOneWidget);
  });
}
