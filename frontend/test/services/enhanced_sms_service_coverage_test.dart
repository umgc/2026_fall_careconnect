import 'dart:convert';

import 'package:care_connect_app/services/enhanced_sms_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _launcher = MethodChannel('plugins.flutter.io/url_launcher');

void _mockLauncher(Object? Function(MethodCall call) handler) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_launcher, (call) async => handler(call));
}

Future<BuildContext> _context(WidgetTester tester) async {
  await tester.pumpWidget(
    const MaterialApp(home: Scaffold(body: Text('host'))),
  );
  return tester.element(find.text('host'));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_launcher, null);
  });

  testWidgets('sendSMS via backend success shows green snackbar',
      (tester) async {
    final context = await _context(tester);
    final ok = await http.runWithClient(
      () => EnhancedSMSService.sendSMS(
        toPhone: '555-1234',
        message: 'hi',
        fromUserId: '1',
        fromUserName: 'Cara',
        authToken: 'tok',
        context: context,
      ),
      () => MockClient((req) async {
        expect(req.headers['Authorization'], 'Bearer tok');
        return http.Response(
          jsonEncode({'success': true, 'message': 'queued'}),
          200,
        );
      }),
    );
    expect(ok, isTrue);
    await tester.pump();
    expect(find.text('✅ SMS sent successfully'), findsOneWidget);
  });

  testWidgets('backend failure falls back to SMS app', (tester) async {
    _mockLauncher((_) => true);
    final context = await _context(tester);
    await http.runWithClient(
      () => SMSIntegrationExamples.sendCaregiverToPatientSMS(
        patientPhone: '(555) 123-4567',
        message: 'hello',
        caregiverUserId: '2',
        caregiverName: 'Cara',
        context: context,
      ),
      () => MockClient((_) async => http.Response('down', 500)),
    );
    await tester.pump();
    expect(find.text('📱 SMS app opened'), findsOneWidget);
  });

  testWidgets('fallback cannot launch shows failure snackbar',
      (tester) async {
    _mockLauncher((_) => false);
    final context = await _context(tester);
    await http.runWithClient(
      () => SMSIntegrationExamples.sendPatientToCaregiverSMS(
        caregiverPhone: '555',
        message: 'hello',
        patientUserId: '3',
        patientName: 'Pat',
        context: context,
      ),
      () => MockClient((_) async => throw Exception('offline')),
    );
    await tester.pump();
    expect(find.text('❌ Failed to send SMS'), findsOneWidget);
  });

  test('sendSMSFallback returns false when launcher throws', () async {
    _mockLauncher((_) => throw PlatformException(code: 'x'));
    expect(
      await EnhancedSMSService.sendSMSFallback(toPhone: '1', message: 'm'),
      isFalse,
    );
  });

  testWidgets('emergency SMS success and failure snackbars', (tester) async {
    final context = await _context(tester);
    await http.runWithClient(
      () => SMSIntegrationExamples.sendPatientEmergency(
        patientUserId: '9',
        emergencyMessage: 'Help',
        location: 'Home',
        authToken: 'tok',
        context: context,
      ),
      () => MockClient((_) async => http.Response(
            jsonEncode({'success': true, 'sentCount': 2}),
            200,
          )),
    );
    await tester.pump();
    expect(find.text('🚨 Emergency alert sent to all contacts'), findsOneWidget);

    expect(
      await http.runWithClient(
        () => EnhancedSMSService.sendEmergencySMS(
          patientId: '9',
          message: 'Help',
        ),
        () => MockClient((_) async => http.Response('err', 503)),
      ),
      isFalse,
    );
    expect(
      await http.runWithClient(
        () => EnhancedSMSService.sendEmergencySMS(
          patientId: '9',
          message: 'Help',
        ),
        () => MockClient((_) async => throw Exception('boom')),
      ),
      isFalse,
    );
  });
}
