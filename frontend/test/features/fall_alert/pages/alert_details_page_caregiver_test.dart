// AlertDetailsPage → PatientDetailsPage for each role (DEF-MCR-33, PR #364).
// Test ID TC-MCR-CG-043 is permanent. Never renumber, never reuse.

import 'package:care_connect_app/features/fall_alert/models/fall_alert.dart';
import 'package:care_connect_app/features/fall_alert/pages/alert_details_page.dart';
import 'package:care_connect_app/features/health/caregiver-patient-list/page/patient_details_page.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../../mock_user_provider.dart';

/// Records pushed routes and removes the newest before it builds, so the test
/// checks what View Details opens without running the patient page.
class _Pushes extends NavigatorObserver {
  final List<Route<dynamic>> routes = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      routes.add(route);
}

void main() {
  FallAlert alert() => FallAlert(
        id: 'a1',
        patientId: '42',
        patientName: 'Sarah Johnson',
        detectedAtUtc: DateTime.now().toUtc(),
        source: 'watch',
        hasLiveVideo: false,
      );

  Future<PatientDetailsPage> openedFor(WidgetTester t, String? role) async {
    final pushes = _Pushes();
    final app = MaterialApp(
      navigatorObservers: [pushes],
      home: AlertDetailsPage(alert: alert()),
    );
    await t.pumpWidget(role == null
        ? app
        : ChangeNotifierProvider<UserProvider>.value(
            value: MockUserProvider(mockUser: MockUser(role: role)),
            child: app,
          ));
    await t.pump();
    await t.tap(find.text('View Details'));
    final route = pushes.routes.last as MaterialPageRoute;
    route.navigator!.removeRoute(route);
    await t.pumpAndSettle();
    return route.builder(t.element(find.byType(AlertDetailsPage)))
        as PatientDetailsPage;
  }

  testWidgets(
      'TC-MCR-CG-043: a caregiver opening the patient from a fall alert gets the '
      'caregiver page (with its Medicare tab); a patient, a family member or no '
      'signed-in user gets the patient view', (t) async {
    final caregiver = await openedFor(t, 'CAREGIVER');
    expect(caregiver.patientId, '42');
    expect(caregiver.isCaregiver, isTrue);
    for (final role in ['PATIENT', 'FAMILY_LINK', null]) {
      await t.pumpWidget(const SizedBox());
      final page = await openedFor(t, role);
      expect(page.isCaregiver, isFalse, reason: '$role');
    }
  });
}
