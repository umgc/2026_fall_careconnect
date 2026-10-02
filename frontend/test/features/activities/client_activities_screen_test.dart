// Tests for ClientActivitiesScreen, ActivitiesGrid and LogActivitySheet
// (lib/features/activities/presentation/pages/client_activities_screen.dart).
// HTTP goes through the ApiService.debugSetHttpClient test seam.

import 'dart:convert';

import 'package:care_connect_app/features/activities/presentation/pages/client_activities_screen.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Widget _wrap() => const MaterialApp(
      home: ClientActivitiesScreen(clientId: 5, clientName: 'Alex Rivera'),
    );

void _setLargeViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

final _activities = [
  {'id': 1, 'name': 'Bathing', 'category': 'ADL', 'enabled': true},
  {'id': 2, 'name': 'Dressing', 'category': 'adl', 'enabled': true},
  {'id': 3, 'name': 'Toileting', 'category': 'ADL', 'enabled': false},
  {'id': 4, 'name': 'Meal prep', 'category': 'IADL', 'enabled': true},
];

/// Fake backend for the activities list, the competency scale and the
/// activity-log POST. Records the last POST body.
class _Backend {
  int activitiesStatus = 200;
  Object activitiesBody = _activities;
  int scaleStatus = 200;
  Object scaleBody = [
    {'value': 1, 'label': 'Needs help'},
    {'value': 5, 'label': 'On their own'},
  ];
  int logStatus = 201;
  String logBody = '';
  Map<String, dynamic>? lastLog;

