// More happy-path tests for the older PatientDashboard
// (lib/features/dashboard/presentation/pages/patient_dashboard.dart), with
// both the zone client and ApiService's client faked: mood and pain auto-save
// outcomes, family members load and add, and the per-caregiver Ask AI consent
// switch (load, grant, revoke, failure).
import 'dart:convert';

import 'package:care_connect_app/features/dashboard/presentation/pages/patient_dashboard.dart';
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

import '../../mock_user_provider.dart';

class _Backend {
  int moodStatus = 200;
  Map<String, String> moodHeaders = const {};
  int familyStatus = 200;
  int addStatus = 201;
  int consentStatus = 200;
  bool consentWriteFails = false;
  List<dynamic> family = [
    {
      'firstName': 'Fran',
      'lastName': 'Member',
      'relationship': 'Sister',
      'phone': '555',
      'email': 'f@example.com',
    },
  ];
  int patientCalls = 0;
  final requests = <http.Request>[];

  Future<http.Response> handle(http.Request r) async {
    requests.add(r);
    final path = r.url.path;
    if (path.endsWith('/caregivers') &&
        path.contains('caregiver-patient-links')) {
      return http.Response(
          jsonEncode([
            {'caregiverEmail': 'Email@Example.com', 'caregiverUserId': '303'},
            {'caregiverEmail': '', 'caregiverUserId': 1},
          ]),
          200);
    }
    if (path.endsWith('/patients/1/caregivers')) {
      return http.Response(
          jsonEncode([
            {'id': 10, 'firstName': 'Direct', 'userId': 101, 'phone': '1'},
            {'id': 11, 'firstName': 'Stringy', 'userId': '102'},
            {
              'id': 12,
              'firstName': 'Nested',
              'user': {'id': '104'},
            },
            {
              'id': 13,
              'firstName': 'NestedInt',
              'user': {'id': 105},
            },
            {'id': 14, 'firstName': 'ByEmail', 'email': 'email@example.com'},
            {'id': 15, 'firstName': 'Nobody'},
          ]),
          200);
    }
    if (path.endsWith('/ai-retrieval')) {
      if (r.method == 'GET') {
        final grantee = r.url.queryParameters['granteeUserId'];
        if (grantee == '102') return http.Response('oops', consentStatus);
        if (grantee == '104') {
          return http.Response(jsonEncode({'effectiveConsent': true}), 200);
        }
        return http.Response(jsonEncode({'granted': grantee == '101'}), 200);
      }
      if (consentWriteFails) return http.Response('no', 500);
      return http.Response(jsonEncode({'ok': true}), 200);
    }
    if (path.endsWith('/mood-pain-log')) {
      return http.Response(jsonEncode({'error': 'bad mood'}), moodStatus,
          headers: moodHeaders);
    }
    if (path.endsWith('/patients/1/family-members') && r.method == 'POST') {
      return http.Response(jsonEncode({'message': 'dup member'}), addStatus);
    }
    if (RegExp(r'/patients/1$').hasMatch(path)) {
      patientCalls++;
      // The page reads this URL first for the patient, then for family.
      if (patientCalls == 1) {
        return http.Response(
            jsonEncode({'id': 1, 'firstName': 'Pat', 'lastName': 'Doe'}),
            200);
      }
      return http.Response(jsonEncode(family), familyStatus);
    }
    return http.Response('{}', 200);
  }
}

late _Backend _b;

