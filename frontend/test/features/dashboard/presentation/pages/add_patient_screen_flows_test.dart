// Interaction tests for AddPatientScreen
// (lib/features/dashboard/presentation/pages/add_patient_screen.dart):
// email lookup outcomes and the connection request submission.

import 'dart:convert';

import 'package:care_connect_app/features/dashboard/presentation/pages/add_patient_screen.dart';
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

import '../../../../mock_user_provider.dart';

late http.Response Function(http.Request) _handler;

Future<void> _pump(WidgetTester tester, {int? caregiverId = 5}) async {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, __) => const AddPatientScreen()),
      GoRoute(
        path: '/register/patient',
        builder: (_, __) => const Text('Register Patient Route'),
      ),
    ],
    errorBuilder: (_, state) => Text('Other route ${state.uri.path}'),
  );
  await tester.pumpWidget(
    ChangeNotifierProvider<UserProvider>.value(
      value: MockUserProvider(
        mockUser:
            MockUser(id: 1, role: 'CAREGIVER', caregiverId: caregiverId),
      ),
      child: MaterialApp.router(
        theme: ThemeData(splashFactory: InkRipple.splashFactory),
        routerConfig: router,
      ),
    ),
  );
  await tester.pump();
}

Future<void> _lookup(WidgetTester tester, String email) async {
  await tester.enterText(find.byType(TextFormField).first, email);
  await tester.tap(find.byIcon(Icons.search));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _sendRequest(WidgetTester tester) async {
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Relationship to Patient'),
    'Daughter',
  );
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Message (Optional)'),
    'Hello',
  );
  final send = find.byType(ElevatedButton).last;
  await tester.ensureVisible(send);
  await tester.tap(send);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  setUpAll(() => ApiService.debugSetHttpClient(
        MockClient((r) async => _handler(r)),
      ));

  setUp(() {
    _handler = (r) => r.url.path.endsWith('/check-email')
        ? http.Response(
            jsonEncode({'exists': true, 'role': 'PATIENT', 'userId': 9}),
            200,
          )
        : http.Response(jsonEncode({'requestId': 1, 'message': 'ok'}), 200);
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => call.method == 'readAll' ? <String, String>{} : null,
    );
  });

  testWidgets('empty email lookup asks for an address', (tester) async {
    await _pump(tester);
    await tester.tap(find.byIcon(Icons.search));
    await tester.pump();
    expect(find.text('Please enter an email address'), findsOneWidget);
  });

  testWidgets('found patient shows request form and sends request',
      (tester) async {
    await _pump(tester);
    await _lookup(tester, 'pat@example.test');
    expect(find.text('Patient found! You can send a connection request.'),
        findsOneWidget);
    expect(find.text('Step 2: Send connection request'), findsOneWidget);
    await _sendRequest(tester);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(AddPatientScreen), findsNothing);
  });

  testWidgets('request rejected by server shows its error', (tester) async {
    _handler = (r) => r.url.path.endsWith('/check-email')
        ? http.Response(jsonEncode({'exists': true, 'role': 'PATIENT'}), 200)
        : http.Response(jsonEncode({'error': 'Already linked'}), 200);
    await _pump(tester);
    await _lookup(tester, 'pat@example.test');
    await _sendRequest(tester);
    expect(find.text('Already linked'), findsOneWidget);
  });

  testWidgets('request server failure shows status code', (tester) async {
    _handler = (r) => r.url.path.endsWith('/check-email')
        ? http.Response(jsonEncode({'exists': true, 'role': 'PATIENT'}), 200)
        : http.Response('x', 500);
    await _pump(tester);
    await _lookup(tester, 'pat@example.test');
    await _sendRequest(tester);
    expect(find.text('Server error: 500'), findsOneWidget);
  });

  testWidgets('request without caregiver id is blocked', (tester) async {
    await _pump(tester, caregiverId: null);
    await _lookup(tester, 'pat@example.test');
    await _sendRequest(tester);
    expect(find.text('User or caregiver ID not available'), findsOneWidget);
  });

  testWidgets('email belonging to a caregiver is rejected', (tester) async {
    _handler = (r) => http.Response(
          jsonEncode({'exists': true, 'role': 'CAREGIVER', 'userId': 3}),
          200,
        );
    await _pump(tester);
    await _lookup(tester, 'cg@example.test');
    expect(find.text('This email belongs to a caregiver, not a patient'),
        findsOneWidget);
  });

  testWidgets('unknown email offers patient registration', (tester) async {
    _handler = (r) => http.Response(jsonEncode({'exists': false}), 200);
    await _pump(tester);
    await _lookup(tester, 'new@example.test');
    final register = find.text('Register New Patient').last;
    await tester.ensureVisible(register);
    await tester.tap(register);
    await tester.pumpAndSettle();
    expect(find.text('Register Patient Route'), findsOneWidget);
  });
}
