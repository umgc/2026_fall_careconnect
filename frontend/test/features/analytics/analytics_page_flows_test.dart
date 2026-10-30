// Flow tests for AnalyticsPage (lib/features/analytics/analytics_page.dart):
// CSV/PDF export outcomes, and a filter change that fails after data has
// loaded so the AI chat is given the loaded vitals as context.
// AnalyticsPage uses top-level http calls (http.runWithClient).

import 'dart:convert';

import 'package:care_connect_app/features/analytics/analytics_page.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/widgets/ai_chat_improved.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _vitals(int count) => jsonEncode({
      'data': List.generate(count, (i) {
        return {
          'patientId': 1,
          'timestamp': DateTime.now()
              .subtract(Duration(days: count - i))
              .toIso8601String(),
          'heartRate': 70.0 + i,
          'spo2': 96.0 + i,
          'systolic': 118 + i,
          'diastolic': 78 + i,
          'weight': 160.0 - i,
          'moodValue': 4 + (i % 3),
          'painValue': 6 - (i % 3),
        };
      }),
    });

final _dashboard = jsonEncode({
  'adherenceRate': 90.0,
  'avgHeartRate': 72.0,
  'avgSpo2': 97.0,
  'avgSystolic': 120.0,
  'avgDiastolic': 80.0,
  'avgWeight': 165.0,
  'avgMood': 5.0,
  'avgPain': 4.0,
  'periodStart':
      DateTime.now().subtract(const Duration(days: 7)).toIso8601String(),
  'periodEnd': DateTime.now().toIso8601String(),
});

class _Backend {
  bool fail = false;
  int exportStatus = 200;

  MockClient client() => MockClient((req) async {
        final url = req.url.toString();
        if (url.contains('analytics/export')) {
          return http.Response('x', exportStatus,
              headers: {'content-disposition': 'attachment; filename="a.csv"'});
        }
        if (fail) return http.Response(jsonEncode({'error': 'down'}), 500);
        if (url.contains('analytics/vitals')) {
          return http.Response(_vitals(12), 200);
        }
        if (url.contains('analytics/dashboard')) {
          return http.Response(_dashboard, 200);
        }
        return http.Response('{}', 200);
      });
}

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

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final original = FlutterError.onError;
    FlutterError.onError = (d) {
      if (d.toString().contains('overflowed')) return;
      original?.call(d);
    };
    addTearDown(() => FlutterError.onError = original);
    await tester.pumpWidget(const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: AnalyticsPage(patientId: 1),
    ));
    await _pumpN(tester);
  }

  testWidgets('exports report failure off-web and on bad status',
      (tester) async {
    final backend = _Backend();
    await http.runWithClient(() async {
      await pumpPage(tester);
      await tester.tap(find.text('CSV'));
      await _pumpN(tester, n: 5);
      expect(find.textContaining('Export failed'), findsOneWidget);
      ScaffoldMessenger.of(tester.element(find.text('CSV')))
          .removeCurrentSnackBar();
      await _pumpN(tester, n: 5);

      backend.exportStatus = 500;
      await tester.tap(find.text('PDF'));
      await _pumpN(tester, n: 5);
      expect(find.textContaining('status 500'), findsOneWidget);
    }, backend.client);
  });

  testWidgets('a failed refresh keeps loaded vitals for the AI chat context',
      (tester) async {
    final backend = _Backend();
    await http.runWithClient(() async {
      await pumpPage(tester);
      backend.fail = true;
      await tester.tap(find.text('14 days'));
      await _pumpN(tester);
      expect(find.byType(FloatingActionButton), findsOneWidget);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      final chat = tester.widget<AIChat>(find.byType(AIChat));
      expect(chat.healthDataContext, contains('RECENT VITAL SIGNS'));
      expect(chat.healthDataContext, contains('TRENDS OVER PERIOD'));
      expect(chat.healthDataContext, contains('... and 2 more entries'));
    }, backend.client);
  });
}
