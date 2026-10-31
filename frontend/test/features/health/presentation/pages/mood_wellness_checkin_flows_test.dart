// Submission tests for MoodWellnessCheckIn
// (lib/features/health/presentation/pages/mood_wellness_checkin.dart):
// slider changes and the success, queued and failure outcomes.

import 'package:care_connect_app/features/health/presentation/pages/mood_wellness_checkin.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../mock_user_provider.dart';

late http.Response Function() _response;

Future<void> _submit(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider<UserProvider>.value(
      value: MockUserProvider(),
      child: const MaterialApp(home: MoodWellnessCheckIn()),
    ),
  );
  final sliders = find.byType(Slider);
  tester.widget<Slider>(sliders.first).onChanged!(8);
  tester.widget<Slider>(sliders.last).onChanged!(2);
  await tester.pump();
  await tester.enterText(find.byType(TextField), 'Good day');
  final submit = find.text('Submit');
  await tester.ensureVisible(submit);
  await tester.tap(submit);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  setUpAll(() => ApiService.debugSetHttpClient(
        MockClient((_) async => _response()),
      ));

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => call.method == 'readAll' ? <String, String>{} : null,
    );
  });

  testWidgets('successful submission shows confirmation', (tester) async {
    _response = () => http.Response('{}', 201);
    await _submit(tester);
    expect(find.text('Mood & Pain submitted successfully!'), findsOneWidget);
  });

  testWidgets('queued submission shows sync message', (tester) async {
    _response =
        () => http.Response('{}', 200, headers: {'x-offline-queued': 'true'});
    await _submit(tester);
    expect(
      find.text('Mood check-in queued for sync when internet is restored'),
      findsOneWidget,
    );
  });

  testWidgets('failed submission shows error', (tester) async {
    _response = () => http.Response('no', 500);
    await _submit(tester);
    expect(find.textContaining('Failed to submit:'), findsOneWidget);
  });
}
