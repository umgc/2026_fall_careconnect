// Page-title tests for CallIntegrationHelper
// (lib/utils/call_integration_helper.dart): both call directions open the
// call screen in a page titled "Video Call" (WCAG 2.4.2). The signed-in user
// isn't a caregiver, so the premium check is skipped; the probe reads the
// pushed title without building the call screen.
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/utils/call_integration_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../helpers/titled_route_probe.dart';
import '../mock_user_provider.dart';

void main() {
  late TitledRouteProbe probe;

  const patient = {
    'patient': {
      'id': 12,
      'firstName': 'Romilda',
      'lastName': 'Smith',
      'email': 'romilda@example.test',
    },
    'link': {'patientUserId': 34},
  };
  const caregiver = {
    'id': 9,
    'name': 'Casey Caregiver',
    'email': 'casey@example.test',
  };

  Future<void> pumpCaller(
      WidgetTester tester, Future<void> Function(BuildContext) call) async {
    probe = TitledRouteProbe();
    await tester.pumpWidget(ChangeNotifierProvider<UserProvider>.value(
      value: MockUserProvider(mockUser: MockUser(id: 1, role: 'ADMIN')),
      child: MaterialApp(
        navigatorObservers: [probe],
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
                onPressed: () => call(context), child: const Text('Call')),
          ),
        ),
      ),
    ));
  }

  testWidgets('a call to a patient opens a page titled "Video Call"',
      (tester) async {
    await pumpCaller(
        tester,
        (context) => CallIntegrationHelper.startVideoCallToPatient(
            context: context, currentUser: caregiver, targetPatient: patient));
    expect(
        await probe.tapAndReadTitle(tester, find.text('Call')), 'Video Call');
  });

  testWidgets('a call to a caregiver opens a page titled "Video Call"',
      (tester) async {
    await pumpCaller(
        tester,
        (context) => CallIntegrationHelper.startVideoCallToCaregiver(
            context: context,
            currentUser: patient,
            targetCaregiver: caregiver));
    expect(
        await probe.tapAndReadTitle(tester, find.text('Call')), 'Video Call');
  });
}
