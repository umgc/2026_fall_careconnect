// Happy-path tests for PatientCheckInDetailPage
// (lib/features/health/virtual_check_in/presentation/pages/patient_check_in_detail_page.dart):
// answering questions, submitting, the success view and a submit failure.

import 'dart:convert';

import 'package:care_connect_app/features/health/virtual_check_in/models/question_type.dart';
import 'package:care_connect_app/features/health/virtual_check_in/models/virtual_check_in_backend_question_model.dart';
import 'package:care_connect_app/features/health/virtual_check_in/presentation/pages/patient_check_in_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

late http.Response Function() _response;
final _client = MockClient((_) async => _response());

const _questions = [
  BackendQuestionDto(
    id: 1,
    prompt: 'How do you feel?',
    type: BackendQuestionType.text,
    required: true,
    active: true,
    ordinal: 1,
  ),
  BackendQuestionDto(
    id: 2,
    prompt: 'Did you sleep well?',
    type: BackendQuestionType.yesNo,
    required: false,
    active: true,
    ordinal: 2,
  ),
];

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const PatientCheckInDetailPage(
                  checkInId: 7,
                  questions: _questions,
                ),
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Future<void> _answerAndSubmit(WidgetTester tester) async {
  await tester.enterText(find.byType(TextFormField).first, 'Fine');
  await tester.tap(find.text('Yes'));
  await tester.pump();
  final submit = find.text('Submit Answers');
  await tester.ensureVisible(submit);
  await http.runWithClient(() async {
    await tester.tap(submit);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }, () => _client);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => call.method == 'readAll' ? <String, String>{} : null,
    );
  });

  testWidgets('submits answers, shows success and returns', (tester) async {
    _response = () => http.Response(
          jsonEncode({'checkInId': 7, 'acceptedAnswerCount': 2}),
          201,
        );
    await _pump(tester);
    expect(find.text('Please answer the following questions:'),
        findsOneWidget);
    await _answerAndSubmit(tester);
    expect(find.text('Successfully submitted 2 answer(s)'), findsOneWidget);
    // Auto-return after the success delay.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('submit failure shows the error banner', (tester) async {
    _response = () => http.Response(jsonEncode({'message': 'Closed'}), 400);
    await _pump(tester);
    await _answerAndSubmit(tester);
    expect(find.textContaining('Error: '), findsOneWidget);
  });

  testWidgets('back arrow closes the page', (tester) async {
    await _pump(tester);
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
  });
}
