// Tests for StmlRecallPage
// (lib/features/stml/presentation/pages/stml_recall_page.dart).

import 'dart:convert';

import 'package:care_connect_app/features/stml/presentation/pages/stml_recall_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../../../mock_user_provider.dart';
import 'stml_test_harness.dart';

void main() {
  setUp(installStmlPlatformMocks);

  testWidgets('suggestion tap shows the answer with sources and disclaimer',
      (tester) async {
    final client = MockClient((req) async => http.Response(
        jsonEncode({
          'answer': 'You discussed your new medication.',
          'sources': [
            {'sourceType': 'CALL', 'summary': 'Pharmacy call', 'date': 'Oct 1'},
          ],
          'disclaimer': 'Based on your records.',
        }),
        200));
    await http.runWithClient(() async {
      await pumpStmlPage(tester, const StmlRecallPage());
      expect(find.text('What did we discuss?'), findsOneWidget);
      await tester.tap(find.text('What do I need to do next?'));
      await tester.pump();
      await settle(tester);
    }, () => client);
    expect(find.text('What do I need to do next?'), findsOneWidget);
    expect(find.text('You discussed your new medication.'), findsOneWidget);
    expect(find.text('CALL · Oct 1: Pharmacy call'), findsOneWidget);
    expect(find.text('Based on your records.'), findsOneWidget);
  });

  testWidgets('typed question with an error response shows the error',
      (tester) async {
    final client = MockClient((req) async => http.Response('', 401));
    await http.runWithClient(() async {
      await pumpStmlPage(tester, const StmlRecallPage());
      await tester.enterText(find.byType(TextField), 'When is my visit?');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();
      await settle(tester);
    }, () => client);
    expect(find.text('When is my visit?'), findsOneWidget);
    expect(find.text('Please log in again.'), findsOneWidget);
  });

  testWidgets('submitting from the keyboard sends the question',
      (tester) async {
    final client = MockClient((req) async => http.Response(
        jsonEncode({'answer': 'Nothing pending.', 'sources': []}), 200));
    await http.runWithClient(() async {
      await pumpStmlPage(tester, const StmlRecallPage());
      await tester.enterText(find.byType(TextField), 'Anything due?');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();
      await settle(tester);
    }, () => client);
    expect(find.text('Nothing pending.'), findsOneWidget);
  });

  testWidgets('no patient shows a snackbar', (tester) async {
    await pumpStmlPage(
      tester,
      const StmlRecallPage(),
      provider: MockUserProvider(mockUser: MockUser(patientId: null)),
    );
    await tester.tap(find.text('What did we discuss in my last call?'));
    await tester.pump();
    expect(find.text('No patient is selected for this account.'),
        findsOneWidget);
  });
}
