// Coverage-focused widget tests (group I): search, incident history and
// communication actions.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/features/health/caregiver-patient-list/page/incident_report_history_screen.dart';
import 'package:care_connect_app/features/social/presentation/pages/search_user_screen.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:care_connect_app/widgets/communication_widget.dart';

import '../mock_user_provider.dart';

const _secure = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void _api(Future<http.Response> Function(http.Request) handler) {
  ApiService.debugSetHttpClient(MockClient(handler));
  addTearDown(ApiService.debugResetHttpClient);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secure,
            (call) async => call.method == 'readAll' ? <String, String>{} : null);
  });

  group('IncidentReportHistoryScreen', () {
    testWidgets('empty list shows the empty message', (tester) async {
      _api((_) async => http.Response('[]', 200));
      await tester.pumpWidget(const MaterialApp(
          home: IncidentReportHistoryScreen(
              clientId: 7, clientName: 'Mary Johnson')));
      await _settle(tester);
      expect(find.text('No incident reports logged yet.'), findsOneWidget);
    });

    testWidgets('network exception shows error text', (tester) async {
      _api((_) async => throw Exception('offline'));
      await tester.pumpWidget(const MaterialApp(
          home: IncidentReportHistoryScreen(
              clientId: 7, clientName: 'Mary Johnson')));
      await _settle(tester);
      expect(find.textContaining('Error: '), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  });

  group('SearchUserScreen', () {
    Widget app() => ChangeNotifierProvider<UserProvider>.value(
          value: MockUserProvider(
              mockUser: MockUser(id: 1, role: 'PATIENT', patientId: 1)),
          child: const MaterialApp(home: SearchUserScreen()),
        );

    testWidgets('loading spinner, friend request error and search error',
        (tester) async {
      var failSearch = false;
      final gate = Completer<void>();
      _api((req) async {
        if (req.method == 'POST') throw Exception('request boom');
        if (failSearch) throw Exception('search boom');
        await gate.future;
        return http.Response(
            jsonEncode([
              {'id': 2, 'name': 'Alex Kim', 'email': 'alex@example.com'}
            ]),
            200);
      });
      await tester.pumpWidget(app());
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'alex');
      await tester.tap(find.byIcon(Icons.search));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      gate.complete();
      await _settle(tester);
      expect(find.text('Alex Kim'), findsOneWidget);

      await tester.tap(find.byType(ElevatedButton).last);
      await _settle(tester);
      expect(find.textContaining('request boom'), findsOneWidget);

      failSearch = true;
      await tester.tap(find.byIcon(Icons.search));
      await _settle(tester);
      expect(find.text('Search Users'), findsWidgets);
    });
  });

  group('CommunicationWidget', () {
    Widget app({String? phone}) => MaterialApp(
          home: Scaffold(
            body: CommunicationWidget(
              currentUserId: '1',
              currentUserName: 'Casey',
              targetUserId: '2',
              targetUserName: 'Pat',
              targetPhoneNumber: phone,
            ),
          ),
        );

    testWidgets('empty phone reports unavailable', (tester) async {
      await tester.pumpWidget(app(phone: ''));
      await tester.pump();
      await tester.tap(find.text('SMS'));
      await tester.pump();
      expect(find.text('Phone number not available'), findsOneWidget);
    });

    testWidgets('message send reports success', (tester) async {
      await tester.pumpWidget(app());
      await tester.pump();
      await tester.tap(find.text('Message'));
      await tester.pumpAndSettle();
      expect(find.text('Send Message to Pat'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Hello there');
      await tester.tap(find.text('Send'));
      await _settle(tester);
      expect(find.byType(CommunicationWidget), findsOneWidget);
    });

    testWidgets('sms send completes', (tester) async {
      await tester.pumpWidget(app(phone: '5551234567'));
      await tester.pump();
      await tester.tap(find.text('SMS'));
      await tester.pumpAndSettle();
      expect(find.text('Send SMS to Pat'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Hi');
      await tester.tap(find.text('Send'));
      await _settle(tester);
      expect(find.byType(CommunicationWidget), findsOneWidget);
    });
  });
}
