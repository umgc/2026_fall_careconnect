// Coverage tests for PatientRegistrationPage
// (lib/features/onboarding/presentation/pages/patient_registration.dart):
// the full three-step registration submitted to a mocked API (success,
// server error, missing caregiver id), the themed stepper buttons and the
// AppBar back arrow.

import 'dart:convert';

import 'package:care_connect_app/config/theme/app_theme.dart';
import 'package:care_connect_app/features/onboarding/presentation/pages/patient_registration.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _secureStorage =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
const _connectivity = MethodChannel('dev.fluttercommunity.plus/connectivity');
const _connectivityStatus =
    MethodChannel('dev.fluttercommunity.plus/connectivity_status');

Widget _app({int? caregiverId, UserSession? user}) {
  final provider = UserProvider();
  if (user != null) provider.setUser(user);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => PatientRegistrationPage(caregiverId: caregiverId),
      ),
      GoRoute(
          path: '/login',
          builder: (_, __) => const Scaffold(body: Text('LOGIN PAGE'))),
      GoRoute(
          path: '/dashboard',
          builder: (_, __) => const Scaffold(body: Text('DASHBOARD PAGE'))),
    ],
  );
  return ChangeNotifierProvider<UserProvider>.value(
    value: provider,
    child: MaterialApp.router(theme: AppTheme.lightTheme, routerConfig: router),
  );
}

Future<void> _pressButton(WidgetTester tester, String label) async {
  final ElevatedButton button =
      tester.widget(find.widgetWithText(ElevatedButton, label).last);
  button.onPressed!();
  await tester.pumpAndSettle();
}

Future<void> _fillStep0(WidgetTester tester) async {
  final fields = find.byType(TextFormField);
  await tester.enterText(fields.at(0), 'John');
  await tester.enterText(fields.at(1), 'Doe');
  await tester.enterText(fields.at(2), 'john@example.com');
  await tester.enterText(fields.at(3), '1234567890');
  await tester.pumpAndSettle();
  await tester.ensureVisible(fields.at(4));
  await tester.pumpAndSettle();
  await tester.tap(fields.at(4));
  await tester.pumpAndSettle();
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(fields.at(5));
  await tester.pumpAndSettle();
  await tester.enterText(fields.at(5), 'ma123456789');
  await tester.pumpAndSettle();
  final gender = find.byType(DropdownButtonFormField<String>);
  await tester.ensureVisible(gender);
  await tester.pumpAndSettle();
  await tester.tap(gender);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Female').last);
  await tester.pumpAndSettle();
  await _pressButton(tester, 'Next');
}

Future<void> _fillStep1(WidgetTester tester) async {
  final fields = find.byType(TextFormField);
  await tester.enterText(fields.at(6), '123 Main St');
  await tester.enterText(fields.at(7), 'Apt 4');
  await tester.enterText(fields.at(8), 'Springfield');
  await tester.enterText(fields.at(9), 'VA');
  await tester.enterText(fields.at(10), '22150');
  await tester.enterText(fields.at(11), '5551234567');
  await tester.pumpAndSettle();
  await _pressButton(tester, 'Next');
}

Future<void> _completeForm(WidgetTester tester) async {
  await _fillStep0(tester);
  await _fillStep1(tester);
  await tester.enterText(find.byType(TextFormField).at(12), 'Daughter');
  await tester.pumpAndSettle();
}

/// navigateToDashboard goes to /login or /dashboard depending on whether a
/// session was persisted by an earlier test; either way the form is gone.
void _expectLeftForm() {
  expect(find.byType(PatientRegistrationPage), findsNothing);
  expect(
    find.byWidgetPredicate((w) =>
        w is Text && (w.data == 'LOGIN PAGE' || w.data == 'DASHBOARD PAGE')),
    findsOneWidget,
  );
}

void main() {
  late List<http.Request> requests;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    requests = <http.Request>[];
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(_secureStorage, (call) async {
      if (call.method == 'readAll') return <String, String>{};
      return null;
    });
    m.setMockMethodCallHandler(
        _connectivity, (call) async => call.method == 'check' ? ['wifi'] : null);
    m.setMockMethodCallHandler(_connectivityStatus, (call) async => null);
  });

  tearDown(() {
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final c in [_secureStorage, _connectivity, _connectivityStatus]) {
      m.setMockMethodCallHandler(c, null);
    }
    ApiService.debugResetHttpClient();
  });

  void mockApi(int status, String body) {
    ApiService.debugSetHttpClient(MockClient((r) async {
      requests.add(r);
      return http.Response(body, status);
    }));
  }

  testWidgets('successful registration posts the patient and leaves the page',
      (tester) async {
    mockApi(201, '{"id": 99}');
    await tester.pumpWidget(_app(caregiverId: 12));
    await tester.pumpAndSettle();

    await _completeForm(tester);
    await _pressButton(tester, 'Register Patient');

    expect(requests, hasLength(1));
    expect(requests.single.url.path, endsWith('caregivers/12/patients'));
    final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
    expect(body['firstName'], 'John');
    expect(body['maNumber'], 'MA123456789');
    expect(body['gender'], 'FEMALE');
    expect(body['relationship'], 'Daughter');
    expect(body['caregiverId'], 12);
    expect((body['address'] as Map)['line2'], 'Apt 4');
    _expectLeftForm();
  });

  testWidgets('server error message is shown in a snackbar', (tester) async {
    mockApi(400, jsonEncode({'message': 'Email already registered'}));
    await tester.pumpWidget(_app(
      user: UserSession(
        id: 3,
        email: 'cg@example.com',
        role: 'CAREGIVER',
        token: 't',
        caregiverId: 44,
      ),
    ));
    await tester.pumpAndSettle();

    await _completeForm(tester);
    await _pressButton(tester, 'Register Patient');

    expect(requests.single.url.path, endsWith('caregivers/44/patients'));
    expect(find.textContaining('Registration failed'), findsOneWidget);
    expect(find.textContaining('Email already registered'), findsOneWidget);
    expect(find.text('Register Patient'), findsOneWidget);
  });

  testWidgets('falls back to the error key when no message is returned',
      (tester) async {
    mockApi(500, jsonEncode({'error': 'Boom'}));
    await tester.pumpWidget(_app(caregiverId: 5));
    await tester.pumpAndSettle();

    await _completeForm(tester);
    await _pressButton(tester, 'Register Patient');

    expect(find.textContaining('Boom'), findsOneWidget);
  });

  testWidgets('missing caregiver id fails without calling the API',
      (tester) async {
    mockApi(201, '{}');
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await _completeForm(tester);
    await _pressButton(tester, 'Register Patient');

    expect(requests, isEmpty);
    expect(find.textContaining('Caregiver ID is required'), findsOneWidget);
  });

  testWidgets('AppBar back arrow routes away from the form', (tester) async {
    await tester.pumpWidget(_app(caregiverId: 1));
    await tester.pumpAndSettle();

    final back = find.widgetWithIcon(IconButton, Icons.arrow_back);
    expect(back, findsOneWidget);
    tester.widget<IconButton>(back).onPressed!();
    await tester.pumpAndSettle();

    _expectLeftForm();
  });
}
