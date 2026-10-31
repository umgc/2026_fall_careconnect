// Interaction tests for AlertDetailsPage
// (lib/features/fall_alert/pages/alert_details_page.dart): phone/SMS
// launch outcomes, playback section, View Details guard and the
// emergency actions sheet.

import 'package:care_connect_app/features/fall_alert/models/fall_alert.dart';
import 'package:care_connect_app/features/fall_alert/pages/alert_details_page.dart';
import 'package:care_connect_app/features/fall_alert/pages/skeleton_playback_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _channels = [
  'plugins.flutter.io/url_launcher',
  'plugins.flutter.io/url_launcher_android',
  'plugins.flutter.io/url_launcher_ios',
  'plugins.flutter.io/url_launcher_windows',
];

/// Installs a url_launcher mock that answers [launchResult] and records URLs.
List<String> _mockLauncher(bool launchResult) {
  final urls = <String>[];
  for (final name in _channels) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MethodChannel(name), (call) async {
      final args = call.arguments;
      if (args is Map && args['url'] != null) urls.add('${args['url']}');
      if (call.method == 'canLaunch') return true;
      return launchResult;
    });
  }
  return urls;
}

FallAlert _alert({
  String patientId = 'p-1',
  String? phone = '+15550001111',
  String? contactPhone = '+15550002222',
  Map<String, dynamic>? playback,
}) =>
    FallAlert(
      id: 'a-1',
      patientId: patientId,
      patientName: 'Robin Test',
      detectedAtUtc: DateTime.now().toUtc(),
      source: 'camera',
      hasLiveVideo: false,
      patientPhone: phone,
      emergencyContactName: 'Casey',
      emergencyContactPhone: contactPhone,
      playbackData: playback,
    );

Future<void> _pump(WidgetTester tester, FallAlert alert) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: AlertDetailsPage(alert: alert)));
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, String text) async {
  final f = find.text(text);
  await tester.ensureVisible(f);
  await tester.tap(f);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  tearDown(() {
    for (final name in _channels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(name), null);
    }
  });

  testWidgets('recent alert hides no-response badge and shows playback',
      (tester) async {
    await _pump(tester, _alert(playback: const {}));
    expect(find.text('No response from patient'), findsNothing);
    expect(find.text('Fall Playback'), findsOneWidget);
    expect(find.byType(SkeletonPlaybackWidget), findsOneWidget);
    expect(find.text('Available'), findsOneWidget);
    expect(find.text('Playback Unavailable'), findsNothing);
  });

  testWidgets('call and message launch tel and sms URIs', (tester) async {
    final urls = _mockLauncher(true);
    await _pump(tester, _alert());
    await _tap(tester, 'Call Patient');
    await _tap(tester, 'Send Message');
    expect(urls.any((u) => u.startsWith('tel:+15550001111')), isTrue);
    expect(urls.any((u) => u.startsWith('sms:+15550001111')), isTrue);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('failed call launch shows a toast', (tester) async {
    _mockLauncher(false);
    await _pump(tester, _alert());
    await _tap(tester, 'Call Patient');
    expect(find.text('Call failed to start'), findsOneWidget);
  });

  testWidgets('failed message launch shows a toast', (tester) async {
    _mockLauncher(false);
    await _pump(tester, _alert());
    await _tap(tester, 'Send Message');
    expect(find.text('Message failed to start'), findsOneWidget);
  });

  testWidgets('View Details without patient id shows a toast',
      (tester) async {
    await _pump(tester, _alert(patientId: ''));
    await _tap(tester, 'View Details');
    expect(find.text('Patient ID not available'), findsOneWidget);
  });

  testWidgets('emergency sheet Call 911 failure shows a toast',
      (tester) async {
    final urls = _mockLauncher(false);
    await _pump(tester, _alert());
    await _tap(tester, 'Contact Emergency Services');
    await tester.pumpAndSettle();
    expect(find.text('Emergency actions'), findsOneWidget);
    await _tap(tester, 'Call 911');
    await tester.pumpAndSettle();
    expect(urls.any((u) => u.startsWith('tel:911')), isTrue);
    expect(find.text('Could not start call to 911'), findsOneWidget);
  });

  testWidgets('emergency sheet calls the emergency contact', (tester) async {
    final urls = _mockLauncher(false);
    await _pump(tester, _alert());
    await _tap(tester, 'Contact Emergency Services');
    await tester.pumpAndSettle();
    expect(find.text('+15550002222'), findsWidgets);
    await _tap(tester, 'Call Casey');
    await tester.pumpAndSettle();
    expect(urls.any((u) => u.startsWith('tel:+15550002222')), isTrue);
    expect(find.text('Could not start call to Casey'), findsOneWidget);
  });

  testWidgets('successful emergency calls show no toast', (tester) async {
    _mockLauncher(true);
    await _pump(tester, _alert());
    await _tap(tester, 'Contact Emergency Services');
    await tester.pumpAndSettle();
    await _tap(tester, 'Call 911');
    await tester.pumpAndSettle();
    await _tap(tester, 'Contact Emergency Services');
    await tester.pumpAndSettle();
    await _tap(tester, 'Call Casey');
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  });
}
