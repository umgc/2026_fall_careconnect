// Tests for StmlSearchPage
// (lib/features/stml/presentation/pages/stml_search_page.dart).
// StmlService uses package:http top-level calls, so each test body runs
// inside http.runWithClient with a MockClient.

import 'dart:convert';

import 'package:care_connect_app/features/stml/presentation/pages/stml_search_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../../../mock_user_provider.dart';
import 'stml_test_harness.dart';

void main() {
  setUp(installStmlPlatformMocks);

  testWidgets('shows the prompt before any search', (tester) async {
    await pumpStmlPage(tester, const StmlSearchPage());
    expect(find.text('Search your history'), findsOneWidget);
    expect(find.textContaining('Enter a keyword, sender, or date range'),
        findsOneWidget);
  });

  testWidgets('keyword search lists results', (tester) async {
    Map<String, dynamic>? body;
    final client = MockClient((req) async {
      body = jsonDecode(req.body) as Map<String, dynamic>;
      return http.Response(
          jsonEncode({
            'totalResults': 2,
            'results': [
              {
                'sourceType': 'CALL',
                'content': 'Talked about medication',
                'sender': 'Dr. Lee',
                'date': '2026-10-01',
                'conversationId': 'c1',
              },
              {
                'sourceType': 'MAIL',
                'content': 'Letter from clinic',
                'sender': '',
                'date': '2026-10-02',
                'conversationId': 'c2',
              },
            ],
          }),
          200);
    });
    await http.runWithClient(() async {
      await pumpStmlPage(tester, const StmlSearchPage());
      await tester.enterText(find.byType(TextField).first, 'medication');
      await tester.enterText(find.byType(TextField).at(1), 'Dr. Lee');
      // Typing alone does not rebuild the Search button, so submit from
      // the keyboard.
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      await settle(tester);
    }, () => client);

    expect(body?['keyword'], 'medication');
    expect(body?['sender'], 'Dr. Lee');
    expect(find.text('Talked about medication'), findsOneWidget);
    expect(find.text('Letter from clinic'), findsOneWidget);
    expect(find.text('Dr. Lee'), findsWidgets);
  });

  testWidgets('empty results show the no-results message', (tester) async {
    final client = MockClient((req) async =>
        http.Response(jsonEncode({'totalResults': 0, 'results': []}), 200));
    await http.runWithClient(() async {
      await pumpStmlPage(tester, const StmlSearchPage());
      await tester.enterText(find.byType(TextField).first, 'x');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await settle(tester);
    }, () => client);
    expect(find.text('No results found for these filters.'), findsOneWidget);
  });

  testWidgets('403 shows the error state and retry re-runs the search',
      (tester) async {
    var calls = 0;
    final client = MockClient((req) async {
      calls++;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return http.Response('', 403);
    });
    await http.runWithClient(() async {
      await pumpStmlPage(tester, const StmlSearchPage());
      await tester.enterText(find.byType(TextField).first, 'visit');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await settle(tester);
      expect(find.textContaining("aren't authorized"), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await settle(tester);
    }, () => client);
    expect(calls, 2);
  });

  testWidgets('no patient on the account sends no search', (tester) async {
    var calls = 0;
    final client = MockClient((req) async {
      calls++;
      return http.Response('{}', 200);
    });
    await http.runWithClient(() async {
      await pumpStmlPage(
        tester,
        const StmlSearchPage(),
        provider: MockUserProvider(mockUser: MockUser(patientId: null)),
      );
      await tester.enterText(find.byType(TextField).first, 'visit');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await settle(tester);
    }, () => client);
    expect(calls, 0);
  });

  testWidgets('date pickers set from and to dates', (tester) async {
    Map<String, dynamic>? body;
    final client = MockClient((req) async {
      body = jsonDecode(req.body) as Map<String, dynamic>;
      return http.Response(jsonEncode({'results': []}), 200);
    });
    await http.runWithClient(() async {
      await pumpStmlPage(tester, const StmlSearchPage());
      await tester.tap(find.text('From date'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('To date'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('From date'), findsNothing);
      expect(find.text('To date'), findsNothing);
      await tester.tap(find.text('Search'));
      await settle(tester);
    }, () => client);
    expect(body?['fromDate'], isNotNull);
    expect(body?['toDate'], isNotNull);
  });
}
