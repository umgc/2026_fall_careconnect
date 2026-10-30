// Tests for ClientCategoryActivitiesScreen
// (lib/features/activities/presentation/pages/client_category_activities_screen.dart).
// HTTP goes through the ApiService.debugSetHttpClient test seam.

import 'dart:convert';

import 'package:care_connect_app/features/activities/presentation/pages/client_category_activities_screen.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrap({String category = 'ADL'}) => MaterialApp(
      home: ClientCategoryActivitiesScreen(
        clientId: 7,
        clientName: 'Jamie Lee',
        category: category,
      ),
    );

void _setLargeViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

class _Backend {
  int clientStatus = 200;
  Object clientBody = const [];
  int allStatus = 200;
  Object allBody = const [];
  int putStatus = 200;
  bool throwOnClient = false;
  bool throwOnPut = false;
  final List<String> puts = [];

  void install() {
    ApiService.debugSetHttpClient(MockClient((req) async {
      final path = req.url.path;
      if (req.method == 'PUT') {
        if (throwOnPut) throw Exception('put failed');
        puts.add(req.url.toString());
        return http.Response('{}', putStatus);
      }
      if (path.contains('/clients/')) {
        if (throwOnClient) throw Exception('network down');
        return http.Response(jsonEncode(clientBody), clientStatus);
      }
      if (path.endsWith('/activities')) {
        return http.Response(jsonEncode(allBody), allStatus);
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

  testWidgets('log mode shows enabled backend activities for the category',
      (tester) async {
    _setLargeViewport(tester);
    final b = _Backend()
      ..clientBody = [
        {'id': 1, 'name': 'Bathing', 'category': 'ADL', 'enabled': true},
        {'id': 2, 'name': 'Laundry', 'category': 'IADL', 'enabled': true},
      ];
    b.install();
    await tester.pumpWidget(_wrap());
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await _settle(tester);

    expect(find.text('ADL Activities'), findsOneWidget);
    expect(find.text('Jamie Lee'), findsWidgets);
    expect(find.text('Bathing'), findsOneWidget);
    expect(find.text('Laundry'), findsNothing);
  });

  testWidgets('log mode shows empty message when nothing is enabled',
      (tester) async {
    _setLargeViewport(tester);
    _Backend().install();
    await tester.pumpWidget(_wrap());
    await _settle(tester);
    expect(
      find.text(
          'No activities enabled. Switch to Manage Activities to enable some.'),
      findsOneWidget,
    );
  });

  testWidgets('log mode falls back to locally enabled defaults',
      (tester) async {
    _setLargeViewport(tester);
    SharedPreferences.setMockInitialValues({
      'activity_enabled_names:7:IADL': ['Laundry', 'Shopping'],
    });
    _Backend().install();
    await tester.pumpWidget(_wrap(category: 'IADL'));
    await _settle(tester);
    expect(find.text('Laundry'), findsOneWidget);
    expect(find.text('Shopping'), findsOneWidget);
  });

  testWidgets('log mode shows status error on non-200', (tester) async {
    _setLargeViewport(tester);
    (_Backend()..clientStatus = 500).install();
    await tester.pumpWidget(_wrap());
    await _settle(tester);
    expect(find.text('Failed to load: 500'), findsOneWidget);
  });

  testWidgets('log mode shows exception error', (tester) async {
    _setLargeViewport(tester);
    (_Backend()..throwOnClient = true).install();
    await tester.pumpWidget(_wrap());
    await _settle(tester);
    expect(find.textContaining('Error:'), findsOneWidget);
  });

  testWidgets('manage mode lists backend activities and toggles them on/off',
      (tester) async {
    _setLargeViewport(tester);
    final b = _Backend()
      ..allBody = [
        {'id': 1, 'name': 'Bathing', 'category': 'ADL'},
        {
          'id': 2,
          'name': 'Dressing',
          'category': 'ADL',
          'defaultIconUrl': 'https://example.test/dress.png'
        },
      ]
      ..clientBody = [
        {'id': 1, 'name': 'Bathing', 'category': 'ADL', 'enabled': true},
      ];
    b.install();
    await tester.pumpWidget(_wrap());
    await _settle(tester);

    await tester.tap(find.text('Manage Activities'));
    await _settle(tester);

    expect(find.text('Bathing'), findsOneWidget);
    expect(find.text('Dressing'), findsOneWidget);
    expect(find.byType(Switch), findsNWidgets(2));

    // Enable Dressing.
    await tester.tap(find.byType(Switch).at(1));
    await _settle(tester);
    // Disable Bathing.
    await tester.tap(find.byType(Switch).at(0));
    await _settle(tester);
    expect(b.puts.length, 2);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('activity_enabled_names:7:ADL'),
        contains('Dressing'));

    // Back to Log mode reloads because the log was invalidated.
    await tester.tap(find.text('Log Activities'));
    await _settle(tester);
    expect(find.text('Log Activities'), findsOneWidget);
  });

  testWidgets('manage mode falls back to default ADL list and reports put error',
      (tester) async {
    _setLargeViewport(tester);
    final b = _Backend()
      ..allStatus = 404
      ..putStatus = 500;
    b.install();
    await tester.pumpWidget(_wrap());
    await _settle(tester);
    await tester.tap(find.text('Manage Activities'));
    await _settle(tester);

    expect(find.text('Bathing'), findsOneWidget);
    expect(find.text('Personal Hygiene & Grooming'), findsOneWidget);

    await tester.tap(find.byType(Switch).first);
    await _settle(tester);
    expect(find.text('Failed to update: 500'), findsOneWidget);
  });

  testWidgets('manage mode shows snackbar when the toggle throws',
      (tester) async {
    _setLargeViewport(tester);
    (_Backend()..throwOnPut = true).install();
    await tester.pumpWidget(_wrap(category: 'IADL'));
    await _settle(tester);
    await tester.tap(find.text('Manage Activities'));
    await _settle(tester);
    expect(find.text('Meal Preparation'), findsOneWidget);
    await tester.tap(find.byType(Switch).first);
    await _settle(tester);
    expect(find.textContaining('Error: Exception: put failed'), findsOneWidget);
  });

  testWidgets('manage mode falls back to defaults when the request throws',
      (tester) async {
    _setLargeViewport(tester);
    (_Backend()..throwOnClient = true).install();
    await tester.pumpWidget(_wrap());
    await _settle(tester);
    await tester.tap(find.text('Manage Activities'));
    await _settle(tester);
    expect(find.text('Bathing'), findsOneWidget);
  });

  testWidgets('manage mode shows empty message for unknown category',
      (tester) async {
    _setLargeViewport(tester);
    _Backend().install();
    await tester.pumpWidget(_wrap(category: 'OTHER'));
    await _settle(tester);
    await tester.tap(find.text('Manage Activities'));
    await _settle(tester);
    expect(find.text('No activities defined for this category.'),
        findsOneWidget);
  });
}
