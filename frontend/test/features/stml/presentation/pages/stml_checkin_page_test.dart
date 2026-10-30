// Tests for StmlCheckInPage and StmlCheckInPatientSelectionPage
// (lib/features/stml/presentation/pages/stml_checkin_page.dart,
//  lib/features/stml/presentation/pages/stml_checkin_patient_selection_page.dart).

import 'dart:convert';

import 'package:care_connect_app/features/stml/presentation/pages/stml_checkin_page.dart';
import 'package:care_connect_app/features/stml/presentation/pages/stml_checkin_patient_selection_page.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../../../mock_user_provider.dart';
import 'stml_test_harness.dart';

MockUserProvider _caregiver() => MockUserProvider(
      mockUser: MockUser(role: 'CAREGIVER', patientId: null, caregiverId: 9),
    );

void main() {
  setUp(installStmlPlatformMocks);

  group('StmlCheckInPage', () {
    testWidgets('shows pending items, notes and disclaimer', (tester) async {
      Uri? url;
      final client = MockClient((req) async {
        url = req.url;
        return http.Response(
            jsonEncode({
              'consentGranted': true,
              'disclaimer': 'Prepared from records.',
              'pendingItems': [
                {
                  'type': 'ACTION_ITEM',
                  'summary': 'Refill prescription',
                  'date': '2026-10-01',
                  'source': 'CALL',
                },
              ],
              'notes': [
                {
                  'type': 'NOTE',
                  'summary': 'Felt tired',
                  'date': '2026-10-02',
                  'source': 'VISIT',
                },
              ],
            }),
            200);
      });
      await http.runWithClient(() async {
        await pumpStmlPage(tester, const StmlCheckInPage(patientId: 3),
            provider: _caregiver());
        await settle(tester);
      }, () => client);
      expect(url?.path, contains('/patients/3/checkin'));
      expect(find.text('Check-in Prep'), findsOneWidget);
      expect(find.text('Pending items'), findsOneWidget);
      expect(find.text('Notes'), findsOneWidget);
      expect(find.text('Refill prescription'), findsOneWidget);
      expect(find.text('Felt tired'), findsOneWidget);
      expect(find.text('Prepared from records.'), findsOneWidget);
    });

    testWidgets('consent denied shows the consent message', (tester) async {
      final client = MockClient((req) async =>
          http.Response(jsonEncode({'consentGranted': false}), 200));
      await http.runWithClient(() async {
        await pumpStmlPage(tester, const StmlCheckInPage(patientId: 3),
            provider: _caregiver());
        await settle(tester);
      }, () => client);
      expect(find.textContaining("hasn't granted check-in access"),
          findsOneWidget);
    });

    testWidgets('consent denied with disclaimer shows the disclaimer',
        (tester) async {
      final client = MockClient((req) async => http.Response(
          jsonEncode({'consentGranted': false, 'disclaimer': 'Ask first.'}),
          200));
      await http.runWithClient(() async {
        await pumpStmlPage(tester, const StmlCheckInPage(patientId: 3),
            provider: _caregiver());
        await settle(tester);
      }, () => client);
      expect(find.textContaining('Ask first.'), findsOneWidget);
    });

    testWidgets('empty check-in shows nothing-to-prepare', (tester) async {
      final client = MockClient((req) async =>
          http.Response(jsonEncode({'consentGranted': true}), 200));
      await http.runWithClient(() async {
        await pumpStmlPage(tester, const StmlCheckInPage(patientId: 3),
            provider: _caregiver());
        await settle(tester);
      }, () => client);
      expect(find.text('Nothing to prepare for right now.'), findsOneWidget);
    });

    testWidgets('error state retries', (tester) async {
      var calls = 0;
      final client = MockClient((req) async {
        calls++;
        // Delay so the retried future is subscribed before it fails.
        await Future<void>.delayed(const Duration(milliseconds: 50));
        throw Exception('offline');
      });
      await http.runWithClient(() async {
        await pumpStmlPage(tester, const StmlCheckInPage(patientId: 3),
            provider: _caregiver());
        await settle(tester);
        expect(find.textContaining('Could not reach the server'),
            findsOneWidget);
        await tester.tap(find.text('Try again'));
        await settle(tester);
      }, () => client);
      expect(calls, 2);
    });
  });

  group('StmlCheckInPatientSelectionPage', () {
    void install(MockClient c) {
      ApiService.debugSetHttpClient(c);
      addTearDown(ApiService.debugResetHttpClient);
    }

    testWidgets('lists patients and opens the check-in route',
        (tester) async {
      ignoreListTileInk();
      install(MockClient((req) async => http.Response(
          jsonEncode([
            {
              'patient': {'id': 11, 'firstName': 'Ana', 'lastName': 'Diaz'}
            },
            {'id': 12, 'firstName': 'Ben', 'lastName': 'Ode'},
            'garbage',
          ]),
          200)));
      await pumpStmlPage(tester, const StmlCheckInPatientSelectionPage(),
          provider: _caregiver());
      await settle(tester);
      expect(find.text('Select a patient'), findsOneWidget);
      expect(find.text('Ana Diaz'), findsOneWidget);
      expect(find.text('Ben Ode'), findsOneWidget);
      await tester.tap(find.text('Ana Diaz'));
      await settle(tester);
      expect(find.text('route:/stml/checkin/11'), findsOneWidget);
    });

    testWidgets('empty list shows the no-patients message', (tester) async {
      install(MockClient((req) async => http.Response('[]', 200)));
      await pumpStmlPage(tester, const StmlCheckInPatientSelectionPage(),
          provider: _caregiver());
      await settle(tester);
      expect(find.textContaining("don't have any patients"), findsOneWidget);
    });

    testWidgets('error shows retry', (tester) async {
      var calls = 0;
      install(MockClient((req) async {
        calls++;
        return http.Response('', 500);
      }));
      await pumpStmlPage(tester, const StmlCheckInPatientSelectionPage(),
          provider: _caregiver());
      await settle(tester);
      expect(find.textContaining('Failed to load patients: 500'),
          findsOneWidget);
      await tester.tap(find.text('Try again'));
      await settle(tester);
      expect(calls, 2);
    });
  });
}
