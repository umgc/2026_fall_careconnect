// Coverage-focused widget tests (group I): role-specific views, admin drawer
// navigation, AI configuration edits and activity icons.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/features/activities/presentation/pages/client_activities_screen.dart';
import 'package:care_connect_app/features/dashboard/presentation/pages/patient_medical_notes_page.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/pages/ai_configuration_page.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:care_connect_app/widgets/role_based_drawer.dart';

import '../mock_user_provider.dart';

const _secure = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

// 1x1 transparent PNG.
final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=');

class _Session {
  _Session(this.name, this.email, this.role);
  final String name;
  final String email;
  final String role;
}

class _AdminProvider extends MockUserProvider {
  _AdminProvider()
      : super(mockUser: MockUser(name: 'Admin', email: 'a@t.com', role: 'ADMIN')) {
    userSession = _Session('Admin', 'a@t.com', 'ADMIN');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secure, (call) async {
      if (call.method == 'readAll') return <String, String>{};
      if (call.method == 'containsKey') return false;
      return null;
    });
  });

  group('PatientMedicalNotesPage', () {
    testWidgets('patient role shows the Patient View chip', (tester) async {
      final t = lookupAppLocalizations(const Locale('en'));
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ChangeNotifierProvider<UserProvider>.value(
          value: MockUserProvider(
              mockUser: MockUser(id: 1, role: 'PATIENT', patientId: 1)),
          child: const PatientMedicalNotesPage(
              patientId: 1, patientName: 'Jane Doe'),
        ),
      ));
      await tester.pump();
      expect(find.text(t.ptmednotes_ptView), findsOneWidget);
    });
  });

  group('RoleBasedDrawer admin', () {
    testWidgets('Product Analytics navigates to /admin/analytics',
        (tester) async {
      final router = GoRouter(routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => Scaffold(
            drawer: const RoleBasedDrawer(),
            body: Builder(
              builder: (ctx) => TextButton(
                onPressed: () => Scaffold.of(ctx).openDrawer(),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/admin/analytics',
          builder: (_, __) => const Scaffold(body: Text('Analytics Page')),
        ),
      ]);
      await tester.pumpWidget(ChangeNotifierProvider<UserProvider>.value(
        value: _AdminProvider(),
        child: MaterialApp.router(routerConfig: router),
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Administration'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Product Analytics'));
      await tester.pumpAndSettle();
      expect(find.text('Analytics Page'), findsOneWidget);
    });
  });

  group('AIConfigurationPage', () {
    testWidgets('personality dropdown change', (tester) async {
      tester.view.physicalSize = const Size(1200, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final router = GoRouter(initialLocation: '/ai-config', routes: [
        GoRoute(path: '/', builder: (_, __) => const Scaffold()),
        GoRoute(
            path: '/ai-config',
            builder: (_, __) => const AIConfigurationPage()),
      ]);
      await http.runWithClient(() async {
        await tester.pumpWidget(ChangeNotifierProvider<UserProvider>.value(
          value: MockUserProvider(mockUser: MockUser(id: 1)),
          child: MaterialApp.router(routerConfig: router),
        ));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('AI Configuration'), findsOneWidget);

        await tester.tap(find.text('FRIENDLY'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('DIRECT').last);
        await tester.pumpAndSettle();
        expect(find.text('DIRECT'), findsOneWidget);
      },
          () => MockClient((_) async => http.Response(
              jsonEncode({
                'id': 4,
                'patientId': 1,
                'aiProvider': 'OPENAI',
                'enabledFeatures': ['general_chat'],
                'maxTokensPerSession': 800,
                'temperature': 0.5,
                'personalityStyle': 'FRIENDLY',
                'contextMemoryEnabled': true,
                'medicalContextEnabled': false,
                'language': 'en',
                'emergencyAlertsEnabled': true,
              }),
              200)));
    });
  });

  group('ClientActivitiesScreen icons', () {
    testWidgets('activities with icon URLs load authenticated images',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final client = MockClient((req) async {
        if (req.url.path.endsWith('/activities')) {
          return http.Response(
              jsonEncode([
                {
                  'id': 1,
                  'name': 'Bathing',
                  'category': 'ADL',
                  'enabled': true,
                  'defaultIconUrl': '/icons/bath.png',
                },
                {
                  'id': 2,
                  'name': 'Meal prep',
                  'category': 'IADL',
                  'enabled': true,
                  'customIconUrl': '/icons/meal.png',
                },
              ]),
              200);
        }
        return http.Response.bytes(_png, 200);
      });
      ApiService.debugSetHttpClient(client);
      addTearDown(ApiService.debugResetHttpClient);
      await http.runWithClient(() async {
        await tester.pumpWidget(const MaterialApp(
          home: ClientActivitiesScreen(clientId: 5, clientName: 'Alex Rivera'),
        ));
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }, () => client);
      expect(find.text('Bathing'), findsOneWidget);
      expect(find.byType(Image), findsWidgets);
    });
  });
}
