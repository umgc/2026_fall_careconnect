// More happy-path tests for SymptomInputForm
// (lib/features/health/symptom-tracker/widgets/symptom_input_form.dart): the
// AI voice result for each severity, the AI failure, and saving with an AI
// key/value, a changed severity and a bad patient id.
import 'dart:async';
import 'dart:convert';

import 'package:care_connect_app/features/health/symptom-tracker/widgets/symptom_input_form.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Closes the voice assistant page as soon as it is pushed, returning
/// [transcript] to the form.
class _Voice extends NavigatorObserver {
  _Voice(this.transcript);
  final String transcript;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute == null || route is! PageRoute) return;
    scheduleMicrotask(() => route.navigator?.removeRoute(route, transcript));
  }
}

void main() {
  late http.Response Function(http.Request) handler;
  final requests = <http.Request>[];
  late MockClient client;

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
    client = MockClient((r) async {
      requests.add(r);
      return handler(r);
    });
    ApiService.debugSetHttpClient(client);
  });

  tearDown(ApiService.debugResetHttpClient);

  Future<void> pumpForm(WidgetTester tester, _Voice voice,
      {String patientId = '1'}) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [voice],
      home: Scaffold(
        body: SingleChildScrollView(
          child: SymptomInputForm(patientId: patientId, onSymptomAdded: (_) {}),
        ),
      ),
    ));
    await tester.pump();
  }

  Future<void> run(WidgetTester tester, Future<void> Function() body) =>
      http.runWithClient(body, () => client);

  Future<void> frames(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> useVoice(WidgetTester tester) async {
    await tester.tap(find.text('Use AI Voice'));
    await frames(tester);
  }

  for (final sev in ['SEVERE', 'MODERATE', 'MILD', 'OTHER']) {
    testWidgets('an AI result with $sev severity fills the form',
        (tester) async {
      await run(tester, () async {
        handler = (r) => r.url.path.endsWith('/ai/analyze/symptom')
            ? http.Response(
                jsonEncode({
                  'data': {
                    'symptomKey': 'Anxiety',
                    'symptomValue': sev == 'OTHER' ? '' : 'high',
                    'severity': sev,
                    'notes': 'from ai',
                  },
                }),
                200)
            : http.Response(jsonEncode({'id': 5}), 201);
        await pumpForm(tester, _Voice('feeling anxious'));
        await useVoice(tester);
        expect(find.text('AI analyzed symptom ✅'), findsOneWidget);
        expect(find.text('from ai'), findsOneWidget);

        // Save with the AI key and value.
        await tester.tap(find.text('Record Symptom').last);
        await frames(tester);
        final saved = requests.last;
        expect(jsonDecode(saved.body)['symptomKey'], 'Anxiety');
      });
    });
  }

  testWidgets('an AI result without a key falls back to the transcript',
      (tester) async {
    await run(tester, () async {
      handler = (_) => http.Response(jsonEncode({'other': true}), 200);
      await pumpForm(tester, _Voice('tired'));
      await useVoice(tester);
      expect(find.text('tired'), findsWidgets);
    });
  });

  testWidgets('an AI failure keeps the transcript as notes', (tester) async {
    await run(tester, () async {
      handler = (_) => http.Response('down', 500);
      await pumpForm(tester, _Voice('panic'));
      await tester.enterText(find.byType(TextField).last, 'earlier note');
      await useVoice(tester);
      expect(find.textContaining('AI analysis failed'), findsOneWidget);
      expect(find.text('earlier note\npanic'), findsOneWidget);
    });
  });

  testWidgets('a bad patient id stops the AI call and the save',
      (tester) async {
    await run(tester, () async {
      await pumpForm(tester, _Voice('panic'), patientId: 'x');
      await useVoice(tester);
      expect(find.text('Invalid patient ID'), findsOneWidget);
      ScaffoldMessenger.of(tester.element(find.byType(SymptomInputForm)))
          .clearSnackBars();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Record Symptom').last);
      await frames(tester);
      expect(find.text('Invalid patient ID'), findsOneWidget);
    });
  });

  testWidgets('a changed severity is saved, and a failed save says so',
      (tester) async {
    await run(tester, () async {
      handler = (_) => http.Response('no', 500);
      await pumpForm(tester, _Voice(''));
      await tester.enterText(find.byType(TextField).first, 'Insomnia');
      await tester.tap(find.text('Mild'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Severe').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Record Symptom').last);
      await frames(tester);
      expect(find.textContaining('Failed to save'), findsOneWidget);
      expect(jsonDecode(requests.last.body)['severity'], 5);
    });
  });
}
