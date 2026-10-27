// Accessibility tests for PatientDashboard: its icon-only buttons have names (WCAG 4.1.2).
// Setup copied from patient_dashboard_test.dart.
import 'dart:convert';

import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:care_connect_app/features/dashboard/patient_dashboard/pages/patient_dashboard.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';

import '../../../../mock_user_provider.dart';

late Future<http.Response> Function(http.Request) _httpHandler;

Future<http.Response> _defaultHandler(http.Request request) async {
  return http.Response('[]', 200);
}

Widget _wrap({MockUserProvider? provider}) {
  final p = provider ??
      MockUserProvider(
        mockUser: MockUser(
            id: 1, role: 'PATIENT', patientId: 1, name: 'Test Patient'),
      );
  return MaterialApp(
    locale: Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: ChangeNotifierProvider<UserProvider>.value(
      value: p,
      child: const PatientDashboard(),
    ),
  );
}

void _setLargeViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1600, 2400);
  tester.view.devicePixelRatio = 1.0;
}

List<Map<String, dynamic>> _sampleMoodHistory() {
  final now = DateTime.now().toUtc();
  return [
    {
      'score': 7,
      'label': 'Good',
      'createdAt': now.toIso8601String(),
    },
    {
      'score': 6,
      'label': 'Feeling well today',
      'createdAt': now.subtract(const Duration(days: 1)).toIso8601String(),
    },
    {
      'score': 5,
      'label': 'Slight headache',
      'createdAt': now.subtract(const Duration(days: 2)).toIso8601String(),
    },
    {
      'score': 8,
      'label': 'Medications taken',
      'createdAt': now.subtract(const Duration(days: 3)).toIso8601String(),
    },
  ];
}

List<Map<String, dynamic>> _sampleMedications() {
  return [
    {
      'id': 101,
      'medicationName': 'Blood Pressure Medication',
      'dosage': '10 mg',
      'frequency': 'Once daily',
      'isActive': true,
      'startDate': DateTime.now()
          .subtract(const Duration(days: 30))
          .toIso8601String()
          .split('T')
          .first,
      'lastTaken': null,
    },
  ];
}

/// Sets _httpHandler to respond like the patient dashboard's API.
void _setupMockClient({
  int evvStatusCode = 200,
  int medicationUpdateStatusCode = 200,
}) {
  _httpHandler = (request) async {
    final path = request.url.path;
    final method = request.method.toUpperCase();

    // Mood history: /v1/api/patient/{userId}/mood
    if (path.contains('/patient/') && path.endsWith('/mood')) {
      return http.Response(jsonEncode(_sampleMoodHistory()), 200);
    }

    // Medications list: /v3/api/patients/{id}/medications
    if (path.contains('/medications') &&
        !path.contains('/last-taken') &&
        method == 'GET') {
      return http.Response(jsonEncode(_sampleMedications()), 200);
    }

    // Mark taken / clear taken
    if (path.contains('/last-taken')) {
      return http.Response('{}', medicationUpdateStatusCode);
    }

    // Caregiver list / linked caregivers for patient
    if (path.contains('/caregivers') ||
        path.contains('caregiver-patient-links')) {
      return http.Response(
        jsonEncode([
          {
            'id': 10,
            'caregiverId': 10,
            'caregiverUserId': 10,
            'firstName': 'Jane',
            'lastName': 'Smith',
            'phone': '555-5678',
          },
        ]),
        200,
      );
    }

    // Scheduled visits
    if (path.contains('/scheduled-visits/')) {
      return http.Response(jsonEncode([]), 200);
    }

    // EVV search records
    if (path.contains('/evv/')) {
      return http.Response(
        jsonEncode({
          'content': [],
          'totalElements': 0,
          'totalPages': 0,
          'size': 200,
          'number': 0,
          'first': true,
          'last': true,
        }),
        evvStatusCode,
      );
    }

    // Provider endpoint — empty so dashboard uses built-in fallback provider
    if (path.contains('/provider')) {
      return http.Response('{}', 404);
    }

    // Family members / patient details
    if (RegExp(r'/patients/\d+$').hasMatch(path)) {
      return http.Response(jsonEncode([]), 200);
    }

    // Default
    return http.Response('{}', 200);
  };

  final client = MockClient((request) => _httpHandler(request));
  ApiService.debugSetHttpClient(client);
}

void _setupMethodChannels() {
  SharedPreferences.setMockInitialValues({});

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    (MethodCall methodCall) async {
      if (methodCall.method == 'readAll') {
        return <String, String>{'jwt_token': 'mock-jwt-for-test'};
      }
      if (methodCall.method == 'read') {
        final key = (methodCall.arguments as Map?)?['key'] as String?;
        if (key == 'jwt_token') return 'mock-jwt-for-test';
        return null;
      }
      if (methodCall.method == 'containsKey') {
        final key = (methodCall.arguments as Map?)?['key'] as String?;
        if (key == 'jwt_token') return true;
        return false;
      }
      if (methodCall.method == 'write' || methodCall.method == 'delete')
        return null;
      return null;
    },
  );

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('dev.fluttercommunity.plus/connectivity'),
    (MethodCall methodCall) async {
      if (methodCall.method == 'check') return ['wifi'];
      return null;
    },
  );
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
    (MethodCall methodCall) async => null,
  );
}

void _teardownMethodChannels() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    null,
  );
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('dev.fluttercommunity.plus/connectivity'),
    null,
  );
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
    null,
  );
}

/// Pump multiple frames to let async initState futures complete.
Future<void> _pumpUntilSettled(WidgetTester tester) async {
  for (int i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(() {
    _httpHandler = _defaultHandler;
  });

  setUp(() {
    _setupMockClient();
    _setupMethodChannels();
  });

  tearDown(() {
    _teardownMethodChannels();
    ApiService.debugResetHttpClient();
  });

  testWidgets('the AI chat button is named "AI Assistant"', (tester) async {
    _setLargeViewport(tester);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_wrap());
    await _pumpUntilSettled(tester);
    expect(find.byTooltip('AI Assistant'), findsOneWidget);
  });

  testWidgets('the EVV refresh button is named "Refresh"', (tester) async {
    _setLargeViewport(tester);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_wrap());
    await _pumpUntilSettled(tester);
    expect(find.byTooltip('Refresh', skipOffstage: false), findsWidgets);
  });
}