void main() {
  late MockClient client;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        if (call.method == 'readAll') return <String, String>{};
        if (call.method == 'containsKey') return false;
        return null;
      },
    );
    m.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => call.method == 'check' ? ['wifi'] : null,
    );
    _b = _Backend();
    client = MockClient((r) => _b.handle(r));
    ApiService.debugSetHttpClient(client);
  });

  tearDown(ApiService.debugResetHttpClient);

  Future<void> frames(WidgetTester t, [int n = 15]) async {
    for (var i = 0; i < n; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpDash(WidgetTester t) async {
    t.view.physicalSize = const Size(1000, 5000);
    t.view.devicePixelRatio = 1;
    final orig = FlutterError.onError;
    FlutterError.onError = (d) {
      if (d.exceptionAsString().contains('overflow')) return;
      orig?.call(d);
    };
    addTearDown(() {
      FlutterError.onError = orig;
      t.view.reset();
    });
    await t.pumpWidget(ChangeNotifierProvider<UserProvider>.value(
      value: MockUserProvider(
          mockUser: MockUser(id: 1, role: 'PATIENT', patientId: 1, name: 'Pat')),
      child: const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: PatientDashboard(),
      ),
    ));
    await frames(t, 20);
  }

  Future<void> run(WidgetTester t, Future<void> Function() body) =>
      http.runWithClient(body, () => client);

  Future<void> pickMoodAndPain(WidgetTester t) async {
    await t.ensureVisible(find.text('Happy'));
    await t.pump();
    await t.tap(find.text('Happy'));
    await t.pump();
    await t.ensureVisible(find.textContaining('Moderate').first);
    await t.tap(find.textContaining('Moderate').first);
    await frames(t, 5);
  }

  testWidgets('mood and pain save automatically', (t) async {
    await run(t, () async {
      await pumpDash(t);
      await pickMoodAndPain(t);
      expect(find.text('Status saved automatically'), findsOneWidget);
      final log = _b.requests.lastWhere((r) => r.url.path.endsWith('/mood-pain-log'));
      final body = jsonDecode(log.body) as Map<String, dynamic>;
      expect(body['moodValue'], 6);
      expect(body['painValue'], 4);
    });
  });

  testWidgets('an offline-queued save says it will sync', (t) async {
    await run(t, () async {
      _b.moodStatus = 201;
      _b.moodHeaders = {'x-offline-queued': 'true'};
      await pumpDash(t);
      await pickMoodAndPain(t);
      expect(find.text('Status queued for sync when internet is restored'),
          findsOneWidget);
    });
  });

  testWidgets('a rejected save shows the error', (t) async {
    await run(t, () async {
      _b.moodStatus = 400;
      await pumpDash(t);
      for (final mood in ['Angry', 'Sad', 'Tired', 'Fearful', 'Neutral']) {
        await t.ensureVisible(find.text(mood));
        await t.pump();
        await t.tap(find.text(mood));
        await t.pump();
      }
      await t.ensureVisible(find.textContaining('No Pain').first);
      await t.tap(find.textContaining('No Pain').first);
      await frames(t, 5);
      expect(find.textContaining('bad mood'), findsWidgets);
    });
  });

  testWidgets('family members are listed', (t) async {
    await run(t, () async {
      await pumpDash(t);
      expect(find.textContaining('Fran'), findsWidgets);
    });
  });

  testWidgets('adding a family member saves and reloads', (t) async {
    await run(t, () async {
      await pumpDash(t);
      await t.ensureVisible(find.text('Add Family Member').first);
      await t.tap(find.text('Add Family Member').first);
      await t.pumpAndSettle();
      final fields = find.descendant(
          of: find.byType(Dialog), matching: find.byType(TextFormField));
      await t.enterText(fields.at(0), 'New');
      await t.enterText(fields.at(1), 'Person');
      await t.enterText(fields.at(2), 'Cousin');
      await t.enterText(fields.at(3), '555-0000');
      await t.enterText(fields.at(4), 'new@example.com');
      await t.tap(find.descendant(
          of: find.byType(Dialog), matching: find.text('Add')));
      // The "Adding family member..." snack bar shows first.
      await frames(t, 30);
      expect(find.text('Family member added successfully!'), findsOneWidget);
    });
  });

  testWidgets('a rejected family member add shows the message', (t) async {
    await run(t, () async {
      _b.addStatus = 409;
      await pumpDash(t);
      await t.ensureVisible(find.text('Add Family Member').first);
      await t.tap(find.text('Add Family Member').first);
      await t.pumpAndSettle();
      final fields = find.descendant(
          of: find.byType(Dialog), matching: find.byType(TextFormField));
      for (var i = 0; i < 4; i++) {
        await t.enterText(fields.at(i), 'x$i');
      }
      await t.enterText(fields.at(4), 'x@example.com');
      await t.tap(find.descendant(
          of: find.byType(Dialog), matching: find.text('Add')));
      // The "Adding family member..." snack bar shows first.
      await frames(t, 30);
      expect(find.textContaining('dup member'), findsOneWidget);
    });
  });

  testWidgets('a failed family member load is reported', (t) async {
    await run(t, () async {
      _b.familyStatus = 500;
      await pumpDash(t);
      expect(find.textContaining('Failed to load family members'),
          findsWidgets);
    });
  });

  testWidgets('consent switches load, grant and revoke', (t) async {
    await run(t, () async {
      await pumpDash(t);
      final switches = find.byType(SwitchListTile);
      expect(switches, findsNWidgets(5));
      expect(
          t.widget<SwitchListTile>(
              find.byKey(const ValueKey('ask-ai-consent-101'))).value,
          isTrue);
      expect(
          t.widget<SwitchListTile>(
              find.byKey(const ValueKey('ask-ai-consent-104'))).value,
          isTrue);

      await t.ensureVisible(find.byKey(const ValueKey('ask-ai-consent-101')));
      await t.tap(find.byKey(const ValueKey('ask-ai-consent-101')));
      await frames(t, 5);
      expect(
          _b.requests.any(
              (r) => r.method == 'DELETE' && r.url.path.endsWith('/ai-retrieval')),
          isTrue);

      await t.ensureVisible(find.byKey(const ValueKey('ask-ai-consent-105')));
      await t.tap(find.byKey(const ValueKey('ask-ai-consent-105')));
      await frames(t, 5);
      expect(
          _b.requests.any(
              (r) => r.method == 'POST' && r.url.path.endsWith('/ai-retrieval')),
          isTrue);
    });
  });

  testWidgets('a failed consent change is reverted and reported', (t) async {
    await run(t, () async {
      _b.consentWriteFails = true;
      await pumpDash(t);
      await t.ensureVisible(find.byKey(const ValueKey('ask-ai-consent-303')));
      await t.tap(find.byKey(const ValueKey('ask-ai-consent-303')));
      await frames(t, 5);
      expect(find.text('Could not grant Ask AI access. Please try again.'),
          findsOneWidget);
      await t.pump(const Duration(seconds: 5));
      await t.ensureVisible(find.byKey(const ValueKey('ask-ai-consent-101')));
      await t.tap(find.byKey(const ValueKey('ask-ai-consent-101')));
      await frames(t, 5);
      expect(find.text('Could not revoke Ask AI access. Please try again.'),
          findsOneWidget);
    });
  });
}
