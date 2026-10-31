// Additional coverage for CurrentMoodWidget
// (lib/features/dashboard/patient_dashboard/widgets/current_mood_widget.dart):
// the mood sparkline painter and tolerant date parsing of history entries.

import 'dart:convert';
import 'dart:ui' as ui;

import 'package:care_connect_app/features/dashboard/patient_dashboard/widgets/current_mood_widget.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../mock_user_provider.dart';

late List<dynamic> _history;
final _client = MockClient((request) async {
  if (request.method == 'POST') return http.Response('{}', 200);
  return http.Response(jsonEncode(_history), 200);
});

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider<UserProvider>.value(
      value: MockUserProvider(),
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: SingleChildScrollView(
            child: CurrentMoodWidget(
              moodScore: 6,
              moodLabel: 'Great',
              moodTags: ['calm'],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

CustomPainter _sparkline(WidgetTester tester) {
  final paints = tester
      .widgetList<CustomPaint>(find.descendant(
        of: find.byType(CurrentMoodWidget),
        matching: find.byType(CustomPaint),
      ))
      .where((w) =>
          w.painter != null &&
          w.painter.runtimeType.toString() == '_MoodSparklinePainter')
      .toList();
  expect(paints, hasLength(1));
  return paints.single.painter!;
}

void _paint(CustomPainter painter, Size size) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  painter.paint(canvas, size);
  recorder.endRecording().dispose();
}

void main() {
  setUpAll(() => ApiService.debugSetHttpClient(_client));

  setUp(() {
    final now = DateTime.now().toUtc();
    _history = [
      {'score': 8, 'label': 'Great', 'createdAt': now.toIso8601String()},
      {
        'score': 3,
        'label': 'Down',
        'createdAt': now.subtract(const Duration(days: 2)).toIso8601String(),
      },
    ];
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => call.method == 'readAll' ? <String, String>{} : null,
    );
  });

  testWidgets('sparkline painter draws the 7-day trend on a real canvas',
      (tester) async {
    await _pump(tester);
    expect(find.text('Last 4 Moods'), findsOneWidget);

    final painter = _sparkline(tester);
    // Draws the full chart (baseline, fill, line and end marker).
    _paint(painter, const Size(240, 54));
    // Too small to draw: returns early without throwing.
    _paint(painter, const Size(4, 4));
    expect(painter.shouldRepaint(painter), isFalse);
  });

  testWidgets('history entries with string or invalid dates still render',
      (tester) async {
    await _pump(tester);
    final dynamic state = tester.state(find.byType(CurrentMoodWidget));
    final today = DateTime.now().toUtc();
    state.moodHistory = <Map<String, dynamic>>[
      {'score': 7, 'label': 'Happy', 'date': today.toIso8601String()},
      {'score': 6, 'label': 'Okay', 'date': 'not-a-date'},
      {'score': 4, 'label': 'Down', 'date': 12345},
    ];
    tester.element(find.byType(CurrentMoodWidget)).markNeedsBuild();
    await tester.pump();

    expect(find.text('7/10 - Happy'), findsOneWidget);
    expect(find.text('6/10 - Okay'), findsOneWidget);
    expect(find.text('4/10 - Down'), findsOneWidget);

    // A single-point trend still paints (zero step width).
    _paint(_sparkline(tester), const Size(120, 54));
  });
}