  void install() {
    ApiService.debugSetHttpClient(MockClient((req) async {
      final path = req.url.path;
      if (req.method == 'POST') {
        lastLog = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(logBody, logStatus);
      }
      if (path.endsWith('/competency-scale')) {
        return http.Response(jsonEncode(scaleBody), scaleStatus);
      }
      if (path.endsWith('/activities')) {
        return http.Response(jsonEncode(activitiesBody), activitiesStatus);
      }
      return http.Response('', 404);
    }));
    addTearDown(ApiService.debugResetHttpClient);
  }
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _openSheet(WidgetTester tester, String activity) async {
  await tester.tap(find.text(activity));
  await _settle(tester);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

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

  group('ClientActivitiesScreen – loading', () {
    testWidgets('shows a spinner, then the client name and tabs',
        (tester) async {
      _setLargeViewport(tester);
      _Backend().install();
      await tester.pumpWidget(_wrap());
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await _settle(tester);

      expect(find.text('Alex Rivera'), findsOneWidget);
      expect(find.text('ADL'), findsOneWidget);
      expect(find.text('IADL'), findsOneWidget);
    });

    testWidgets('lists enabled ADL activities and hides disabled ones',
        (tester) async {
      _setLargeViewport(tester);
      _Backend().install();
      await tester.pumpWidget(_wrap());
      await _settle(tester);

      expect(find.text('Bathing'), findsOneWidget);
      // Category is matched case-insensitively.
      expect(find.text('Dressing'), findsOneWidget);
      expect(find.text('Toileting'), findsNothing);
    });

    testWidgets('IADL tab shows the IADL activities', (tester) async {
      _setLargeViewport(tester);
      _Backend().install();
      await tester.pumpWidget(_wrap());
      await _settle(tester);

      await tester.tap(find.text('IADL'));
      await _settle(tester);
      expect(find.text('Meal prep'), findsOneWidget);
    });

    testWidgets('shows the empty message when nothing is enabled',
        (tester) async {
      _setLargeViewport(tester);
      (_Backend()..activitiesBody = []).install();
      await tester.pumpWidget(_wrap());
      await _settle(tester);
      expect(find.textContaining('No activities enabled'), findsOneWidget);
    });

    testWidgets('shows the status code when loading fails', (tester) async {
      _setLargeViewport(tester);
      (_Backend()..activitiesStatus = 500).install();
      await tester.pumpWidget(_wrap());
      await _settle(tester);
      expect(find.text('Failed to load activities: 500'), findsOneWidget);
    });

    testWidgets('shows the error when the body is not a list', (tester) async {
      _setLargeViewport(tester);
      (_Backend()..activitiesBody = {'not': 'a list'}).install();
      await tester.pumpWidget(_wrap());
      await _settle(tester);
      expect(find.textContaining('Error:'), findsOneWidget);
    });
  });

  group('LogActivitySheet', () {
    testWidgets('opens with the activity name and the server scale',
        (tester) async {
      _setLargeViewport(tester);
      _Backend().install();
      await tester.pumpWidget(_wrap());
      await _settle(tester);
      await _openSheet(tester, 'Bathing');

      expect(find.text('Competency Score'), findsOneWidget);
      expect(find.text('1 — Needs help'), findsOneWidget);
      expect(find.text('5 — On their own'), findsOneWidget);
      expect(find.text('Client Satisfaction (optional)'), findsOneWidget);
      expect(find.text('Notes (optional)'), findsOneWidget);
    });

    testWidgets('falls back to the default scale when the GET fails',
        (tester) async {
      _setLargeViewport(tester);
      (_Backend()..scaleStatus = 500).install();
      await tester.pumpWidget(_wrap());
      await _settle(tester);
      await _openSheet(tester, 'Bathing');

      expect(find.text('3 — Moderate Assistance'), findsOneWidget);
      expect(
        find.text('Using default competency scale (GET failed: 500)'),
        findsOneWidget,
      );
    });

    testWidgets('falls back to the default scale when the list is empty',
        (tester) async {
      _setLargeViewport(tester);
      (_Backend()..scaleBody = {'items': []}).install();
      await tester.pumpWidget(_wrap());
      await _settle(tester);
      await _openSheet(tester, 'Bathing');

      expect(find.text('5 — Independent'), findsOneWidget);
      expect(find.text('Using default competency scale'), findsOneWidget);
    });

    testWidgets('falls back to the default scale on a bad body',
        (tester) async {
      _setLargeViewport(tester);
      final backend = _Backend()..install();
      ApiService.debugSetHttpClient(MockClient((req) async {
        if (req.url.path.endsWith('/competency-scale')) {
          return http.Response('not json', 200);
        }
        return http.Response(jsonEncode(backend.activitiesBody), 200);
      }));
      await tester.pumpWidget(_wrap());
      await _settle(tester);
      await _openSheet(tester, 'Bathing');

      expect(
        find.text('Using default competency scale (network error)'),
        findsOneWidget,
      );
    });

    testWidgets('Log Activity is disabled until a score is picked',
        (tester) async {
      _setLargeViewport(tester);
      _Backend().install();
      await tester.pumpWidget(_wrap());
      await _settle(tester);
      await _openSheet(tester, 'Bathing');

      FilledButton button() =>
          tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button().onPressed, isNull);

      await tester.tap(find.text('5 — On their own'));
      await tester.pump();
      expect(button().onPressed, isNotNull);
    });

    testWidgets('submits score, satisfaction and notes, then confirms',
        (tester) async {
      _setLargeViewport(tester);
      final backend = _Backend()..install();
      await tester.pumpWidget(_wrap());
      await _settle(tester);
      await _openSheet(tester, 'Bathing');

      await tester.tap(find.text('1 — Needs help'));
      await tester.pump();
      for (final emoji in ['😫', '😕', '😐', '😄', '🙂']) {
        await tester.tap(find.text(emoji));
        await tester.pump();
      }
      await tester.enterText(find.byType(TextField), '  needed a reminder  ');
      await tester.pump();

      await tester.tap(find.text('Log Activity'));
      await _settle(tester);

      expect(backend.lastLog, isNotNull);
      expect(find.text('Activity logged'), findsOneWidget);
      expect(find.text('Competency Score'), findsNothing);
    });

    testWidgets('shows the server error when the POST fails', (tester) async {
      _setLargeViewport(tester);
      (_Backend()
            ..logStatus = 400
            ..logBody = 'bad score')
          .install();
      await tester.pumpWidget(_wrap());
      await _settle(tester);
      await _openSheet(tester, 'Bathing');

      await tester.tap(find.text('5 — On their own'));
      await tester.pump();
      await tester.tap(find.text('Log Activity'));
      await _settle(tester);

      expect(find.textContaining('Failed to log: 400'), findsOneWidget);
      // The sheet stays open so the caregiver can retry.
      expect(find.text('Competency Score'), findsOneWidget);
    });
  });
}
