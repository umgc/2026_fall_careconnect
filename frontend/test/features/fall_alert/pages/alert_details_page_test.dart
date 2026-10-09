// Tests for AlertDetailsPage and PatientFallPromptPage
// (lib/features/fall_alert/pages/alert_details_page.dart)
// (lib/features/fall_alert/pages/alert_details_page_patient.dart)

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/fall_alert/pages/alert_details_page.dart';
import 'package:care_connect_app/features/fall_alert/pages/alert_details_page_patient.dart';
import 'package:care_connect_app/features/fall_alert/models/fall_alert.dart';

FallAlert _makeAlert() => FallAlert(
      id: 'alert-1',
      patientId: 'patient-1',
      patientName: 'Jane Doe',
      detectedAtUtc: DateTime.utc(2025, 1, 1, 12),
      source: 'watch',
      hasLiveVideo: false,
    );

Widget _wrap() => MaterialApp(home: AlertDetailsPage(alert: _makeAlert()));

void main() {
  group('AlertDetailsPage – initial render', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(AlertDetailsPage), findsOneWidget);
    });

    testWidgets('shows "Fall Alert" in AppBar', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Fall Alert'), findsOneWidget);
    });

    testWidgets('shows patient name', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.textContaining('Jane Doe'), findsOneWidget);
    });

    testWidgets('shows Scaffold', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('does NOT show CircularProgressIndicator', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('AlertDetailsPage – content details', () {
    testWidgets('shows warning message', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Patient may need help.'), findsOneWidget);
    });

    testWidgets('shows warning icon', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });

    testWidgets('shows patient initials in CircleAvatar', (tester) async {
      await tester.pumpWidget(_wrap());
      // Jane Doe -> "JD"
      expect(find.text('JD'), findsOneWidget);
    });

    testWidgets('shows View Details button', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('View Details'), findsOneWidget);
    });

    testWidgets('shows person_outline icon for View Details', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byIcon(Icons.person_outline), findsOneWidget);
    });

    testWidgets('shows camera source text', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('camera'), findsOneWidget);
    });

    testWidgets('shows videocam_outlined icon', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byIcon(Icons.videocam_outlined), findsOneWidget);
    });

    testWidgets('shows access_time icon', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byIcon(Icons.access_time), findsOneWidget);
    });

    testWidgets('shows Call Patient button', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Call Patient'), findsOneWidget);
      expect(find.byIcon(Icons.call), findsOneWidget);
    });

    testWidgets('shows Send Message button', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Send Message'), findsOneWidget);
      expect(find.byIcon(Icons.message_outlined), findsOneWidget);
    });

    testWidgets('shows Contact Emergency Services button', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Contact Emergency Services'), findsOneWidget);
      expect(find.byIcon(Icons.emergency_share_rounded), findsOneWidget);
    });

    testWidgets('shows Playback Unavailable when no playback data', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Playback Unavailable'), findsOneWidget);
      expect(find.byIcon(Icons.videocam_off), findsOneWidget);
    });

    testWidgets('shows Details section', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Details'), findsOneWidget);
    });

    testWidgets('shows Source meta row with "watch"', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Source'), findsOneWidget);
      expect(find.text('watch'), findsOneWidget);
    });

    testWidgets('shows Patient phone as "Not available"', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Patient phone'), findsOneWidget);
      expect(find.text('Not available'), findsAtLeastNWidgets(1));
    });

    testWidgets('shows Playback meta row as "Not available"', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Playback'), findsOneWidget);
    });

    testWidgets('shows "No response from patient" for old alerts', (tester) async {
      // Alert detected at 2025-01-01 12:00 UTC, which is more than 2 minutes ago
      await tester.pumpWidget(_wrap());
      expect(find.text('No response from patient'), findsOneWidget);
    });

    testWidgets('shows SingleChildScrollView', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });

    testWidgets('tapping Call Patient with no phone shows SnackBar', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.ensureVisible(find.text('Call Patient'));
      await tester.pump();
      await tester.tap(find.text('Call Patient'));
      await tester.pump();
      expect(find.text('No phone number available'), findsOneWidget);
    });

    testWidgets('tapping Send Message with no phone shows SnackBar', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.ensureVisible(find.text('Send Message'));
      await tester.pump();
      await tester.tap(find.text('Send Message'));
      await tester.pump();
      expect(find.text('No phone number available'), findsOneWidget);
    });

    testWidgets('tapping Contact Emergency Services opens bottom sheet', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.ensureVisible(find.text('Contact Emergency Services'));
      await tester.pump();
      await tester.tap(find.text('Contact Emergency Services'));
      await tester.pumpAndSettle();
      expect(find.text('Emergency actions'), findsOneWidget);
      expect(find.text('Call 911'), findsOneWidget);
    });

    testWidgets('emergency bottom sheet shows "Call Emergency Contact"', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.ensureVisible(find.text('Contact Emergency Services'));
      await tester.pump();
      await tester.tap(find.text('Contact Emergency Services'));
      await tester.pumpAndSettle();
      expect(find.text('Call Emergency Contact'), findsOneWidget);
      expect(find.text('No phone on file'), findsOneWidget);
    });
  });

  group('AlertDetailsPage – initials helper', () {
    testWidgets('single name shows single initial', (tester) async {
      final alert = FallAlert(
        id: 'a2',
        patientId: 'p2',
        patientName: 'Madonna',
        detectedAtUtc: DateTime.utc(2025, 1, 1, 12),
        source: 'camera',
        hasLiveVideo: false,
      );
      await tester.pumpWidget(MaterialApp(home: AlertDetailsPage(alert: alert)));
      expect(find.text('M'), findsOneWidget);
    });

    testWidgets('empty name shows ?', (tester) async {
      final alert = FallAlert(
        id: 'a3',
        patientId: 'p3',
        patientName: '',
        detectedAtUtc: DateTime.utc(2025, 1, 1, 12),
        source: 'camera',
        hasLiveVideo: false,
      );
      await tester.pumpWidget(MaterialApp(home: AlertDetailsPage(alert: alert)));
      expect(find.text('?'), findsOneWidget);
    });

    testWidgets('three-word name shows first and last initial', (tester) async {
      final alert = FallAlert(
        id: 'a4',
        patientId: 'p4',
        patientName: 'Mary Jane Watson',
        detectedAtUtc: DateTime.utc(2025, 1, 1, 12),
        source: 'camera',
        hasLiveVideo: false,
      );
      await tester.pumpWidget(MaterialApp(home: AlertDetailsPage(alert: alert)));
      expect(find.text('MW'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // PatientFallPromptPage tests
  // ---------------------------------------------------------------------------

  group('PatientFallPromptPage – rendering', () {
    setUp(() => _installUrlLauncherMock());
    tearDown(() => _removeUrlLauncherMock());

    testWidgets('renders Fall Detected title', (tester) async {
      await tester.pumpWidget(_wrapPatient());
      expect(find.text('Fall Detected'), findsOneWidget);
    });

    testWidgets('shows Are You Okay? text', (tester) async {
      await tester.pumpWidget(_wrapPatient());
      expect(find.text('Are You Okay?'), findsOneWidget);
    });

    testWidgets('shows I\'m Okay button', (tester) async {
      await tester.pumpWidget(_wrapPatient());
      expect(find.text("I'm Okay"), findsOneWidget);
    });

    testWidgets('shows Call for Help button', (tester) async {
      await tester.pumpWidget(_wrapPatient());
      expect(find.text('Call for Help'), findsOneWidget);
    });

    testWidgets('shows countdown text', (tester) async {
      await tester.pumpWidget(_wrapPatient(autoCallSeconds: 30));
      expect(find.textContaining('Auto-calling in'), findsOneWidget);
      expect(find.text('Auto-calling in 30 seconds...'), findsOneWidget);
    });

    testWidgets('shows info banner about auto-call', (tester) async {
      await tester.pumpWidget(_wrapPatient(autoCallSeconds: 30));
      expect(
        find.textContaining('emergency services will be contacted automatically'),
        findsOneWidget,
      );
    });

    testWidgets('shows warning icon', (tester) async {
      await tester.pumpWidget(_wrapPatient());
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });

    testWidgets('shows description text', (tester) async {
      await tester.pumpWidget(_wrapPatient());
      expect(
        find.text('It looks like you may have fallen. Do you need help?'),
        findsOneWidget,
      );
    });

    testWidgets('shows Scaffold', (tester) async {
      await tester.pumpWidget(_wrapPatient());
      expect(find.byType(Scaffold), findsOneWidget);
    });
  });

  group('PatientFallPromptPage – I\'m Okay', () {
    setUp(() => _installUrlLauncherMock());
    tearDown(() => _removeUrlLauncherMock());

    testWidgets('tapping I\'m Okay calls onAcknowledgeOk', (tester) async {
      bool called = false;
      await tester.pumpWidget(_wrapPatient(
        onAcknowledgeOk: () async {
          called = true;
        },
      ));
      await tester.tap(find.text("I'm Okay"));
      await tester.pumpAndSettle();
      expect(called, isTrue);
    });

    testWidgets('tapping I\'m Okay without callback does not crash',
        (tester) async {
      await tester.pumpWidget(_wrapPatient());
      await tester.tap(find.text("I'm Okay"));
      await tester.pumpAndSettle();
      // Should not crash
    });

    testWidgets('tapping I\'m Okay shows snackbar', (tester) async {
      await tester.pumpWidget(_wrapPatient());
      await tester.tap(find.text("I'm Okay"));
      await tester.pump(); // start navigation
      await tester.pump(); // allow snackbar
      expect(
        find.text('Glad you are okay. We will dismiss this alert.'),
        findsOneWidget,
      );
    });
  });

  group('PatientFallPromptPage – Call for Help', () {
    setUp(() => _installUrlLauncherMock());
    tearDown(() => _removeUrlLauncherMock());

    testWidgets('tapping Call for Help opens bottom sheet', (tester) async {
      await tester.pumpWidget(_wrapPatient(
        emergencyContactName: 'Jane',
        emergencyContactPhone: '555-5555',
      ));
      await tester.tap(find.text('Call for Help'));
      await tester.pumpAndSettle();
      expect(find.text('Emergency actions'), findsOneWidget);
      expect(find.text('Call 911'), findsOneWidget);
      expect(find.text('Call Jane'), findsOneWidget);
    });

    testWidgets('bottom sheet shows fallback when no contact provided',
        (tester) async {
      await tester.pumpWidget(_wrapPatient());
      await tester.tap(find.text('Call for Help'));
      await tester.pumpAndSettle();
      expect(find.text('Call Emergency Contact'), findsOneWidget);
      expect(find.text('No phone on file'), findsOneWidget);
    });

    testWidgets('bottom sheet shows Choose how subtitle', (tester) async {
      await tester.pumpWidget(_wrapPatient());
      await tester.tap(find.text('Call for Help'));
      await tester.pumpAndSettle();
      expect(find.text('Choose how you want to escalate'), findsOneWidget);
    });

    testWidgets('tapping Call 911 in sheet triggers onEscalate',
        (tester) async {
      bool escalated = false;
      await tester.pumpWidget(_wrapPatient(
        onEscalate: () async {
          escalated = true;
        },
      ));
      await tester.tap(find.text('Call for Help'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Call 911'));
      await tester.pumpAndSettle();
      expect(escalated, isTrue);
    });

    testWidgets('tapping emergency contact calls their number',
        (tester) async {
      await tester.pumpWidget(_wrapPatient(
        emergencyContactName: 'Bob',
        emergencyContactPhone: '555-9999',
      ));
      await tester.tap(find.text('Call for Help'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Call Bob'));
      await tester.pumpAndSettle();
      // Should not crash – url_launcher mock handles it
    });

    testWidgets('emergency contact tile is disabled when no phone on file',
        (tester) async {
      await tester.pumpWidget(_wrapPatient());
      await tester.tap(find.text('Call for Help'));
      await tester.pumpAndSettle();
      // The tile labelled "Call Emergency Contact" should be present but disabled
      final listTile = tester.widget<ListTile>(
        find.ancestor(
          of: find.text('Call Emergency Contact'),
          matching: find.byType(ListTile),
        ),
      );
      expect(listTile.enabled, isFalse);
    });

    testWidgets('bottom sheet shows connect to local services subtitle',
        (tester) async {
      await tester.pumpWidget(_wrapPatient());
      await tester.tap(find.text('Call for Help'));
      await tester.pumpAndSettle();
      expect(
        find.text('Connect to local emergency services'),
        findsOneWidget,
      );
    });
  });

  group('PatientFallPromptPage – timer', () {
    setUp(() => _installUrlLauncherMock());
    tearDown(() => _removeUrlLauncherMock());

    testWidgets('countdown decreases over time', (tester) async {
      await tester.pumpWidget(_wrapPatient(autoCallSeconds: 5));
      expect(find.text('Auto-calling in 5 seconds...'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Auto-calling in 4 seconds...'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Auto-calling in 3 seconds...'), findsOneWidget);
    });

    testWidgets('auto-calls emergency when timer expires', (tester) async {
      bool escalated = false;
      await tester.pumpWidget(_wrapPatient(
        autoCallSeconds: 2,
        onEscalate: () async {
          escalated = true;
        },
      ));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(escalated, isTrue);
    });

    testWidgets('I\'m Okay stops the countdown timer', (tester) async {
      bool escalated = false;
      await tester.pumpWidget(_wrapPatient(
        autoCallSeconds: 3,
        onEscalate: () async {
          escalated = true;
        },
      ));
      // Tap I'm Okay before timer expires
      await tester.tap(find.text("I'm Okay"));
      await tester.pumpAndSettle();
      // Let remaining time pass
      await tester.pump(const Duration(seconds: 4));
      expect(escalated, isFalse);
    });
  });

  group('PatientFallPromptPage – custom emergency number', () {
    setUp(() => _installUrlLauncherMock());
    tearDown(() => _removeUrlLauncherMock());

    testWidgets('shows custom emergency number in sheet', (tester) async {
      await tester.pumpWidget(_wrapPatient(emergencyNumber: '112'));
      await tester.tap(find.text('Call for Help'));
      await tester.pumpAndSettle();
      expect(find.text('Call 112'), findsOneWidget);
    });
  });
}

// ---------------------------------------------------------------------------
// Helpers for PatientFallPromptPage
// ---------------------------------------------------------------------------

Widget _wrapPatient({
  int autoCallSeconds = 60,
  String emergencyNumber = '911',
  String? emergencyContactName,
  String? emergencyContactPhone,
  Future<void> Function()? onAcknowledgeOk,
  Future<void> Function()? onEscalate,
}) {
  return MaterialApp(
    home: PatientFallPromptPage(
      autoCallSeconds: autoCallSeconds,
      emergencyNumber: emergencyNumber,
      emergencyContactName: emergencyContactName,
      emergencyContactPhone: emergencyContactPhone,
      onAcknowledgeOk: onAcknowledgeOk,
      onEscalate: onEscalate,
    ),
  );
}

void _installUrlLauncherMock() {
  const channels = [
    'plugins.flutter.io/url_launcher',
    'plugins.flutter.io/url_launcher_android',
    'plugins.flutter.io/url_launcher_ios',
    'plugins.flutter.io/url_launcher_linux',
    'plugins.flutter.io/url_launcher_macos',
    'plugins.flutter.io/url_launcher_windows',
  ];
  for (final name in channels) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MethodChannel(name), (call) async {
      if (call.method == 'canLaunch') return true;
      if (call.method == 'launch') return true;
      if (call.method == 'launchUrl') return true;
      return null;
    });
  }
}

void _removeUrlLauncherMock() {
  const channels = [
    'plugins.flutter.io/url_launcher',
    'plugins.flutter.io/url_launcher_android',
    'plugins.flutter.io/url_launcher_ios',
    'plugins.flutter.io/url_launcher_linux',
    'plugins.flutter.io/url_launcher_macos',
    'plugins.flutter.io/url_launcher_windows',
  ];
  for (final name in channels) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MethodChannel(name), null);
  }
}
