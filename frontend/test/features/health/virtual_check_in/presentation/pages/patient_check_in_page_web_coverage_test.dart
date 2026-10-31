// Additional coverage for the web PatientVirtualCheckIn page: exercises the
// questionnaire loading branches with a mocked HTTP client.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/features/health/virtual_check_in/presentation/pages/patient_check_in_detail_page.dart';
import 'package:care_connect_app/features/health/virtual_check_in/presentation/pages/patient_check_in_page_web.dart';
import 'package:care_connect_app/providers/user_provider.dart';

const _secureStorageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

Widget _wrap(UserProvider provider) {
  return ChangeNotifierProvider<UserProvider>.value(
    value: provider,
    child: const MaterialApp(home: PatientVirtualCheckIn()),
  );
}

UserProvider _providerWith({int? patientId}) {
  final provider = UserProvider();
  provider.setUser(UserSession(
    id: 7,
    email: 'p@test.com',
    role: 'PATIENT',
    token: 'tok',
    name: 'Pat',
    patientId: patientId,
  ));
  return provider;
}

Map<String, dynamic> _summary(int id, {String? submittedAt}) => {
      'checkInId': id,
      'patientId': 7,
      'createdAt': '2025-01-01T00:00:00',
      'submittedAt': submittedAt,
      'questionCount': 1,
    };

/// Pumps the page with all HTTP traffic routed through [handler].
Future<List<String>> _pumpWith(
  WidgetTester tester,
  UserProvider provider,
  Future<http.Response> Function(http.Request) handler,
) async {
  final paths = <String>[];
  final client = MockClient((req) async {
    paths.add(req.url.path);
    return handler(req);
  });
  await http.runWithClient(() async {
    await tester.pumpWidget(_wrap(provider));
    await tester.pumpAndSettle();
  }, () => client);
  return paths;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, (call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, null);
  });

  testWidgets('shows session error when no user is signed in', (tester) async {
    await tester.pumpWidget(ChangeNotifierProvider<UserProvider>.value(
      value: UserProvider(),
      child: const MaterialApp(home: PatientVirtualCheckIn()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('No user session found. Please sign in again.'),
        findsOneWidget);
  });

  testWidgets('shows not-assigned message when no check-ins exist',
      (tester) async {
    final paths = await _pumpWith(
      tester,
      _providerWith(patientId: 99),
      (req) async => http.Response('[]', 200),
    );
    // Both candidate ids (patientId and user id) are queried.
    expect(paths.where((p) => p.contains('/patients/')).length, 2);
    expect(find.text('No check-in questionnaire has been assigned yet.'),
        findsOneWidget);
  });

  testWidgets('shows all-completed message when every check-in submitted',
      (tester) async {
    await _pumpWith(
      tester,
      _providerWith(),
      (req) async => http.Response(
        jsonEncode([_summary(1, submittedAt: '2025-01-02T00:00:00')]),
        200,
      ),
    );
    expect(find.textContaining('All assigned check-ins have already'),
        findsOneWidget);
  });

  testWidgets('shows no-questions message and check-in id', (tester) async {
    await _pumpWith(tester, _providerWith(), (req) async {
      if (req.url.path.endsWith('/questions')) {
        return http.Response('[]', 200);
      }
      return http.Response(jsonEncode([_summary(31)]), 200);
    });
    expect(find.text('Check-in #31'), findsOneWidget);
    expect(find.text('This check-in has no questions configured.'),
        findsOneWidget);
  });

  testWidgets('shows load failure when questions endpoint errors',
      (tester) async {
    await _pumpWith(tester, _providerWith(), (req) async {
      if (req.url.path.endsWith('/questions')) {
        return http.Response('nope', 500);
      }
      return http.Response(jsonEncode([_summary(5)]), 200);
    });
    expect(find.textContaining('Failed to load questionnaire'), findsOneWidget);
  });

  testWidgets('renders detail page when questions are assigned',
      (tester) async {
    await _pumpWith(tester, _providerWith(), (req) async {
      if (req.url.path.endsWith('/questions')) {
        return http.Response(
          jsonEncode([
            {
              'id': 1,
              'prompt': 'How do you feel?',
              'type': 'TEXT',
              'required': true,
              'ordinal': 1,
            },
          ]),
          200,
        );
      }
      return http.Response(jsonEncode([_summary(12)]), 200);
    });
    expect(find.byType(PatientCheckInDetailPage), findsOneWidget);
  });
}
