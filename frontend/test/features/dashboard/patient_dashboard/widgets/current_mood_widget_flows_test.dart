// Interaction tests for CurrentMoodWidget
// (lib/features/dashboard/patient_dashboard/widgets/current_mood_widget.dart):
// mood history parsing, last-four grid, slider changes and save outcomes.

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

class _OfflineUserProvider extends MockUserProvider {
  @override
  bool get isDeviceOnline => false;
}

late List<dynamic> _history;
late Future<http.Response> Function(http.Request) _onSave;
final _client = MockClient((request) async {
  if (request.method == 'POST') return _onSave(request);
  return http.Response(jsonEncode(_history), 200);
});

Future<void> _pump(
  WidgetTester tester, {
  UserProvider? provider,
  ValueChanged<double>? onAverage,
}) async {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider<UserProvider>.value(
      value: provider ?? MockUserProvider(),
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: CurrentMoodWidget(
              moodScore: 6,
              moodLabel: 'Great',
              moodTags: const ['calm'],
              date: DateTime.now().toUtc(),
              onAverageMoodChanged: onAverage,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _save(WidgetTester tester) async {
  final button = find.text('Save Mood');
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  setUpAll(() => ApiService.debugSetHttpClient(_client));

  setUp(() {
    final now = DateTime.now().toUtc();
    _history = [
      {
        'score': '8',
        'label': 'Great',
        'createdAt': now.toIso8601String(),
      },
      {
        'score': 3.6,
        'label': 'Down',
        'createdAt': now.subtract(const Duration(days: 1)).toIso8601String(),
      },
      {
        'score': 'abc',
        'label': '',
        'createdAt': now.subtract(const Duration(days: 3)).toIso8601String(),
      },
      {
        'score': 9,
        'label': 'Excellent',
        'createdAt': now.subtract(const Duration(days: 20)).toIso8601String(),
      },
    ];
    _onSave = (r) async => http.Response('{}', 200);
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => call.method == 'readAll' ? <String, String>{} : null,
    );
  });

  testWidgets('parses mixed history into the last four grid', (tester) async {
    double? average;
    await _pump(tester, onAverage: (v) => average = v);

    expect(find.text('Last 4 Moods'), findsOneWidget);
    // String score parsed, numeric score rounded, invalid score defaults to 5.
    expect(find.text('8/10 - Great'), findsOneWidget);
    expect(find.text('4/10 - Down'), findsOneWidget);
    expect(find.text('5/10 - Okay'), findsOneWidget);
    expect(find.text('9/10 - Excellent'), findsOneWidget);
    expect(find.text('Yesterday'), findsOneWidget);
    // Entries in the last 7 days average (8 + 4 + 5) / 3.
    expect(average, closeTo(17 / 3, 0.001));
    // Current label translation for "Great".
    expect(find.text('Great'), findsOneWidget);
  });

  testWidgets('slider change updates score and label', (tester) async {
    await _pump(tester);
    tester.widget<Slider>(find.byType(Slider)).onChanged!(2.0);
    await tester.pump();
    expect(find.text('2/10'), findsOneWidget);
    expect(find.text('Sad'), findsWidgets);
  });

  testWidgets('saving online shows saved message and adds entry',
      (tester) async {
    Map<String, dynamic>? body;
    _onSave = (r) async {
      body = jsonDecode(r.body) as Map<String, dynamic>;
      return http.Response('{}', 201);
    };
    double? average;
    await _pump(tester, onAverage: (v) => average = v);
    tester.widget<Slider>(find.byType(Slider)).onChanged!(10.0);
    await tester.pump();
    await _save(tester);

    expect(body, {'score': 10, 'label': 'Excellent'});
    expect(find.text('Mood saved successfully'), findsOneWidget);
    expect(find.text('10/10 - Excellent'), findsOneWidget);
    expect(average, closeTo(27 / 4, 0.001));
  });

  testWidgets('saving offline shows locally saved message', (tester) async {
    await _pump(tester, provider: _OfflineUserProvider());
    await _save(tester);
    expect(find.text('No internet: mood saved locally'), findsOneWidget);
  });

  testWidgets('queued save shows sync message', (tester) async {
    _onSave = (r) async =>
        http.Response('{}', 202, headers: {'x-offline-queued': 'true'});
    await _pump(tester);
    await _save(tester);
    expect(
      find.text('Mood queued for sync when internet is restored'),
      findsOneWidget,
    );
  });

  testWidgets('save failure shows error message', (tester) async {
    _onSave = (r) async => throw http.ClientException('offline');
    await _pump(tester);
    await _save(tester);
    expect(find.textContaining('Error saving mood: '), findsOneWidget);
  });

  testWidgets('history load failure keeps widget usable', (tester) async {
    _history = [
      {'score': 5, 'label': 'Okay', 'createdAt': 'not-a-date'},
    ];
    await _pump(tester);
    expect(find.text('Last 4 Moods'), findsNothing);
    expect(find.text('6/10'), findsOneWidget);
  });
}
