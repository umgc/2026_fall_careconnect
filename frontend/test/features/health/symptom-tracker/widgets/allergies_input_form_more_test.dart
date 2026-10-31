// More happy-path tests for AllergyInputForm
// (lib/features/health/symptom-tracker/widgets/allergies_input_form.dart):
// the AI voice result filling the fields (each severity, and the drug read
// from the transcript), the AI failure, and submit outcomes.
import 'dart:async';
import 'dart:convert';

import 'package:care_connect_app/features/health/symptom-tracker/widgets/allergies_input_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Closes the voice assistant page as soon as it is pushed, returning
/// [transcript] to the form.
class _Voice extends NavigatorObserver {
  _Voice(this.transcript);
  String transcript;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute == null || route is! PageRoute) return;
    scheduleMicrotask(() => route.navigator?.removeRoute(route, transcript));
  }
}

void main() {
  late http.Response Function(http.Request) handler;
  final requests = <http.Request>[];

  setUp(() {
    requests.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        if (call.method != 'read') return null;
        final key = (call.arguments as Map<Object?, Object?>)['key'];
        if (key == 'jwt_token') return 'test-jwt';
        if (key == 'token_expiry') return '4102444800';
        return null;
      },
    );
    handler = (_) => http.Response('{}', 200);
  });

  Future<void> pumpForm(WidgetTester tester, _Voice voice,
      {String patientId = '1'}) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [voice],
      home: Scaffold(
        body: SingleChildScrollView(
          child: AllergyInputForm(patientId: patientId, onAllergyAdded: (_) {}),
        ),
      ),
    ));
    await tester.pump();
  }

  Future<void> run(WidgetTester tester, Future<void> Function() body) =>
      http.runWithClient(body, () => MockClient((r) async {
            requests.add(r);
            return handler(r);
          }));

  Future<void> useVoice(WidgetTester tester) async {
    await tester.tap(find.text('Use AI Voice'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  for (final c in <(String, String)>[
    ('MODERATE', 'Moderate (Noticeable symptoms)'),
    ('SEVERE', 'Severe (Life-threatening)'),
    ('MILD', 'Mild (Minor symptoms)'),
  ]) {
    testWidgets('an AI result with ${c.$1} severity fills the form',
        (tester) async {
      await run(tester, () async {
        handler = (_) => http.Response(
            jsonEncode({
              'data': {
                'medication': 'Amoxicillin',
                'reaction': 'Rash',
                'severity': c.$1,
              },
            }),
            200);
        await pumpForm(tester, _Voice('rash after amoxicillin'));
        await useVoice(tester);
        expect(find.text('Amoxicillin'), findsOneWidget);
        expect(find.text('Rash'), findsOneWidget);
        expect(find.text(c.$2), findsOneWidget);
      });
    });
  }

  for (final phrase in [
    'I am allergic to penicillin, it gives hives',
    'I have an allergy to sulfa; bad',
    'the drug codeine allergy makes me itch',
    'nothing useful here',
  ]) {
    testWidgets('an empty AI allergen is read from "$phrase"', (tester) async {
      await run(tester, () async {
        handler = (_) => http.Response(jsonEncode({'severity': ''}), 200);
        await pumpForm(tester, _Voice(phrase));
        await useVoice(tester);
        expect(find.text(phrase), findsOneWidget);
      });
    });
  }

  testWidgets('an AI failure keeps the dictation', (tester) async {
    await run(tester, () async {
      handler = (_) => http.Response('down', 500);
      await pumpForm(tester, _Voice('itchy eyes'));
      await useVoice(tester);
      expect(find.textContaining('AI could not parse'), findsOneWidget);
      expect(find.text('itchy eyes'), findsOneWidget);
    });
  });

  testWidgets('a bad patient id stops the AI call', (tester) async {
    await run(tester, () async {
      await pumpForm(tester, _Voice('itchy eyes'), patientId: 'x');
      await useVoice(tester);
      expect(find.text('Invalid patient ID'), findsOneWidget);
    });
  });

  Future<void> fillAndSubmit(WidgetTester tester) async {
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Latex');
    await tester.enterText(fields.at(1), 'Hives');
    await tester.tap(find.byWidgetPredicate((w) => w is ElevatedButton));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('submitting a moderate allergy saves it', (tester) async {
    await run(tester, () async {
      handler = (_) => http.Response(jsonEncode({'data': {'id': 1}}), 201);
      await pumpForm(tester, _Voice(''));
      await tester.tap(find.text('Mild (Minor symptoms)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Moderate (Noticeable symptoms)').last);
      await tester.pumpAndSettle();
      await fillAndSubmit(tester);
      expect(find.text('✅ Drug allergy added successfully'), findsOneWidget);
      final body = jsonDecode(requests.last.body) as Map<String, dynamic>;
      expect(body['severity'], 'MODERATE');
    });
  });

  testWidgets('submitting a severe allergy that fails says so',
      (tester) async {
    await run(tester, () async {
      handler = (_) => http.Response('nope', 500);
      await pumpForm(tester, _Voice(''));
      await tester.tap(find.text('Mild (Minor symptoms)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Severe (Life-threatening)').last);
      await tester.pumpAndSettle();
      await fillAndSubmit(tester);
      expect(find.textContaining('Failed to add allergy'), findsOneWidget);
    });
  });

  testWidgets('submitting with a bad patient id says so', (tester) async {
    await run(tester, () async {
      await pumpForm(tester, _Voice(''), patientId: 'x');
      await fillAndSubmit(tester);
      expect(find.text('Invalid patient ID'), findsOneWidget);
    });
  });
}
