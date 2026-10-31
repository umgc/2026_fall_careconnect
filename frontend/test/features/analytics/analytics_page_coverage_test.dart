// Additional coverage for AnalyticsPage: network exceptions, the export
// failure snackbar action, and the summary fallbacks used when the dashboard
// analytics are missing (computed from vitals, or "no data" in dark mode).

import 'dart:convert';

import 'package:care_connect_app/features/analytics/analytics_page.dart';
import 'package:care_connect_app/features/analytics/models/vital_model.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _vital(DateTime ts, int i, {bool withMood = true}) => {
      'patientId': 1,
      'timestamp': ts.toIso8601String(),
      'heartRate': 70.0 + i,
      'spo2': 96.0,
      'systolic': 118 + i,
      'diastolic': 78,
      'weight': 160.0 - i,
      if (withMood) 'moodValue': 4 + i,
      if (withMood) 'painValue': 3,
    };

String _vitalsBody() {
  final now = DateTime.now();
  return jsonEncode({
    'data': [
      _vital(now.subtract(const Duration(hours: 3)), 0),
      _vital(now.subtract(const Duration(days: 1)), 1, withMood: false),
      _vital(now.subtract(const Duration(days: 2)), 2),
    ],
  });
}

final _dashboardBody = jsonEncode({
  'adherenceRate': 90.0,
  'avgHeartRate': 72.0,
  'avgSpo2': 97.0,
  'avgSystolic': 120.0,
  'avgDiastolic': 80.0,
  'avgWeight': 165.0,
  'avgMood': 5.0,
  'avgPain': 4.0,
});

MockClient _okClient() => MockClient((req) async {
      final url = req.url.toString();
      if (url.contains('analytics/export')) return http.Response('x', 200);
      if (url.contains('analytics/vitals')) {
        return http.Response(_vitalsBody(), 200);
      }
      if (url.contains('analytics/dashboard')) {
        return http.Response(_dashboardBody, 200);
      }
      return http.Response('{}', 200);
    });

Future<void> _pumpN(WidgetTester tester, {int n = 15}) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        if (call.method == 'readAll') return <String, String>{};
        if (call.method == 'containsKey') return false;
        return null;
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => call.method == 'check' ? ['wifi'] : null,
    );
  });

  Future<void> pumpPage(WidgetTester tester,
      {required Size size, ThemeData? theme}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final original = FlutterError.onError;
    FlutterError.onError = (d) {
      if (d.toString().contains('overflowed')) return;
      original?.call(d);
    };
    addTearDown(() => FlutterError.onError = original);
    await tester.pumpWidget(MaterialApp(
      theme: theme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const AnalyticsPage(patientId: 1),
    ));
    await _pumpN(tester);
  }

  testWidgets('network exception shows a generic error screen',
      (tester) async {
    final client = MockClient((req) async {
      throw const SocketExceptionLike('connection refused');
    });
    await http.runWithClient(() async {
      await pumpPage(tester, size: const Size(1200, 2400));
    }, () => client);
    expect(find.textContaining('Error: '), findsOneWidget);
    expect(find.textContaining('connection refused'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });

  testWidgets('export failure snackbar OK action dismisses', (tester) async {
    await http.runWithClient(() async {
      await pumpPage(tester, size: const Size(1600, 3200));
      await tester.tap(find.text('CSV'));
      await _pumpN(tester, n: 5);
      expect(find.textContaining('Export failed'), findsOneWidget);
      await tester.tap(find.widgetWithText(SnackBarAction, 'OK'));
      await _pumpN(tester, n: 10);
    }, _okClient);
  });

  testWidgets(
      'mobile dark summary computes averages from vitals when dashboard is '
      'missing, then shows the no-data card', (tester) async {
    await http.runWithClient(() async {
      await pumpPage(tester,
          size: const Size(420, 3000), theme: ThemeData.dark());
    }, _okClient);

    expect(find.text('Latest Reading'), findsOneWidget);
    expect(find.text('3h ago'), findsOneWidget);

    // Drop the dashboard analytics so the summary falls back to vitals.
    final dynamic state = tester.state(find.byType(AnalyticsPage));
    state.dashboard = null;
    tester.element(find.byType(AnalyticsPage)).markNeedsBuild();
    await tester.pump();
    expect(find.text('Latest Reading'), findsOneWidget);
    expect(state.dashboard, isNull);

    // With no vitals either, the "No Health Data Available" card appears.
    state.vitals = <Vital>[];
    tester.element(find.byType(AnalyticsPage)).markNeedsBuild();
    await tester.pump();
    expect(find.text('No Health Data Available'), findsOneWidget);
  });

  testWidgets('desktop summary falls back to vitals-derived averages',
      (tester) async {
    await http.runWithClient(() async {
      await pumpPage(tester, size: const Size(1400, 3200));
    }, _okClient);
    final dynamic state = tester.state(find.byType(AnalyticsPage));
    state.dashboard = null;
    tester.element(find.byType(AnalyticsPage)).markNeedsBuild();
    await tester.pump();
    expect(find.byType(AnalyticsPage), findsOneWidget);
    expect((state.vitals as List).length, 3);
  });
}

class SocketExceptionLike implements Exception {
  final String message;
  const SocketExceptionLike(this.message);
  @override
  String toString() => 'SocketExceptionLike: $message';
}
