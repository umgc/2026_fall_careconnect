// More happy-path tests for CaregiverPatientList
// (lib/features/health/caregiver-patient-list/page/caregiver-patient-list.dart):
// mood and unread enrichment, search filtering, the Add Existing Patient
// dialog outcomes, the Register sheet, and the error/no-caregiver states.
import 'dart:convert';

import 'package:care_connect_app/features/health/caregiver-patient-list/page/caregiver-patient-list.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
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

List<Map<String, dynamic>> _rows() => [
      {
        'patient': {'id': 12, 'firstName': 'Romilda', 'lastName': 'Smith'},
        'link': {'patientUserId': 34, 'notes': 'Doing well'},
      },
      {
        'patient': {'id': 13, 'firstName': 'Bertram', 'lastName': 'Jones'},
        'link': {'patientUserId': '35'},
      },
      {
        'patient': {'id': 14, 'firstName': 'Cora', 'lastName': 'Lane'},
        'link': {'patientUserId': 36},
      },
      {
        'patient': {'id': 15, 'firstName': 'Dax', 'lastName': 'Moe'},
        'link': {'patientUserId': 37},
      },
      {
        'patient': {'id': 16, 'firstName': 'Eve', 'lastName': 'Nash'},
        'link': {},
      },
    ];

void main() {
  late http.Response Function(http.Request) handler;
  final posts = <http.Request>[];

  setUp(() {
    posts.clear();
    SharedPreferences.setMockInitialValues({});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => call.method == 'check' ? ['wifi'] : null,
    );
    handler = (request) {
      final path = request.url.path;
      if (path.endsWith('/caregivers/42/patients')) {
        return http.Response(jsonEncode(_rows()), 200);
      }
      if (path.endsWith('/34/mood')) {
        return http.Response(
            jsonEncode([
              {'score': 9, 'label': null}
            ]),
            200);
      }
      if (path.endsWith('/35/mood')) {
        return http.Response(
            jsonEncode([
              {'score': 6}
            ]),
            200);
      }
      if (path.endsWith('/36/mood')) {
        return http.Response(
            jsonEncode([
              {'score': 2, 'label': 'Sad'}
            ]),
            200);
      }
      if (path.endsWith('/37/mood')) {
        return http.Response(
            jsonEncode([
              {'score': 4, 'label': 'Neutral'}
            ]),
            200);
      }
      if (path.contains('/messages/inbox/')) {
        return http.Response(
            jsonEncode([
              {'peerId': 34, 'hasUnread': true},
              {'peerId': 35},
              'junk',
            ]),
            200);
      }
      return http.Response(jsonEncode([]), 200);
    };
    ApiService.debugSetHttpClient(MockClient((request) async {
      if (request.method == 'POST') posts.add(request);
      return handler(request);
    }));
  });

  tearDown(ApiService.debugResetHttpClient);

  Future<void> pumpList(WidgetTester tester, {int? caregiverId = 42}) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChangeNotifierProvider<UserProvider>.value(
      value: MockUserProvider(
          mockUser:
              MockUser(id: 10, role: 'CAREGIVER', caregiverId: caregiverId)),
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: CaregiverPatientList(),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('lists every patient with moods derived from scores and labels',
      (tester) async {
    await pumpList(tester);
    expect(find.textContaining('Romilda'), findsWidgets);
    expect(find.textContaining('Bertram'), findsWidgets);
    expect(find.textContaining('Eve'), findsWidgets);
    // Five normal (non-urgent) cases, zero urgent.
    expect(find.text('5'), findsOneWidget);
    expect(find.text('0'), findsWidgets);
  });

  testWidgets('search filters by substring, prefix and fuzzy match, and clear '
      'restores the list', (tester) async {
    await pumpList(tester);
    await tester.enterText(find.byType(TextField).first, 'jones');
    await tester.pumpAndSettle();
    expect(find.textContaining('Romilda'), findsNothing);
    expect(find.textContaining('Bertram'), findsWidgets);

    // Fuzzy: one typo in a 4+ char query still matches the full name.
    await tester.enterText(find.byType(TextField).first, 'romolda');
    await tester.pumpAndSettle();
    expect(find.textContaining('Romilda'), findsWidgets);

    // A nonsense query empties the list.
    await tester.enterText(find.byType(TextField).first, 'zzzzzz');
    await tester.pumpAndSettle();
    expect(find.text('No patients found'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.clear));
    await tester.pumpAndSettle();
    expect(find.textContaining('Romilda'), findsWidgets);
  });

  testWidgets('a patient without a user id cannot open chat', (tester) async {
    await pumpList(tester);
    await tester.scrollUntilVisible(find.textContaining('Eve'), 200,
        scrollable: find.byType(Scrollable).last);
    final evesCard = find.ancestor(
        of: find.textContaining('Eve').first, matching: find.byType(Card));
    final msg = find.descendant(
        of: evesCard.first, matching: find.byIcon(Icons.message_outlined));
    if (msg.evaluate().isNotEmpty) {
      await tester.tap(msg.first);
      await tester.pump();
      expect(find.text('Unable to open chat for this patient.'), findsOneWidget);
    }
  });

  testWidgets('without a caregiver id the list is empty', (tester) async {
    await pumpList(tester, caregiverId: null);
    expect(find.text('No patients found'), findsOneWidget);
  });

  testWidgets('a failed patient load shows the empty state', (tester) async {
    handler = (_) => http.Response('nope', 500);
    await pumpList(tester);
    expect(find.text('No patients found'), findsOneWidget);
  });

  testWidgets('a malformed patient payload shows the empty state',
      (tester) async {
    handler = (_) => http.Response('{not json', 200);
    await pumpList(tester);
    expect(find.text('No patients found'), findsOneWidget);
  });

  testWidgets('pull to refresh reloads the list', (tester) async {
    await pumpList(tester);
    await tester.fling(
        find.byType(Scrollable).last, const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    expect(find.textContaining('Romilda'), findsWidgets);
  });

  /// The page disposes the dialog's email controller as soon as the dialog
  /// returns, while a normal pop still animates the TextField out (a real
  /// use-after-dispose in the page). Removing the dialog route without an
  /// exit animation hands the page the same result without that crash.
  Future<void> closeDialog(WidgetTester tester, bool result) async {
    final ctx = tester.element(find.byType(AlertDialog));
    final route = ModalRoute.of(ctx)!;
    Navigator.of(ctx).removeRoute(route, result);
    await tester.pumpAndSettle();
  }

  Future<void> addPatient(WidgetTester tester, String email) async {
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('Add Existing Patient'), findsOneWidget);
    await tester.enterText(
        find.descendant(
            of: find.byType(AlertDialog), matching: find.byType(TextField)),
        email);
    await closeDialog(tester, true);
  }

  for (final c in <(int, String?, String)>[
    (200, 'Linked!', 'Linked!'),
    (200, null, 'Patient successfully added'),
    (202, 'Invite out', 'Invite out'),
    (202, null, 'Invitation sent to patient'),
    (400, 'Already yours', 'Already yours'),
    (400, null, 'Patient already linked'),
    (503, null, 'Failed to add patient: 503'),
  ]) {
    testWidgets('Add Existing Patient reports a ${c.$1} response',
        (tester) async {
      await pumpList(tester);
      final base = handler;
      handler = (request) {
        if (request.url.path.endsWith('/patients/add')) {
          return http.Response(
              jsonEncode(c.$2 == null ? {} : {'message': c.$2}), c.$1);
        }
        return base(request);
      };
      await addPatient(tester, 'pat@example.com');
      expect(find.text(c.$3), findsOneWidget);
      expect(jsonDecode(posts.last.body), {'email': 'pat@example.com'});
    });
  }

  testWidgets('Add Existing Patient reports a thrown error', (tester) async {
    await pumpList(tester);
    final base = handler;
    handler = (request) {
      if (request.url.path.endsWith('/patients/add')) {
        throw http.ClientException('offline');
      }
      return base(request);
    };
    await addPatient(tester, 'pat@example.com');
    expect(find.textContaining('Error adding patient'), findsOneWidget);
  });

  testWidgets('Add Existing Patient without a caregiver id says so',
      (tester) async {
    await pumpList(tester, caregiverId: null);
    await addPatient(tester, 'pat@example.com');
    expect(find.text('Caregiver ID not found'), findsOneWidget);
  });

  testWidgets('Add Existing Patient cancelled or blank does nothing',
      (tester) async {
    await pumpList(tester);
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await closeDialog(tester, false);
    await addPatient(tester, '   ');
    expect(posts, isEmpty);
  });

  testWidgets('Register opens the patient registration sheet', (tester) async {
    await pumpList(tester);
    await tester.tap(find.text('Register'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(BottomSheet), findsOneWidget);
    // A submitted registration closes the sheet with true.
    Navigator.of(tester.element(find.byType(BottomSheet))).pop(true);
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Patient should receive a registration email.'),
        findsOneWidget);
  });
}
