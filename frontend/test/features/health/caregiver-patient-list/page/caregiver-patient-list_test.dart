// Tests for CaregiverPatientList
// (lib/features/health/caregiver-patient-list/page/caregiver-patient-list.dart).
//
// Covers the accessibility changes: the "Patient List" heading, the Register
// button's text color, and the titled pages for a patient's conversation and
// details (WCAG 2.4.2). The backend is faked through ApiService's test client.
import 'dart:convert';

import 'package:care_connect_app/config/theme/app_theme.dart';
import 'package:care_connect_app/features/health/caregiver-patient-list/page/caregiver-patient-list.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../helpers/titled_route_probe.dart';
import '../../../../mock_user_provider.dart';

void main() {
  late TitledRouteProbe probe;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => call.method == 'check' ? ['wifi'] : null,
    );
    ApiService.debugSetHttpClient(MockClient((request) async {
      if (request.url.path.contains('/caregivers/42/patients')) {
        return http.Response(
            jsonEncode([
              {
                'patient': {
                  'id': 12,
                  'firstName': 'Romilda',
                  'lastName': 'Smith',
                },
                'link': {'patientUserId': 34, 'notes': 'Doing well'},
              }
            ]),
            200);
      }
      return http.Response(jsonEncode([]), 200);
    }));
  });

  tearDown(ApiService.debugResetHttpClient);

  Future<void> pumpList(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    probe = TitledRouteProbe();
    await tester.pumpWidget(ChangeNotifierProvider<UserProvider>.value(
      value: MockUserProvider(
          mockUser: MockUser(id: 10, role: 'CAREGIVER', caregiverId: 42)),
      child: MaterialApp(
        navigatorObservers: [probe],
        home: const CaregiverPatientList(),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('has a level-1 "Patient List" heading', (tester) async {
    await pumpList(tester);
    final heading = tester.widget<Semantics>(find
        .ancestor(
            of: find.text('Patient List'), matching: find.byType(Semantics))
        .first);
    expect(heading.properties.headingLevel, 1);
  });

  testWidgets('Register uses the primary text color (contrast fix)',
      (tester) async {
    await pumpList(tester);
    // ElevatedButton.icon builds a subclass, so match by `is`, not exact type.
    final button = tester.widget<ButtonStyleButton>(find
        .ancestor(
            of: find.text('Register'),
            matching: find.byWidgetPredicate((w) => w is ButtonStyleButton))
        .first);
    expect(button.style?.foregroundColor?.resolve({}), AppTheme.textPrimary);
  });

  testWidgets('lists the linked patient', (tester) async {
    await pumpList(tester);
    expect(find.textContaining('Romilda'), findsWidgets);
  });

  testWidgets('"View Details" pushes a page titled "Patient Details"',
      (tester) async {
    await pumpList(tester);
    expect(await probe.tapAndReadTitle(tester, find.text('View Details')),
        'Patient Details');
  });

  testWidgets('the message icon pushes a page titled "Conversation"',
      (tester) async {
    await pumpList(tester);
    expect(
        await probe.tapAndReadTitle(
            tester, find.byIcon(Icons.message_outlined).first),
        'Conversation');
  });
}
