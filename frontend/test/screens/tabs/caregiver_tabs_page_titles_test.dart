// Page-title test for CaregiverAnalyticsTab
// (lib/screens/tabs/caregiver_tabs.dart): tapping a call in a patient's call
// history opens a page titled "Call Summary" (WCAG 2.4.2).
import 'dart:convert';
import 'dart:io';

import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/screens/tabs/caregiver_tabs.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/titled_route_probe.dart';
import '../../mock_user_provider.dart';

void main() {
  // The history's Sort and Label dropdowns have fixed widths that the test
  // font's square glyphs overflow, so lay them out in Roboto (bundled with the
  // tests, Apache 2.0) as the app does.
  setUpAll(() async {
    final loader = FontLoader('Roboto');
    for (final font in ['regular', 'medium', 'bold']) {
      loader.addFont(File('test/fixtures/fonts/roboto-$font.ttf')
          .readAsBytes()
          .then(ByteData.sublistView));
    }
    await loader.load();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (_) async => null,
    );
    ApiService.debugSetHttpClient(MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/patients')) {
        return http.Response(
            jsonEncode([
              {
                'link': {'patientUserId': 34},
                'patient': {'firstName': 'Mary', 'lastName': 'Johnson'},
              },
            ]),
            200);
      }
      if (path.endsWith('/sentiment-history')) {
        return http.Response(
            jsonEncode([
              {
                'callId': 'call-123',
                'callDate': '2026-10-20T10:00:00',
                'overallLabel': 'POSITIVE',
                'overallScore': 0.8,
                'durationMinutes': 12,
              },
            ]),
            200);
      }
      return http.Response('[]', 200);
    }));
  });

  tearDown(ApiService.debugResetHttpClient);

  testWidgets('a call in the history opens a page titled "Call Summary"',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final probe = TitledRouteProbe();
    await tester.pumpWidget(ChangeNotifierProvider<UserProvider>.value(
      value: MockUserProvider(
          mockUser: MockUser(id: 10, role: 'CAREGIVER', caregiverId: 7)),
      child: MaterialApp(
        navigatorObservers: [probe],
        home: const CaregiverAnalyticsTab(),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mary Johnson').last);
    await tester.pumpAndSettle();

    expect(
        await probe.tapAndReadTitle(tester, find.byIcon(Icons.call).first),
        'Call Summary');
  });
}
