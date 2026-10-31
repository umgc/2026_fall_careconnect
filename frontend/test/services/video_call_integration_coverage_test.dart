// Additional coverage for VideoCallIntegration's backend pass-throughs and
// BackendStatusWidget. HTTP is intercepted with http.runWithClient.
import 'dart:convert';

import 'package:care_connect_app/services/video_call_integration.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  setUp(() {
    VideoCallIntegration.initialize('integration-token');
  });

  group('sendSMSToPatient', () {
    test('returns false without calling backend when phone missing', () async {
      var called = false;
      final ok = await http.runWithClient(
        () => VideoCallIntegration.sendSMSToPatient(
          caregiverName: 'Casey',
          patientData: const {'id': 1},
          message: 'hi',
        ),
        () => MockClient((_) async {
          called = true;
          return http.Response('', 200);
        }),
      );
      expect(ok, isFalse);
      expect(called, isFalse);
    });

    test('posts SMS via backend when phone present', () async {
      http.Request? captured;
      final ok = await http.runWithClient(
        () => VideoCallIntegration.sendSMSToPatient(
          caregiverName: 'Casey',
          patientData: const {'id': 1, 'phone': '555-0100'},
          message: 'hello',
        ),
        () => MockClient((req) async {
          captured = req;
          return http.Response('{}', 200);
        }),
      );
      expect(ok, isTrue);
      expect(captured, isNotNull);
      expect(captured!.headers['Authorization'], 'Bearer integration-token');
    });
  });

  test('getCaregiverPatients delegates to backend', () async {
    final body = jsonEncode([
      {
        'patient': {'id': 7, 'firstName': 'Ann'},
        'link': {'id': 3, 'status': 'ACTIVE'},
      },
    ]);
    final result = await http.runWithClient(
      () => VideoCallIntegration.getCaregiverPatients(5),
      () => MockClient((req) async {
        expect(req.url.path, contains('/caregivers/5/patients'));
        return http.Response(body, 200);
      }),
    );
    expect(result, hasLength(1));
    expect(result.first['firstName'], 'Ann');
  });

  test('getConversation delegates to backend', () async {
    final result = await http.runWithClient(
      () => VideoCallIntegration.getConversation('a', 'b'),
      () => MockClient((_) async => http.Response('nope', 500)),
    );
    expect(result, isEmpty);
  });

  test('sendMessage delegates to backend', () async {
    final ok = await http.runWithClient(
      () => VideoCallIntegration.sendMessage(
        senderId: '1',
        senderName: 'Casey',
        recipientId: '2',
        message: 'msg',
      ),
      () => MockClient((_) async => http.Response('{}', 201)),
    );
    expect(ok, isTrue);
  });

  test('getCallHistory delegates to backend', () async {
    final result = await http.runWithClient(
      () => VideoCallIntegration.getCallHistory('u1'),
      () => MockClient((_) async => http.Response(
          jsonEncode([
            {'id': 1},
            {'id': 2},
          ]),
          200)),
    );
    expect(result, hasLength(2));
  });

  test('testBackendConnection reflects backend health', () async {
    final ok = await http.runWithClient(
      () => VideoCallIntegration.testBackendConnection(),
      () => MockClient((_) async => http.Response('ok', 200)),
    );
    expect(ok, isTrue);
  });

  group('BackendStatusWidget', () {
    Future<void> pumpStatus(WidgetTester tester, int status) async {
      await http.runWithClient(
        () async {
          await tester.pumpWidget(const MaterialApp(
            home: Scaffold(body: Center(child: BackendStatusWidget())),
          ));
        },
        () => MockClient((_) async => http.Response('x', status)),
      );
    }

    testWidgets('shows loading then connected', (tester) async {
      await pumpStatus(tester, 200);
      expect(find.text('Checking backend...'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('Backend Connected'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_done), findsOneWidget);
    });

    testWidgets('shows offline when backend unhealthy', (tester) async {
      await pumpStatus(tester, 503);
      await tester.pumpAndSettle();
      expect(find.text('Backend Offline'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off), findsOneWidget);
    });
  });
}
