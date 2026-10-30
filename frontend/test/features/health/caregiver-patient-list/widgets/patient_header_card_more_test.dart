// More happy-path tests for PatientHeaderCard
// (lib/features/health/caregiver-patient-list/widgets/patient_header_card.dart):
// the full vitals bar, the default Start Video Call screen, and the
// Emergency Contacts dialing flow with zero, one and two numbers.
import 'package:care_connect_app/features/health/caregiver-patient-list/widgets/patient_header_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

PatientHeaderCard _card({List<String> phones = const [], bool vitals = true}) =>
    PatientHeaderCard(
      fullName: 'Pat Example',
      mrn: 'MRN-1',
      age: 70,
      sex: 'Female',
      currentMoodLabel: 'Good',
      currentMoodEmoji: ':)',
      diagnoses: const ['Diabetes'],
      allergies: const ['Latex'],
      heartRateBpm: vitals ? 72 : null,
      bpSystolic: vitals ? 120 : null,
      bpDiastolic: vitals ? 80 : null,
      oxygenPercent: vitals ? 98 : null,
      temperatureF: vitals ? 98.6 : null,
      emergencyPhones: phones,
    );

void main() {
  final dialed = <String>[];

  setUp(() {
    dialed.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/url_launcher'),
      (call) async {
        if (call.method == 'launch') {
          dialed.add((call.arguments as Map)['url'] as String);
          return false;
        }
        return false;
      },
    );
  });

  Future<void> pumpCard(WidgetTester tester, PatientHeaderCard card,
      {double width = 1400}) async {
    tester.view.physicalSize = Size(width, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: card)),
    ));
  }

  for (final width in [1400.0, 500.0]) {
    testWidgets('shows every vital and opens the video call stub ($width)',
        (tester) async {
      await pumpCard(tester, _card(), width: width);
      expect(find.text('72 bpm'), findsOneWidget);
      expect(find.text('120/80 mmHg'), findsOneWidget);
      expect(find.text('98 %'), findsOneWidget);
      expect(find.text('98.6 °F'), findsOneWidget);
      await tester.tap(find.text('Start Video Call').first);
      await tester.pumpAndSettle();
      expect(find.text('Video call in progress…'), findsOneWidget);
    });
  }

  testWidgets('no emergency numbers says so', (tester) async {
    await pumpCard(tester, _card(vitals: false));
    await tester.tap(find.text('Emergency Contacts').first);
    await tester.pump();
    expect(find.text('No emergency contacts configured'), findsOneWidget);
  });

  testWidgets('two numbers are dialed in turn with merge guidance',
      (tester) async {
    await pumpCard(tester, _card(phones: ['111', '222']));
    await tester.tap(find.text('Emergency Contacts').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(dialed, ['tel:111', 'tel:222']);
  });
}
