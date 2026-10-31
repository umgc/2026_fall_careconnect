// Additional coverage for CompetencyTrendScreen and BehavioralTrendScreen:
// non-JSON responses and the From / To pickers in the date range dialog.

import 'dart:convert';

import 'package:care_connect_app/features/dashboards/behavioral_trend_screen.dart';
import 'package:care_connect_app/features/dashboards/competency_trend_screen.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _weeks = ['2026-09-07', '2026-09-14', '2026-09-21', '2026-09-28'];

final _competency = {
  'status': 'IMPROVING',
  'weekLabels': _weeks,
  'activityTrends': [
    {
      'activityId': 1,
      'activityName': 'Bathing',
      'dataPoints': [
        for (final w in _weeks)
          {'weekStartDate': w, 'averageCompetencyScore': 3.0},
      ],
    },
  ],
};

final _behavioral = {
  'trend': 'UP',
  'weeklyCounts': [
    for (var i = 0; i < _weeks.length; i++)
      {'weekStartDate': _weeks[i], 'incidentCount': i},
  ],
  'topKeywords': ['agitation'],
};

void _install(String body) {
  ApiService.debugSetHttpClient(
      MockClient((req) async => http.Response(body, 200)));
  addTearDown(ApiService.debugResetHttpClient);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _pump(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: screen));
  await _settle(tester);
}

/// Opens the range dialog, confirms both date pickers, then applies.
Future<void> _pickBothDates(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.calendar_month));
  await tester.pumpAndSettle();
  expect(find.text('Select date range'), findsOneWidget);

  await tester.tap(find.text('From'));
  await tester.pumpAndSettle();
  expect(find.byType(DatePickerDialog), findsOneWidget);
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();

  await tester.tap(find.text('To'));
  await tester.pumpAndSettle();
  expect(find.byType(DatePickerDialog), findsOneWidget);
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();

  expect(find.text('Select date range'), findsOneWidget);
  await tester.tap(find.text('Apply'));
  await _settle(tester);
  expect(find.text('Select date range'), findsNothing);
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

  group('CompetencyTrendScreen', () {
    const screen = CompetencyTrendScreen(clientId: 9, clientName: 'Sam Lee');

    testWidgets('non-JSON body shows the exception text and Retry',
        (tester) async {
      _install('not json');
      await _pump(tester, screen);
      expect(find.textContaining('FormatException'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('From and To pickers update the range', (tester) async {
      _install(jsonEncode(_competency));
      await _pump(tester, screen);
      expect(find.text('Competency Trends'), findsOneWidget);
      await _pickBothDates(tester);
      expect(find.text('Date range:'), findsOneWidget);
    });
  });

  group('BehavioralTrendScreen', () {
    const screen = BehavioralTrendScreen(clientId: 11, clientName: 'Pat Kim');

    testWidgets('non-JSON body shows the exception text and Retry',
        (tester) async {
      _install('not json');
      await _pump(tester, screen);
      expect(find.textContaining('FormatException'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('From and To pickers update the range', (tester) async {
      _install(jsonEncode(_behavioral));
      await _pump(tester, screen);
      expect(find.text('Behavioral Frequency'), findsOneWidget);
      await _pickBothDates(tester);
      expect(find.text('Date range:'), findsOneWidget);
    });
  });
}
