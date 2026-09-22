// Emission coverage for the seven feature.medications.* telemetry events.
//
// Scope: issue #5 (Unimplemented Medication Telemetry Events) / PR #96,
// WBS 2.4.3. Issue #5 requires that every feature.medications.* name in the
// client whitelist either have a real emission site or be removed from the
// whitelist. Backend TC-TEL-05 already asserts each name is persisted when
// emitted and TC-TEL-21 guards the two allowlists against drift; neither
// asserts that the application actually fires the event. These cases do.
//
// Test IDs are permanent (Software Test Plan section 2.9.1) -- never
// renumbered, never reused. Plan section 3.4.5, Tables 3.4-12 and 3.4-13.
//
// Harness follows feature_use_events_test.dart:
//   - SharedPreferences mock drives the local opt-out gate
//   - flutter_secure_storage MethodChannel mock satisfies AuthTokenManager
//   - ApiService.debugSetHttpClient + http.runWithClient capture telemetry POSTs

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/features/dashboard/patient_dashboard/services/patient_medication_reminder_service.dart';
import 'package:care_connect_app/features/health/caregiver-patient-list/widgets/current_medications_card.dart';
import 'package:care_connect_app/features/health/medication-tracker/models/medication-model.dart';
import 'package:care_connect_app/features/health/medication-tracker/widgets/medication-add-input-form.dart';
import 'package:care_connect_app/features/health/medication-tracker/widgets/medication-card.dart';
import 'package:care_connect_app/features/telemetry/telemetry.dart';
import 'package:care_connect_app/features/telemetry/telemetry_guardrails.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';

import '../../mock_user_provider.dart';

// ---------------------------------------------------------------------------
// The seven names under test.
// ---------------------------------------------------------------------------
const List<String> kMedicationEvents = <String>[
  'feature.medications.view_all',
  'feature.medications.view_active',
  'feature.medications.view_pending',
  'feature.medications.add',
  'feature.medications.approve',
  'feature.medications.delete_soft',
  'feature.medications.delete_hard',
];

/// Captures every telemetry POST body emitted while [body] runs.
///
/// [respond] answers all non-telemetry requests, so each case controls the
/// status code the production code under test observes.
/// [drainEventLoop] must stay false under [testWidgets]: that binding runs on a
/// fake clock, so a real `Future.delayed` there never completes. Widget cases
/// drain through `tester.pump(Duration)` instead.
Future<List<Map<String, dynamic>>> _captureEvents(
  Future<void> Function() body, {
  required Future<http.Response> Function(http.Request req) respond,
  bool drainEventLoop = true,
}) async {
  final bodies = <String>[];

  final mock = MockClient((req) async {
    final isTelemetryPath = req.url.path.contains('telemetry');
    final isToggle = isTelemetryPath && req.url.path.contains('enabled');

    if (isTelemetryPath && !isToggle && req.method == 'POST') {
      bodies.add(req.body);
      return http.Response('', 204);
    }
    if (isToggle) {
      return http.Response(jsonEncode({'enabled': true}), 200);
    }
    return respond(req);
  });

  ApiService.debugSetHttpClient(mock);
  try {
    await http.runWithClient(() async {
      await Telemetry.setBackendEnabled(true);
      await body();
      // Every emission site is fire-and-forget (unawaited), so the telemetry
      // POST can still be in flight when the code under test returns. Drain
      // the event loop until no new body has arrived for several turns;
      // without this the mock client is torn down first and the request
      // escapes to the real HttpClient.
      if (drainEventLoop) {
        var idle = 0;
        var seen = bodies.length;
        for (var turn = 0; turn < 200 && idle < 8; turn++) {
          await Future<void>.delayed(const Duration(milliseconds: 2));
          if (bodies.length == seen) {
            idle++;
          } else {
            seen = bodies.length;
            idle = 0;
          }
        }
      }
    }, () => mock);
  } finally {
    ApiService.debugResetHttpClient();
  }

  return bodies
      .map((b) => jsonDecode(b) as Map<String, dynamic>)
      .toList(growable: false);
}

