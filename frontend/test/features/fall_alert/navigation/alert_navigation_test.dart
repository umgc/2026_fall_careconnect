// Tests for AlertNavigation
// (lib/features/fall_alert/navigation/alert_navigation.dart).
//
// AlertNavigation.navigateFromPayload reads the UserProvider role and pushes:
//   - PatientFallPromptPage ('/patient-fall-prompt') for patient users
//   - AlertDetailsPage       ('/alert-details')       for caregiver users
//
// Strategy: use a NavigatorObserver to capture which route was pushed.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:care_connect_app/features/fall_alert/navigation/alert_navigation.dart';
import 'package:care_connect_app/features/fall_alert/pages/alert_details_page.dart';
import 'package:care_connect_app/features/fall_alert/pages/alert_details_page_patient.dart';
import 'package:care_connect_app/providers/user_provider.dart';

import '../../../mock_user_provider.dart';

// Captures the most-recently-pushed route.
class _TestObserver extends NavigatorObserver {
  Route<dynamic>? lastPushed;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    lastPushed = route;
  }
}

Map<String, String> _samplePayload() => {
      'id': 'alert-1',
      'patientId': 'patient-42',
      'patientName': 'Alice Patient',
      'detectedAtUtc': DateTime.now().toIso8601String(),
      'source': 'watch',
      'hasLiveVideo': 'false',
      'liveVideoUrl': '',
      'patientPhone': '',
      'emergencyContactName': '',
      'emergencyContactPhone': '',
      'playbackData': '',
    };

Widget _buildApp({
  required MockUserProvider provider,
  required _TestObserver observer,
}) {
  return ChangeNotifierProvider<UserProvider>.value(
    value: provider,
    child: MaterialApp(
      navigatorObservers: [observer],
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () =>
                AlertNavigation.navigateFromPayload(context, _samplePayload()),
            child: const Text('Navigate'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('AlertNavigation.navigateFromPayload', () {
    testWidgets('pushes PatientFallPromptPage for patient role', (tester) async {
      final provider = MockUserProvider(
        mockUser: MockUser(role: 'PATIENT', patientId: 1),
      );
      final observer = _TestObserver();

      await tester.pumpWidget(_buildApp(provider: provider, observer: observer));
      await tester.tap(find.text('Navigate'));
      await tester.pump();

      expect(
        observer.lastPushed?.settings.name,
        PatientFallPromptPage.routeName,
      );
    });

    testWidgets('pushes AlertDetailsPage for caregiver role', (tester) async {
      final provider = MockUserProvider(
        mockUser: MockUser(role: 'CAREGIVER', caregiverId: 1, patientId: null),
      );
      final observer = _TestObserver();

      await tester.pumpWidget(_buildApp(provider: provider, observer: observer));
      await tester.tap(find.text('Navigate'));
      await tester.pump();

      expect(
        observer.lastPushed?.settings.name,
        AlertDetailsPage.routeName,
      );
    });

    testWidgets('renders trigger button without crashing', (tester) async {
      final provider = MockUserProvider(
        mockUser: MockUser(role: 'PATIENT', patientId: 1),
      );
      final observer = _TestObserver();

      await tester.pumpWidget(_buildApp(provider: provider, observer: observer));
      expect(find.text('Navigate'), findsOneWidget);
    });

    testWidgets('shows ElevatedButton widget', (tester) async {
      final provider = MockUserProvider(
        mockUser: MockUser(role: 'PATIENT', patientId: 1),
      );
      final observer = _TestObserver();

      await tester.pumpWidget(_buildApp(provider: provider, observer: observer));
      expect(find.byType(ElevatedButton), findsOneWidget);
    });

    testWidgets('shows Scaffold wrapping button', (tester) async {
      final provider = MockUserProvider(
        mockUser: MockUser(role: 'PATIENT', patientId: 1),
      );
      final observer = _TestObserver();

      await tester.pumpWidget(_buildApp(provider: provider, observer: observer));
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('pushes correct route for patient role with different patientId',
        (tester) async {
      final provider = MockUserProvider(
        mockUser: MockUser(role: 'PATIENT', patientId: 99),
      );
      final observer = _TestObserver();

      await tester.pumpWidget(_buildApp(provider: provider, observer: observer));
      await tester.tap(find.text('Navigate'));
      await tester.pump();

      expect(
        observer.lastPushed?.settings.name,
        PatientFallPromptPage.routeName,
      );
    });

    testWidgets('pushes correct route for caregiver role with different caregiverId',
        (tester) async {
      final provider = MockUserProvider(
        mockUser: MockUser(role: 'CAREGIVER', caregiverId: 99, patientId: null),
      );
      final observer = _TestObserver();

      await tester.pumpWidget(_buildApp(provider: provider, observer: observer));
      await tester.tap(find.text('Navigate'));
      await tester.pump();

      expect(
        observer.lastPushed?.settings.name,
        AlertDetailsPage.routeName,
      );
    });
  });
}
