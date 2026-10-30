// Happy-path tests for AllergiesTab and AllergyInputForm
// (lib/features/health/symptom-tracker/widgets/allergies_tab.dart,
//  allergies_input_form.dart): load, add and delete drug allergies.

import 'dart:convert';

import 'package:care_connect_app/features/health/symptom-tracker/widgets/allergies_tab.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../mock_user_provider.dart';

final _requests = <String>[];
late http.Response Function(http.Request) _handler;
final _client = MockClient((r) async {
  _requests.add('${r.method} ${r.url.path}');
  return _handler(r);
});

http.Response _defaultHandler(http.Request r) {
  if (r.method == 'GET') {
    return http.Response(
      jsonEncode({'data': [
        {'id': 1, 'allergen': 'Penicillin', 'severity': 'SEVERE', 'reaction': 'Hives'},
        {'id': 2, 'allergen': 'Codeine'},
      ]}),
      200,
    );
  }
  if (r.method == 'DELETE') return http.Response('', 204);
  return http.Response(
    jsonEncode({'id': 3, 'allergen': 'Aspirin', 'severity': 'MODERATE'}),
    201,
  );
}

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1000, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await http.runWithClient(() async {
    await tester.pumpWidget(
      ChangeNotifierProvider<UserProvider>.value(
        value: MockUserProvider(
          mockUser: MockUser(id: 1, role: 'PATIENT', patientId: 12),
        ),
        child: const MaterialApp(
          home: Scaffold(body: AllergiesTab(patientId: '12')),
        ),
      ),
    );
    await tester.pump();
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }, () => _client);
}

void main() {
  setUpAll(() => ApiService.debugSetHttpClient(_client));

  setUp(() {
    _requests.clear();
    _handler = _defaultHandler;
    SharedPreferences.setMockInitialValues({});
    final expiry =
        (DateTime.now().millisecondsSinceEpoch ~/ 1000 + 86400).toString();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        final key = (call.arguments as Map?)?['key'];
        if (call.method == 'read') {
          if (key == 'jwt_token') return 'test-jwt';
          if (key == 'token_expiry') return expiry;
        }
        if (call.method == 'readAll') return <String, String>{};
        return null;
      },
    );
  });

  testWidgets('loads allergies and deletes one', (tester) async {
    await _pump(tester);
    expect(find.text('Penicillin'), findsOneWidget);
    expect(find.text('Codeine'), findsOneWidget);

    await tester.tap(find.byType(IconButton).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Allergy deleted successfully'), findsOneWidget);
    expect(_requests.where((r) => r.startsWith('DELETE')), hasLength(1));
  });

  testWidgets('failed delete reports failure', (tester) async {
    _handler = (r) => r.method == 'DELETE'
        ? http.Response('no', 500)
        : _defaultHandler(r);
    await _pump(tester);
    await tester.tap(find.byType(IconButton).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Failed to delete allergy'), findsOneWidget);
  });

  testWidgets('adds an allergy through the form', (tester) async {
    await _pump(tester);
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Aspirin');
    await tester.enterText(fields.at(1), 'Rash');

    await tester.tap(find.text('Mild (Minor symptoms)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Moderate (Noticeable symptoms)').last);
    await tester.pumpAndSettle();

    await http.runWithClient(() async {
      final add = find.text('Add Drug Allergy').last;
      await tester.ensureVisible(add);
      await tester.tap(add);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }, () => _client);

    expect(find.text('Aspirin'), findsOneWidget);
    expect(_requests.where((r) => r.startsWith('POST')), hasLength(2));
  });

  testWidgets('empty form shows required-fields message', (tester) async {
    await _pump(tester);
    final add = find.text('Add Drug Allergy').last;
    await tester.ensureVisible(add);
    await tester.tap(add);
    await tester.pump();
    expect(find.text('Please complete all required fields.'), findsOneWidget);
  });

  testWidgets('load failure shows error', (tester) async {
    _handler = (r) => http.Response('x', 500);
    await _pump(tester);
    expect(find.textContaining('Failed to load allergies'), findsOneWidget);
  });
}
