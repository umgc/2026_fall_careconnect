// Page-title test for PatientHeaderCard
// (lib/features/health/caregiver-patient-list/widgets/patient_header_card.dart):
// with no onStartVideoCall callback, Start Video Call opens a page titled
// "Video Call" (WCAG 2.4.2).
import 'package:care_connect_app/features/health/caregiver-patient-list/widgets/patient_header_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/titled_route_probe.dart';

void main() {
  testWidgets('Start Video Call opens a page titled "Video Call"',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final probe = TitledRouteProbe();
    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [probe],
      home: const Scaffold(
        body: SingleChildScrollView(
          child: PatientHeaderCard(
            fullName: 'Alice Johnson',
            mrn: 'MRN-001',
            age: 45,
            sex: 'Female',
            currentMoodLabel: 'Good',
            currentMoodEmoji: '😊',
            diagnoses: [],
            allergies: [],
          ),
        ),
      ),
    ));

    expect(await probe.tapAndReadTitle(tester, find.text('Start Video Call')),
        'Video Call');
  });
}
