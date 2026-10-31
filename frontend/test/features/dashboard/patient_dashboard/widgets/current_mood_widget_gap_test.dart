// Gap-coverage tests for CurrentMoodWidget: 7-day summary status variants,
// localized mood tags and labels, and the date label. Uses the ApiService
// MockClient seam so no real network is touched.
import 'dart:convert';

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
final _client = MockClient(
  (request) async => http.Response(jsonEncode(_history), 200),
);

List<Map<String, dynamic>> _entries(List<int> scores) {
  final now = DateTime.now().toUtc();
  return [
    for (var i = 0; i < scores.length; i++)
      {
        'score': scores[i],
        'label': 'Okay',
        'createdAt': now.subtract(Duration(hours: i)).toIso8601String(),
      },
  ];
}

Future<void> _pump(
  WidgetTester tester, {
  Locale locale = const Locale('en'),
  List<String> tags = const ['calm'],
  DateTime? date,
  String label = 'Okay',
  int score = 5,
}) async {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider<UserProvider>.value(
      value: MockUserProvider(),
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: CurrentMoodWidget(
              moodScore: score,
              moodLabel: label,
              moodTags: tags,
              date: date,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  setUpAll(() => ApiService.debugSetHttpClient(_client));

  setUp(() {
    _history = [];
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => call.method == 'readAll' ? <String, String>{} : null,
    );
  });

  testWidgets('low average shows low mood trend in the error color', (
    tester,
  ) async {
    _history = _entries([2, 3, 4]);
    await _pump(tester);
    expect(find.text('Low mood trend'), findsOneWidget);
    final ctx = tester.element(find.text('Low mood trend'));
    expect(
      tester.widget<Text>(find.text('Low mood trend')).style!.color,
      Theme.of(ctx).colorScheme.error,
    );
    expect(find.text('3.0'), findsOneWidget);
  });

  testWidgets('mid average shows stable trend in orange', (tester) async {
    _history = _entries([6, 6, 7]);
    await _pump(tester);
    expect(find.text('Stable mood trend'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('Stable mood trend')).style!.color,
      Colors.orange.shade700,
    );
    expect(find.text('6.3'), findsOneWidget);
  });

  testWidgets('high average shows positive trend in green with ring value', (
    tester,
  ) async {
    _history = _entries([9, 10, 8]);
    await _pump(tester);
    expect(find.text('Positive mood trend'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('Positive mood trend')).style!.color,
      Colors.green.shade700,
    );
    final ring = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(ring.value, closeTo(0.9, 0.001));
  });

  testWidgets('no history hides the summary card', (tester) async {
    await _pump(tester);
    expect(find.text('Last 4 Moods'), findsNothing);
    expect(find.text('Low mood trend'), findsNothing);
    expect(find.text('Stable mood trend'), findsNothing);
    expect(find.text('Positive mood trend'), findsNothing);
  });

  testWidgets('mood tags are localized (Spanish)', (tester) async {
    await _pump(
      tester,
      locale: const Locale('es'),
      tags: const [
        'happy',
        'calm',
        'positive',
        'comfortable',
        'stable',
        'neutral',
        'watchful',
        'low',
        'monitoring',
        'no recent mood data',
        'custom tag',
      ],
    );
    for (final t in [
      'feliz',
      'tranquilo',
      'positivo',
      'cómodo',
      'estable',
      'neutral',
      'alerta',
      'bajo',
      'en seguimiento',
      'no hay datos recientes sobre el estado de ánimo',
      'custom tag',
    ]) {
      expect(find.text(t), findsWidgets, reason: t);
    }
    expect(find.text('happy'), findsNothing);
  });

  testWidgets('every score maps to an emoji and a translated label', (
    tester,
  ) async {
    final expected = {
      10: ('\u{1F60A}', 'Excellent'),
      9: ('\u{1F601}', 'Great'),
      8: ('\u{1F604}', 'Happy'),
      7: ('\u{1F60A}', 'Happy'),
      6: ('\u{1F642}', 'Okay'),
      5: ('\u{1F610}', 'Okay'),
      4: ('\u{1F615}', 'Down'),
      3: ('\u{1F641}', 'Down'),
      2: ('\u{2639}\u{FE0F}', 'Sad'),
      1: ('\u{1F61E}', 'Sad'),
      0: ('\u{1F614}', 'Sad'),
    };
    final slider = find.byType(Slider);
    await _pump(tester);
    for (final e in expected.entries) {
      if (e.key >= 1) {
        tester.widget<Slider>(slider).onChanged!(e.key.toDouble());
        await tester.pump();
        expect(find.text('${e.key}/10'), findsOneWidget);
        expect(find.text(e.value.$1), findsWidgets, reason: 'emoji ${e.key}');
        expect(find.text(e.value.$2), findsWidgets, reason: 'label ${e.key}');
      }
    }
  });

  testWidgets('score 0 initial state shows the fallback emoji', (tester) async {
    await _pump(tester, score: 0, label: 'Sad');
    expect(find.text('\u{1F614}'), findsOneWidget);
    expect(find.text('0/10'), findsOneWidget);
  });

  testWidgets('date label shows Yesterday and month/day for older dates', (
    tester,
  ) async {
    final now = DateTime.now().toUtc();
    await _pump(tester, date: now.subtract(const Duration(days: 1, hours: 1)));
    expect(find.text('Yesterday'), findsOneWidget);

    final old = now.subtract(const Duration(days: 30));
    await _pump(tester, date: old);
    await tester.pump();
    expect(find.text('${old.month}/${old.day}'), findsOneWidget);
  });
}