Iterable<Map<String, dynamic>> _named(
  List<Map<String, dynamic>> events,
  String name,
) =>
    events.where((e) => e['eventName'] == name);

Map<String, dynamic> _details(Map<String, dynamic> event) =>
    (event['details'] as Map).cast<String, dynamic>();

/// Pumps [child], captures telemetry, and optionally interacts afterwards.
Future<List<Map<String, dynamic>>> _pumpAndCapture(
  WidgetTester tester,
  Widget child, {
  required Future<http.Response> Function(http.Request req) respond,
  Future<void> Function()? interact,
}) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  return _captureEvents(
    () async {
      await tester.pumpWidget(child);
      await tester.pump();
      if (interact != null) {
        await interact();
      }
      await tester.pump(const Duration(milliseconds: 200));
    },
    respond: respond,
    drainEventLoop: false,
  );
}

Medication _med({
  int id = 11,
  int patientId = 1,
  String name = 'Aspirin',
  bool isActive = true,
  MedicationType type = MedicationType.OTC,
}) =>
    Medication(
      id: id,
      patientId: patientId,
      medicationName: name,
      dosage: '100mg',
      frequency: 'Once daily',
      route: 'Oral',
      isActive: isActive,
      medicationType: type,
    );

Widget _wrap(Widget child, {UserProvider? provider}) {
  final inner = MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
  if (provider == null) return inner;
  return ChangeNotifierProvider<UserProvider>.value(
    value: provider,
    child: inner,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final secureStore = <String, String>{};

  void installSecureStorageMock() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async {
      final args = (call.arguments as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{};
      final key = args['key'] as String?;

      if (call.method == 'write' && key != null) {
        secureStore[key] = args['value']?.toString() ?? '';
        return null;
      }
      if (call.method == 'delete' && key != null) {
        secureStore.remove(key);
        return null;
      }
      if (call.method == 'read' && key == 'jwt_token') return 'test-jwt-token';
      if (call.method == 'read' && key == 'token_expiry') {
        final exp = DateTime.now().add(const Duration(days: 1));
        return '${exp.millisecondsSinceEpoch ~/ 1000}';
      }
      if (call.method == 'read' && key != null) return secureStore[key];
      return null;
    });
  }

  setUp(() {
    secureStore.clear();
    SharedPreferences.setMockInitialValues(<String, Object>{
      'telemetry_opted_out': false,
    });
    installSecureStorageMock();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
  });

  // -------------------------------------------------------------------------
  // TC-TEL-MED-001 -- whitelist precondition
  // -------------------------------------------------------------------------
  group('TC-TEL-MED-001  whitelist precondition', () {
    test('all seven feature.medications.* names are allowlisted client-side',
        () {
      for (final name in kMedicationEvents) {
        expect(
          TelemetryGuardrails.allowedEvents.contains(name),
          isTrue,
          reason: '$name is not in TelemetryGuardrails.allowedEvents',
        );
      }
    });

    test('the client whitelist holds exactly these seven medication names', () {
      final inWhitelist = TelemetryGuardrails.allowedEvents
          .where((e) => e.startsWith('feature.medications.'))
          .toSet();
      expect(inWhitelist, kMedicationEvents.toSet());
    });
  });

  // -------------------------------------------------------------------------
  // TC-TEL-MED-002 / 003 / 004 -- view_all from the patient dashboard service
  // -------------------------------------------------------------------------
  group('TC-TEL-MED-002/003/004  view_all -- PatientMedicationReminderService',
      () {
    Future<AppLocalizations> localizations() =>
        AppLocalizations.delegate.load(const Locale('en'));

    test(
        'TC-TEL-MED-002  a successful medication load emits view_all with '
        'statusCode 200', () async {
      final t = await localizations();
      final service = PatientMedicationReminderService();

      final events = await _captureEvents(
        () => service.loadReminders(patientId: 1, t: t),
        respond: (req) async => http.Response(
          jsonEncode(<Map<String, dynamic>>[
            {
              'id': 11,
              'medicationName': 'Aspirin',
              'dosage': '100mg',
              'frequency': 'Once daily',
              'isActive': true,
            },
          ]),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );

      final viewAll = _named(events, 'feature.medications.view_all').toList();
      expect(viewAll, hasLength(1));
      expect(_details(viewAll.single)['statusCode'], 200);
    });

    test(
        'TC-TEL-MED-003  a failed medication load still emits view_all and '
        'carries the failure statusCode', () async {
      final t = await localizations();
      final service = PatientMedicationReminderService();

      final events = await _captureEvents(
        () => service.loadReminders(patientId: 1, t: t),
        respond: (req) async =>
            http.Response(jsonEncode({'error': 'boom'}), 500),
      );

      final viewAll = _named(events, 'feature.medications.view_all').toList();
      expect(viewAll, hasLength(1));
      expect(_details(viewAll.single)['statusCode'], 500);
    });

    test(
        'TC-TEL-MED-004  a null patientId short-circuits before the fetch and '
        'emits no medication event', () async {
      final t = await localizations();
      final service = PatientMedicationReminderService();

      final events = await _captureEvents(
        () => service.loadReminders(patientId: null, t: t),
        respond: (req) async => http.Response('[]', 200),
      );

      expect(
        events.where(
          (e) => (e['eventName'] as String).startsWith('feature.medications.'),
        ),
        isEmpty,
      );
    });
  });

  // -------------------------------------------------------------------------
  // TC-TEL-MED-005 / 013 -- view_active from CurrentMedicationsSection
  // -------------------------------------------------------------------------
  group('TC-TEL-MED-005/013  view_active -- CurrentMedicationsSection', () {
    testWidgets(
        'TC-TEL-MED-005  rendering the caregiver medications section emits '
        'view_active', (tester) async {
      final events = await _pumpAndCapture(
        tester,
        _wrap(CurrentMedicationsSection(entries: [_med()], caregiverId: 7)),
        respond: (req) async => http.Response('{}', 200),
      );

      expect(_named(events, 'feature.medications.view_active'), isNotEmpty);
    });

    testWidgets(
        'TC-TEL-MED-013  a rebuild that changes no medication data does not '
        'emit a second view_active', (tester) async {
      late StateSetter setOuter;
      var pad = 0.0;

      final harness = StatefulBuilder(
        builder: (context, setState) {
          setOuter = setState;
          return Padding(
            padding: EdgeInsets.only(top: pad),
            child: CurrentMedicationsSection(
              entries: [_med()],
              caregiverId: 7,
            ),
          );
        },
      );

      final events = await _pumpAndCapture(
        tester,
        _wrap(harness),
        respond: (req) async => http.Response('{}', 200),
        interact: () async {
          // Same medication data, three more layout-only rebuilds.
          for (var i = 0; i < 3; i++) {
            setOuter(() => pad = pad + 1.0);
            await tester.pump();
          }
          await tester.pump(const Duration(milliseconds: 200));
        },
      );

      expect(
        _named(events, 'feature.medications.view_active').length,
        1,
        reason: 'view_active is emitted from build(), so every rebuild sends '
            'another event and the analytics count no longer reflects views',
      );
    });

    testWidgets(
        'TC-TEL-MED-014  one render of a three-medication section emits one '
        'view_active and no per-card view_all', (tester) async {
      final events = await _pumpAndCapture(
        tester,
        _wrap(CurrentMedicationsSection(
          entries: [
            _med(id: 11, name: 'Aspirin'),
            _med(id: 12, name: 'Lisinopril'),
            _med(id: 13, name: 'Metformin'),
          ],
          caregiverId: 7,
        )),
        respond: (req) async => http.Response('{}', 200),
      );

      expect(
        _named(events, 'feature.medications.view_active').length,
        1,
        reason: 'one section rendered once is one view',
      );
      expect(
        _named(events, 'feature.medications.view_all'),
        isEmpty,
        reason: 'view_all names a list fetch; _MedicationBlock.build emits it '
            'once per card, so the name now covers two unrelated actions and '
            'the count scales with list length',
      );
    });
  });

  // -------------------------------------------------------------------------
  // TC-TEL-MED-006 / 007 / 008 -- approve and delete_hard (caregiver)
  // -------------------------------------------------------------------------
  group('TC-TEL-MED-006/007/008  approve and delete_hard -- caregiver actions',
      () {
    testWidgets(
        'TC-TEL-MED-006  approving a pending medication emits approve with '
        'statusCode 200', (tester) async {
      final events = await _pumpAndCapture(
        tester,
        _wrap(CurrentMedicationsSection(
          entries: [_med(isActive: false)],
          caregiverId: 7,
        )),
        respond: (req) async => http.Response(jsonEncode({'ok': true}), 200),
        interact: () async {
          await tester.tap(find.text('Approve'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));
        },
      );

      final approve = _named(events, 'feature.medications.approve').toList();
      expect(approve, hasLength(1));
      expect(_details(approve.single)['statusCode'], 200);
    });

    testWidgets(
        'TC-TEL-MED-007  confirming a caregiver hard delete emits delete_hard '
        'with statusCode 200', (tester) async {
      final events = await _pumpAndCapture(
        tester,
        _wrap(CurrentMedicationsSection(
          entries: [_med()],
          caregiverId: 7,
        )),
        respond: (req) async => http.Response(jsonEncode({'ok': true}), 200),
        interact: () async {
          await tester.tap(find.text('Delete'));
          await tester.pumpAndSettle();
          // Confirm in the AlertDialog.
          await tester.tap(find.widgetWithText(TextButton, 'Delete'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));
        },
      );

      final hard = _named(events, 'feature.medications.delete_hard').toList();
      expect(hard, hasLength(1));
      expect(_details(hard.single)['statusCode'], 200);
    });

    testWidgets(
        'TC-TEL-MED-008  a hard delete refused by the backend still emits '
        'delete_hard, carrying 403', (tester) async {
      final events = await _pumpAndCapture(
        tester,
        _wrap(CurrentMedicationsSection(
          entries: [_med()],
          caregiverId: 7,
        )),
        respond: (req) async =>
            http.Response(jsonEncode({'message': 'forbidden'}), 403),
        interact: () async {
          await tester.tap(find.text('Delete'));
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(TextButton, 'Delete'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));
        },
      );

      final hard = _named(events, 'feature.medications.delete_hard').toList();
      expect(hard, hasLength(1));
      expect(_details(hard.single)['statusCode'], 403);
    });
  });

  // -------------------------------------------------------------------------
  // TC-TEL-MED-009 -- add
  // -------------------------------------------------------------------------
  group('TC-TEL-MED-009  add -- AddMedicationModal', () {
    testWidgets(
        'TC-TEL-MED-009  submitting the add-medication form emits add with '
        'statusCode 200', (tester) async {
      final provider = MockUserProvider(
        mockUser: MockUser(id: 1, role: 'PATIENT', patientId: 1),
      );

      final events = await _pumpAndCapture(
        tester,
        _wrap(
          AddMedicationModal(onMedicationAdded: (_) {}),
          provider: provider,
        ),
        respond: (req) async => http.Response(
          jsonEncode({
            'id': 11,
            'medicationName': 'Aspirin',
            'dosage': '100mg',
            'frequency': 'Once daily',
            'route': 'Oral',
            'isActive': true,
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
        interact: () async {
          // Only name and dosage are required free-text fields; frequency,
          // route and type all carry defaults.
          await tester.enterText(find.byType(TextFormField).at(0), 'Aspirin');
          await tester.enterText(find.byType(TextFormField).at(1), '100mg');
          await tester.pump();

          final submit = find.text('Add Medication');
          await tester.ensureVisible(submit.last);
          await tester.pump();
          await tester.tap(submit.last, warnIfMissed: false);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
        },
      );

      final add = _named(events, 'feature.medications.add').toList();
      expect(add, hasLength(1));
      expect(_details(add.single)['statusCode'], 200);
    });
  });

  // -------------------------------------------------------------------------
  // TC-TEL-MED-010 -- delete_soft
  // -------------------------------------------------------------------------
  group('TC-TEL-MED-010  delete_soft -- MedicationCard', () {
    testWidgets(
        'TC-TEL-MED-010  a patient soft-remove emits delete_soft carrying a '
        'numeric statusCode', (tester) async {
      final provider = MockUserProvider(
        mockUser: MockUser(id: 1, role: 'PATIENT', patientId: 1),
      );

      final events = await _pumpAndCapture(
        tester,
        _wrap(
          MedicationCard(
            medication: _med(),
            onStatusChanged: (_) {},
          ),
          provider: provider,
        ),
        respond: (req) async => http.Response('', 204),
        interact: () async {
          await tester.tap(find.byIcon(Icons.delete_outline));
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(TextButton, 'Remove'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));
        },
      );

      final soft = _named(events, 'feature.medications.delete_soft').toList();
      expect(soft, hasLength(1));
      expect(
        _details(soft.single)['statusCode'],
        204,
        reason: 'the emission site passes the whole http.Response instead of '
            'response.statusCode, and TelemetryGuardrails.sanitize drops any '
            'non-primitive value, so details arrives empty',
      );
    });
  });

  // -------------------------------------------------------------------------
  // TC-TEL-MED-011 -- every allowlisted name must have an emission site
  // -------------------------------------------------------------------------
  group('TC-TEL-MED-011  view_pending emission site', () {
    test(
        'TC-TEL-MED-011  every allowlisted medication event name has at least '
        'one emission site under lib/', () {
      final libDir = Directory('lib');
      if (!libDir.existsSync()) {
        // Skip rather than fail -- matches the skip semantics of TC-TEL-21,
        // which reads a sibling source tree it cannot guarantee is present.
        markTestSkipped('lib/ not reachable from the test working directory');
        return;
      }

      const guardrailsSuffix = 'features/telemetry/telemetry_guardrails.dart';

      final sources = libDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          // The guardrails whitelist itself is a declaration, not a call site.
          .where((f) =>
              !f.path.replaceAll(r'\', '/').endsWith(guardrailsSuffix))
          .map((f) => f.readAsStringSync())
          .toList(growable: false);

      final orphans = <String>[];
      for (final name in kMedicationEvents) {
        final emitted = sources.any(
          (s) => s.contains("'$name'") || s.contains('"$name"'),
        );
        if (!emitted) orphans.add(name);
      }

      expect(
        orphans,
        isEmpty,
        reason: 'issue #5 requires each allowlisted feature.medications.* name '
            'to be emitted or removed from the whitelist; these names are '
            'still whitelisted with no emission site',
      );
    });
  });

  // -------------------------------------------------------------------------
  // TC-TEL-MED-012 -- privacy: opt-out suppresses medication telemetry
  // -------------------------------------------------------------------------
  group('TC-TEL-MED-012  opt-out suppression', () {
    testWidgets(
        'TC-TEL-MED-012  with telemetry opted out, a caregiver hard delete '
        'sends no telemetry request', (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'telemetry_opted_out': true,
      });

      final events = await _pumpAndCapture(
        tester,
        _wrap(CurrentMedicationsSection(
          entries: [_med()],
          caregiverId: 7,
        )),
        respond: (req) async => http.Response(jsonEncode({'ok': true}), 200),
        interact: () async {
          await tester.tap(find.text('Delete'));
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(TextButton, 'Delete'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));
        },
      );

      expect(events, isEmpty);
    });
  });
}
