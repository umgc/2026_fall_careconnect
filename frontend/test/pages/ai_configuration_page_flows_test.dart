// Flow tests for AIConfigurationPage (lib/pages/ai_configuration_page.dart)
// with a loaded config: every switch, slider, text field and dropdown, then
// save success and failure. AIConfigService uses package:http top-level
// calls (http.runWithClient).

import 'dart:convert';

import 'package:care_connect_app/pages/ai_configuration_page.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../mock_user_provider.dart';

final _config = {
  'id': 4,
  'patientId': 1,
  'aiProvider': 'OPENAI',
  'enabledFeatures': ['general_chat', 'medication_reminders'],
  'maxTokensPerSession': 800,
  'temperature': 0.5,
  'personalityStyle': 'FRIENDLY',
  'contextMemoryEnabled': true,
  'medicalContextEnabled': false,
  'language': 'es',
  'emergencyAlertsEnabled': true,
};

class _Backend {
  int saveStatus = 200;
  int loadStatus = 200;
  Map<String, dynamic>? saved;

  MockClient client() => MockClient((req) async {
        if (req.method == 'POST') {
          saved = jsonDecode(req.body) as Map<String, dynamic>;
          return http.Response(jsonEncode(_config), saveStatus);
        }
        return http.Response(jsonEncode(_config), loadStatus);
      });
}

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final router = GoRouter(initialLocation: '/ai-config', routes: [
    GoRoute(path: '/', builder: (_, __) => const Scaffold()),
    GoRoute(
      path: '/ai-config',
      builder: (_, __) => const AIConfigurationPage(),
    ),
  ]);
  await tester.pumpWidget(ChangeNotifierProvider<UserProvider>.value(
    value: MockUserProvider(mockUser: MockUser(id: 1)),
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
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

  testWidgets('loaded config can be edited and saved', (tester) async {
    final backend = _Backend();
    await http.runWithClient(() async {
      await _pump(tester);
      expect(find.text('OPENAI'), findsOneWidget);

      for (final s in find.byType(Switch).evaluate().toList()) {
        await tester.tap(find.byWidget(s.widget));
        await tester.pump();
      }
      for (final s in find.byType(Slider).evaluate().toList()) {
        await tester.drag(find.byWidget(s.widget), const Offset(40, 0));
        await tester.pump();
      }
      await tester.enterText(find.byType(TextField).first, '1500');
      await tester.pump();

      await tester.tap(find.text('OPENAI'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('DEEPSEEK').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Spanish'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('German').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('AI configuration saved successfully!'),
          findsOneWidget);
    }, backend.client);
    expect(backend.saved?['preferredAiProvider'], 'DEEPSEEK');
    expect(backend.saved?['maxTokens'], 1500);
  });

  testWidgets('save failure and missing config default', (tester) async {
    final backend = _Backend()
      ..loadStatus = 404
      ..saveStatus = 500;
    await http.runWithClient(() async {
      await _pump(tester);
      await tester.tap(find.text('Save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }, backend.client);
    expect(find.textContaining('Failed to save configuration'),
        findsOneWidget);
  });

  testWidgets('cancel returns to the previous route', (tester) async {
    final backend = _Backend()..loadStatus = 500;
    await http.runWithClient(() async {
      final router = GoRouter(initialLocation: '/', routes: [
        GoRoute(
          path: '/',
          builder: (c, __) => Scaffold(
            body: TextButton(
              onPressed: () => c.push('/ai-config'),
              child: const Text('open'),
            ),
          ),
        ),
        GoRoute(
          path: '/ai-config',
          builder: (_, __) => const AIConfigurationPage(),
        ),
      ]);
      await tester.pumpWidget(ChangeNotifierProvider<UserProvider>.value(
        value: MockUserProvider(mockUser: MockUser(id: 1)),
        child: MaterialApp.router(routerConfig: router),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    }, backend.client);
    expect(find.text('open'), findsOneWidget);
  });
}
