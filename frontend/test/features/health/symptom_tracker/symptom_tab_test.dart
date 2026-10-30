// Happy-path tests for SymptomTab and SymptomInputForm
// (lib/features/health/symptom-tracker/widgets/symptom_tab.dart,
//  symptom_input_form.dart): load, record and delete symptoms.

import 'dart:convert';

import 'package:care_connect_app/features/health/symptom-tracker/widgets/symptom_tab.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _requests = <String>[];
late http.Response Function(http.Request) _handler;
final _client = MockClient((r) async {
  _requests.add('${r.method} ${r.url.path}');
  return _handler(r);
});

http.Response _defaultHandler(http.Request r) {
  final now = DateTime.now();
  if (r.method == 'GET') {
    return http.Response(
      jsonEncode({
        'data': [
          {
            'id': 1,
            'symptomKey': 'Anxiety',
            'symptomValue': 'high',
            'severity': 5,
            'takenAt': now.subtract(const Duration(minutes: 5)).toIso8601String(),
            'clinicalNotes': 'Racing thoughts',
          },
          {
            'id': 2,
            'symptomKey': 'Insomnia',
            'severity': 3,
            'takenAt': now.subtract(const Duration(hours: 3)).toIso8601String(),
          },
          {
            'id': 3,
            'symptomKey': 'Fatigue',
            'takenAt': now.subtract(const Duration(days: 2)).toIso8601String(),
          },
          {'id': 4, 'symptomKey': 'Odd', 'takenAt': 'not-a-date'},
          {'id': 5, 'symptomKey': 'Unknown'},
        ],
      }),
      200,
    );
  }
  if (r.method == 'DELETE') return http.Response('', 204);
  return http.Response(jsonEncode({'data': {'id': 9}}), 201);
}

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1000, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    const MaterialApp(home: Scaffold(body: SymptomTab(patientId: '12'))),
  );
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUpAll(() => ApiService.debugSetHttpClient(_client));

  setUp(() {
    _requests.clear();
    _handler = _defaultHandler;
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => call.method == 'readAll' ? <String, String>{} : null,
    );
  });

  testWidgets('loads symptoms with relative times and deletes one',
      (tester) async {
    await _pump(tester);
    expect(find.text('Anxiety high'), findsOneWidget);
    expect(find.textContaining('m ago'), findsWidgets);
    expect(find.textContaining('h ago'), findsWidgets);
    expect(find.textContaining('d ago'), findsWidgets);
    expect(find.textContaining('not-a-date'), findsWidgets);
    expect(find.textContaining('Unknown time'), findsWidgets);

    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(_requests.where((r) => r.startsWith('DELETE')), hasLength(1));
  });

  testWidgets('records a new symptom', (tester) async {
    await _pump(tester);
    await tester.enterText(find.byType(TextField).first, 'Panic attack');
    await tester.enterText(find.byType(TextField).last, 'At night');
    final record = find.text('Record Symptom');
    await tester.ensureVisible(record);
    await tester.tap(record);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Panic attack'), findsOneWidget);
    expect(find.text('✅ Symptom saved'), findsOneWidget);
  });

  testWidgets('load failure shows error', (tester) async {
    _handler = (r) => http.Response('x', 500);
    await _pump(tester);
    expect(find.textContaining('Failed to load symptoms'), findsOneWidget);
    expect(find.text('No symptoms recorded yet'), findsOneWidget);
  });
}
