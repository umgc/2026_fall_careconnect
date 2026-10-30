// Flow tests for CaregiverAnalyticsTab (lib/screens/tabs/caregiver_tabs.dart):
// patient loading, sentiment + mood history, the sort/label/plot/timeframe
// controls, the custom date-range dialog and the error states.
// HTTP goes through the ApiService.debugSetHttpClient test seam.

import 'dart:convert';

import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/screens/tabs/caregiver_tabs.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:care_connect_app/widgets/post_call_telemetry_summary_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../mock_user_provider.dart';

class _Backend {
  int patientsStatus = 200;
  Object patients = [
    {
      'link': {'patientUserId': 20},
      'patient': {'firstName': 'Ana', 'lastName': 'Diaz'},
    },
    {
      'link': {'patientUserId': 21, 'patientName': 'Linked Only'},
    },
    {
      'patient': {'userId': 22},
    },
    {
      'link': {'patientUserId': 20},
    },
    'garbage',
  ];
  Object sentiment = const [];
  Object mood = const [];

  void install() {
    ApiService.debugSetHttpClient(MockClient((req) async {
      final path = req.url.path;
      if (RegExp(r'caregivers/\d+/patients').hasMatch(path)) {
        return http.Response(jsonEncode(patients), patientsStatus);
      }
      if (path.endsWith('/sentiment-history')) {
        return http.Response(jsonEncode(sentiment), 200);
      }
      if (path.endsWith('/mood')) {
        return http.Response(jsonEncode(mood), 200);
      }
      return http.Response('{}', 404);
    }));
    addTearDown(ApiService.debugResetHttpClient);
  }
}

String _ago(Duration d) => DateTime.now().subtract(d).toIso8601String();

List<Map<String, dynamic>> _sentiment() => [
      {
        'callId': 'chime_call_123456',
        'callDate': _ago(const Duration(hours: 2)),
        'overallLabel': 'CALM',
        'overallScore': 0.9,
        'durationMinutes': 12,
      },
      {
        'callId': 'call-ab',
        'callDate': _ago(const Duration(days: 2)),
        'overallLabel': 'ANXIOUS',
        'overallScore': 0.5,
        'durationMinutes': '7',
      },
      {
        'callId': '',
        'callDate': _ago(const Duration(days: 5)),
        'overallLabel': 'DISTRESSED',
        'overallScore': 0.1,
      },
      {
        'callId': 'twilio-call-zz99',
        'callDate': 'not a date',
        'overallLabel': 'CALM',
        'overallScore': '0.8',
      },
    ];

List<Map<String, dynamic>> _mood() => [
      {
        'createdAt': _ago(const Duration(hours: 5)),
        'score': 8,
        'notes': 'Good day',
      },
      {
        'timestamp': _ago(const Duration(days: 1)),
        'moodValue': 0.4,
        'note': '',
      },
      {
        'date': _ago(const Duration(days: 3)),
        'value': 0.1,
        'description': 'Low',
      },
      {'takenAt': _ago(const Duration(days: 4)), 'value': -5},
    ];

Widget _wrap(UserProvider provider) => ChangeNotifierProvider<UserProvider>.value(
      value: provider,
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: CaregiverAnalyticsTab(),
      ),
    );

MockUserProvider _caregiver({int? caregiverId = 5}) => MockUserProvider(
      mockUser: MockUser(
          id: 2, role: 'CAREGIVER', patientId: null, caregiverId: caregiverId),
    );

void _bigView(WidgetTester tester) {
  // The fixed-width filter dropdowns overflow with the test font; only those
  // layout reports are dropped.
  final original = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.toString().contains('overflowed')) return;
    original?.call(details);
  };
  addTearDown(() => FlutterError.onError = original);
  tester.view.physicalSize = const Size(1400, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> _choose(WidgetTester tester, String current, String next) async {
  expect(find.text(current), findsWidgets, reason: current);
  await tester.tap(find.text(current).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(next).last);
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

  testWidgets('loads a patient history and drives every control',
      (tester) async {
    _bigView(tester);
    (_Backend()
          ..sentiment = _sentiment()
          ..mood = _mood())
        .install();
    await tester.pumpWidget(_wrap(_caregiver()));
    await tester.pumpAndSettle();
    expect(find.text('Select a patient to load analytics.'), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    expect(find.text('Linked Only').last, findsOneWidget);
    expect(find.text('Patient 22').last, findsOneWidget);
    await tester.tap(find.text('Ana Diaz').last);
    await tester.pumpAndSettle();

    expect(find.text('Longitudinal Sentiment Trend'), findsOneWidget);
    expect(find.text('Telehealth call #3456'), findsWidgets);
    expect(find.textContaining('Mood entry - '), findsWidgets);
    expect(find.text('Good day'), findsOneWidget);
    expect(find.text('No notes'), findsWidgets);

    // Sort orders.
    await _choose(tester, 'Newest first', 'Oldest first');
    await _choose(tester, 'Oldest first', 'Highest score');
    await _choose(tester, 'Highest score', 'Lowest score');

    // Label filters.
    await _choose(tester, 'All labels', 'Calm');
    await _choose(tester, 'Calm', 'Anxious');
    await _choose(tester, 'Anxious', 'Distressed');
    await _choose(tester, 'Distressed', 'All labels');

    // Plot filters.
    await _choose(tester, 'All metrics', 'Calls');
    await _choose(tester, 'Calls', 'Mood');
    await _choose(tester, 'Mood', 'All metrics');

    // Timeframes.
    await _choose(tester, 'Last 7 days', 'Last 24 hours');
    await _choose(tester, 'Last 24 hours', 'Last 180 days');

    // Custom range: cancel first, then pick and apply.
    await _choose(tester, 'Last 180 days', 'Custom range');
    expect(find.text('Select Date Range'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    // The field keeps showing the cancelled choice; move off it and back.
    await _choose(tester, 'Custom range', 'Last 30 days');
    await _choose(tester, 'Last 30 days', 'Custom range');
    await tester.tap(find.textContaining('End: '));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1').last);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Start: '));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    // Refresh reloads the patient list and clears the selection.
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(find.text('Select a patient to load analytics.'), findsOneWidget);
  });

  testWidgets('tapping a call row opens the call summary', (tester) async {
    _bigView(tester);
    (_Backend()..sentiment = _sentiment()).install();
    await tester.pumpWidget(_wrap(_caregiver()));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ana Diaz').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Telehealth call #3456').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(PostCallTelemetrySummaryScreen), findsOneWidget);
  });

  testWidgets('patient with no history shows the empty card', (tester) async {
    _bigView(tester);
    _Backend().install();
    await tester.pumpWidget(_wrap(_caregiver()));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ana Diaz').last);
    await tester.pumpAndSettle();
    expect(
        find.text('No sentiment or mood history found for this patient yet.'),
        findsOneWidget);
  });

  testWidgets('patient list errors are shown', (tester) async {
    _bigView(tester);
    await tester.pumpWidget(_wrap(_caregiver(caregiverId: null)));
    await tester.pumpAndSettle();
    expect(find.textContaining('No caregiver profile is linked'),
        findsOneWidget);

    final b = _Backend()..patientsStatus = 500;
    b.install();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_wrap(_caregiver()));
    await tester.pumpAndSettle();
    expect(find.textContaining('Failed to load caregiver patients (500)'),
        findsOneWidget);

    b
      ..patientsStatus = 200
      ..patients = {'not': 'a list'};
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Unexpected caregiver patient payload'),
        findsOneWidget);
  });
}
