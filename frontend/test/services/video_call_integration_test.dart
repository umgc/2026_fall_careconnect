// Tests for VideoCallIntegration (lib/services/video_call_integration.dart).
//
// Both entry points open the call screen in a page titled "Video Call"
// (WCAG 2.4.2). The signed-in user here is not a caregiver, so the premium
// subscription check is skipped; the probe reads the pushed title without
// building the call screen.
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/video_call_integration.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../helpers/titled_route_probe.dart';
import '../mock_user_provider.dart';

void main() {
  late TitledRouteProbe probe;

  const patient = {
    'id': 12,
    'firstName': 'Romilda',
    'lastName': 'Smith',
    'email': 'romilda@example.test',
    'phone': '555-0100',
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

  testWidgets('a video call opens a page titled "Video Call"', (tester) async {
    await pumpCaller(
        tester,
        (context) => VideoCallIntegration.startCallToPatient(
              context: context,
              caregiverId: '42',
              caregiverName: 'Casey',
              caregiverEmail: 'casey@example.test',
              patientData: patient,
            ));
    expect(
        await probe.tapAndReadTitle(tester, find.text('Call')), 'Video Call');
  });

  testWidgets('a voice call also opens a page titled "Video Call"',
      (tester) async {
    await pumpCaller(
        tester,
        (context) => VideoCallIntegration.startVoiceCallToPatient(
              context: context,
              caregiverId: '42',
              caregiverName: 'Casey',
              caregiverEmail: 'casey@example.test',
              patientData: patient,
            ));
    expect(
        await probe.tapAndReadTitle(tester, find.text('Call')), 'Video Call');
  });
}
