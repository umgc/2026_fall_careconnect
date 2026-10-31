// Tests for StmlBriefPage
// (lib/features/stml/presentation/pages/stml_brief_page.dart).

import 'dart:convert';

import 'package:care_connect_app/features/stml/presentation/pages/stml_brief_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../../../mock_user_provider.dart';
import 'stml_test_harness.dart';

void main() {
  setUp(installStmlPlatformMocks);

  testWidgets('renders every card type with detail, time and disclaimer',
      (tester) async {
    final client = MockClient((req) async => http.Response(
        jsonEncode({
          'patientId': 1,
          'generatedAt': '2026-10-01T07:00:00Z',
          'disclaimer': 'Summaries may be incomplete.',
          'cards': [
            {
              'type': 'APPOINTMENT',
              'headline': 'Cardiology visit',
              'detail': 'Thursday 2pm',
              'timestamp': '2026-10-02T14:00:00Z',
            },
            {'type': 'ACTION_ITEM', 'headline': 'Call pharmacy'},
            {'type': 'MEDICATION', 'headline': 'Take metformin'},
            {'type': 'RECALL', 'headline': 'Talked to daughter'},
          ],
        }),
        200));
    await http.runWithClient(() async {
      await pumpStmlPage(tester, const StmlBriefPage());
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await settle(tester);
    }, () => client);
    expect(find.text('Your Daily Brief'), findsOneWidget);
    expect(find.text('Cardiology visit'), findsOneWidget);
    expect(find.text('Thursday 2pm'), findsOneWidget);
    expect(find.text('Call pharmacy'), findsOneWidget);
    expect(find.text('Take metformin'), findsOneWidget);
    expect(find.text('Talked to daughter'), findsOneWidget);
    expect(find.text('Summaries may be incomplete.'), findsOneWidget);
  });

  testWidgets('empty brief shows the nothing-new message', (tester) async {
    final client = MockClient((req) async => http.Response(
        jsonEncode({'patientId': 1, 'cards': [], 'disclaimer': 'Note'}),
        200));
    await http.runWithClient(() async {
      await pumpStmlPage(tester, const StmlBriefPage());
      await settle(tester);
    }, () => client);
    expect(find.textContaining('Nothing new right now'), findsOneWidget);
  });

  testWidgets('error shows retry which reloads', (tester) async {
    var calls = 0;
    final client = MockClient((req) async {
      calls++;
      // Delay so the retried future is subscribed before it fails.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return http.Response('', 500);
    });
    await http.runWithClient(() async {
      await pumpStmlPage(tester, const StmlBriefPage());
      await settle(tester);
      expect(find.text('Something went wrong. Please try again.'),
          findsOneWidget);
      await tester.tap(find.text('Try again'));
      await settle(tester);
    }, () => client);
    expect(calls, 2);
  });

  testWidgets('no patient shows message; buttons navigate', (tester) async {
    await pumpStmlPage(
      tester,
      const StmlBriefPage(),
      provider: MockUserProvider(mockUser: MockUser(patientId: null)),
    );
    await settle(tester);
    expect(find.text('No patient is selected for this account.'),
        findsOneWidget);

    await tester.tap(find.byTooltip('Ask what we discussed'));
    await settle(tester);
    expect(find.text('route:/stml/recall'), findsOneWidget);
  });

  testWidgets('continue button routes to login when no stored session',
      (tester) async {
    await pumpStmlPage(
      tester,
      const StmlBriefPage(),
      provider: MockUserProvider(mockUser: MockUser(patientId: null)),
    );
    await settle(tester);
    await tester.tap(find.text('Continue to Dashboard'));
    await settle(tester);
    expect(find.text('route:/login'), findsOneWidget);
  });
}
