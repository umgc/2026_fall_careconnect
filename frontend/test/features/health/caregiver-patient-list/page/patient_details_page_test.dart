// Tests for PatientDetailsPage
// (lib/features/health/caregiver-patient-list/page/patient_details_page.dart).
//
// Test IDs: TC-PDP-001…028 are the inherited tests (labels only, file order);
// TC-PDP-029 onward are the Testing Lead's (PR #364 review). TC-MCR-CG-016
// and 022 are the Medicare tab's. IDs are permanent: never renumber or reuse.

import 'dart:convert';

import 'package:care_connect_app/config/theme/app_theme.dart';
import 'package:care_connect_app/features/activities/presentation/pages/adl_iadl_management_screen.dart';
import 'package:care_connect_app/features/activities/presentation/pages/behavioral_incident_screens.dart';
import 'package:care_connect_app/features/audit/audit_log_screen.dart';
import 'package:care_connect_app/features/dashboards/dashboards_screen.dart';
import 'package:care_connect_app/features/evv/presentation/pages/incident_report_screens.dart';
import 'package:care_connect_app/features/health/caregiver-patient-list/page/incident_report_history_screen.dart';
import 'package:care_connect_app/features/health/caregiver-patient-list/page/patient_details_page.dart';
import 'package:care_connect_app/features/health/medication-tracker/models/medication-model.dart';
import 'package:care_connect_app/features/health/medication-tracker/widgets/medication-add-input-form.dart';
import 'package:care_connect_app/features/health/caregiver-patient-list/widgets/communication_history_card.dart';
import 'package:care_connect_app/features/health/caregiver-patient-list/widgets/emergency_contact_card.dart';
import 'package:care_connect_app/features/health/caregiver-patient-list/widgets/mood_history_card.dart';
import 'package:care_connect_app/features/health/caregiver-patient-list/widgets/pain_level_card.dart';
import 'package:care_connect_app/features/health/caregiver-patient-list/widgets/patient_header_card.dart';
import 'package:care_connect_app/features/health/caregiver-patient-list/widgets/recent_symptom_card.dart'
    as sympt;
import 'package:care_connect_app/features/health/symptom-tracker/widgets/symptom_card.dart';
import 'package:care_connect_app/features/health/symptom-tracker/widgets/symptom_tab.dart';
import 'package:care_connect_app/features/health/virtual_check_in/models/virtual_check_in.dart';
import 'package:care_connect_app/features/health/virtual_check_in/presentation/widgets/virtual_check_in_history_card.dart';
import 'package:care_connect_app/widgets/post_call_telemetry_summary_screen.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_client.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:dio/dio.dart' show HttpClientAdapter;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../mock_user_provider.dart';
import '../../health_data/health_data_test_support.dart';

late Future<http.Response> Function(http.Request) _httpHandler;

final MockClient _globalMockClient =
    MockClient((request) => _httpHandler(request));

Map<String, dynamic> _sarahProfilePayload() => {
      'id': 42,
      'firstName': 'Sarah',
      'lastName': 'Johnson',
      'email': 'sarah.johnson@email.com',
      'phone': '(555) 123-4567',
      'dob': '1980-05-15',
      'gender': 'Female',
      'mrn': 'MRN-2024-0156',
      'diagnoses': [
        'Type 2 Diabetes',
        'Hypertension',
        'Chronic Fatigue Syndrome',
      ],
      'allergies': [
        {'allergen': 'Penicillin', 'severity': 'Severe'},
        {'allergen': 'Shellfish', 'severity': 'Moderate'},
      ],
      'address': {
        'line1': '123 Main St',
        'city': 'Springfield',
        'state': 'IL',
        'zip': '62701',
      },
    };

List<Map<String, dynamic>> _sarahFamilyMembers() => [
      {
        'familyMemberName': 'Michael Johnson',
        'relationship': 'Spouse',
        'familyMemberPhone': '(555) 987-6543',
      },
    ];

void _setSarahHttpMocks() {
  _httpHandler = (request) async {
    final path = request.url.path;

    if (path.contains('/profile')) {
      return http.Response(jsonEncode(_sarahProfilePayload()), 200);
    }
    if (path.contains('/family-members')) {
      return http.Response(jsonEncode(_sarahFamilyMembers()), 200);
    }
    if (path.contains('/medications') || path.contains('/medication')) {
      return http.Response(jsonEncode([]), 200);
    }
    if (path.contains('/risk-types') || path.contains('/riskTypes')) {
      return http.Response(jsonEncode([]), 200);
    }
    if (path.contains('/risks')) {
      return http.Response(jsonEncode([]), 200);
    }
    if (path.contains('/mood') || path.contains('/mood-history')) {
      return http.Response(jsonEncode([]), 200);
    }
    if (path.contains('/symptom')) {
      return http.Response(jsonEncode([]), 200);
    }
    if (path.contains('/telemetry') || path.contains('/call')) {
      return http.Response(jsonEncode([]), 200);
    }
    if (path.contains('/search') ||
        path.contains('/check-in') ||
        path.contains('/checkin')) {
      return http.Response(
        jsonEncode({
          'items': [],
          'page': 0,
          'size': 5,
          'totalElements': 0,
          'totalPages': 0,
        }),
        200,
      );
    }
    if (RegExp(r'/patients/\d+$').hasMatch(path) ||
        RegExp(r'/patients/\d+/').hasMatch(path)) {
      return http.Response(jsonEncode(_sarahProfilePayload()), 200);
    }
    return http.Response(jsonEncode({}), 200);
  };
  ApiService.debugSetHttpClient(_globalMockClient);
}

void main() {
  // ───────────────────── setup / teardown ─────────────────────
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        if (call.method == 'readAll') {
          return <String, String>{
            'jwt_token': 'mock-token',
            'user_session': jsonEncode({'id': 1, 'token': 'mock-token'}),
          };
        }
        if (call.method == 'read') {
          final key = (call.arguments as Map?)?['key'] as String?;
          if (key == 'jwt_token') return 'mock-token';
          if (key == 'user_session') {
            return jsonEncode({'id': 1, 'token': 'mock-token'});
          }
          return null;
        }
        if (call.method == 'containsKey') return true;
        return null;
      },
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async {
        if (call.method == 'check') return ['wifi'];
        return null;
      },
    );
    // ...and listens for connection changes; without a stream handler that
    // listen throws MissingPluginException against whichever test is running.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
      const EventChannel('dev.fluttercommunity.plus/connectivity_status'),
      MockStreamHandler.inline(onListen: (_, __) {}),
    );
    _setSarahHttpMocks();
  });

  tearDown(() {
    ApiService.debugResetHttpClient();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
      const EventChannel('dev.fluttercommunity.plus/connectivity_status'),
      null,
    );
  });

  // ───────────────────── constructor tests ─────────────────────
  group('PatientDetailsPage – constructor', () {
    test('TC-PDP-001: creates with required patientId and default isCaregiver', () {
      const page = PatientDetailsPage(patientId: '123');
      expect(page.patientId, '123');
      expect(page.isCaregiver, isFalse);
    });

    test('TC-PDP-002: creates with isCaregiver true', () {
      const page = PatientDetailsPage(patientId: '456', isCaregiver: true);
      expect(page.patientId, '456');
      expect(page.isCaregiver, isTrue);
    });

    test('TC-PDP-003: is a StatefulWidget', () {
      const page = PatientDetailsPage(patientId: '1');
      expect(page, isA<StatefulWidget>());
    });

    test('TC-PDP-004: createState returns non-null state', () {
      const page = PatientDetailsPage(patientId: '1');
      final state = page.createState();
      expect(state, isNotNull);
    });

    test('TC-PDP-005: patientId stores various string values', () {
      const page1 = PatientDetailsPage(patientId: 'abc');
      expect(page1.patientId, 'abc');
      const page2 = PatientDetailsPage(patientId: '0');
      expect(page2.patientId, '0');
      const page3 = PatientDetailsPage(patientId: '');
      expect(page3.patientId, '');
    });

    test('TC-PDP-006: isCaregiver explicitly set to false', () {
      const page = PatientDetailsPage(patientId: '1', isCaregiver: false);
      expect(page.isCaregiver, isFalse);
    });

    test('TC-PDP-007: key parameter can be provided', () {
      const page = PatientDetailsPage(
        key: ValueKey('test'),
        patientId: '1',
      );
      expect(page.key, const ValueKey('test'));
    });
  });

  // ───────────────────── Helper ─────────────────────
  Widget buildTestWidget({
    String patientId = '42',
    bool isCaregiver = false,
    MockUserProvider? provider,
  }) {
    final userProvider = provider ??
        MockUserProvider(
          mockUser: MockUser(
            role: 'CAREGIVER',
            caregiverId: 10,
          ),
        );

    return ChangeNotifierProvider<UserProvider>.value(
      value: userProvider,
      child: MaterialApp(
        home: PatientDetailsPage(
          patientId: patientId,
          isCaregiver: isCaregiver,
        ),
      ),
    );
  }

  Future<void> pumpReady(WidgetTester tester, Widget widget) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await http.runWithClient(() async {
      await tester.pumpWidget(widget);
      // Allow async patient load to settle.
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }, () => _globalMockClient);
  }

  // ───────────────────── widget rendering tests ─────────────────────

  group('PatientDetailsPage – widget rendering', () {
    testWidgets('TC-PDP-008: renders PatientDetailsPage widget',
        (WidgetTester tester) async {
      await pumpReady(tester, buildTestWidget());
      expect(find.byType(PatientDetailsPage), findsOneWidget);
    });

    testWidgets('TC-PDP-009: renders Scaffold', (WidgetTester tester) async {
      await pumpReady(tester, buildTestWidget());
      expect(find.byType(Scaffold), findsWidgets);
    });

    testWidgets('TC-PDP-010: renders DefaultTabController',
        (WidgetTester tester) async {
      await pumpReady(tester, buildTestWidget());
      expect(find.byType(DefaultTabController), findsOneWidget);
    });

    testWidgets('TC-PDP-011: renders AppBar', (WidgetTester tester) async {
      await pumpReady(tester, buildTestWidget());
      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('TC-PDP-012: AppBar shows patient name Sarah Johnson',
        (WidgetTester tester) async {
      await pumpReady(tester, buildTestWidget());
      expect(find.text('Sarah Johnson'), findsWidgets);
    });

    testWidgets('TC-PDP-013: AppBar shows MRN in subtitle', (WidgetTester tester) async {
      await pumpReady(tester, buildTestWidget());
      expect(find.textContaining('MRN-2024-0156'), findsWidgets);
    });

    testWidgets('TC-PDP-014: AppBar subtitle contains Patient Details',
        (WidgetTester tester) async {
      await pumpReady(tester, buildTestWidget());
      expect(find.textContaining('Patient Details'), findsOneWidget);
    });

    testWidgets('TC-PDP-015: renders all five tab labels', (WidgetTester tester) async {
      await pumpReady(tester, buildTestWidget());
      expect(find.text('Info'), findsOneWidget);
      expect(find.text('Mood'), findsOneWidget);
      expect(find.text('Health'), findsOneWidget);
      expect(find.text('In-home'), findsOneWidget);
      expect(find.text('Virtual Check-In'), findsOneWidget);
    });

    testWidgets('TC-PDP-016: renders tab icons', (WidgetTester tester) async {
      await pumpReady(tester, buildTestWidget());
      expect(find.byIcon(Icons.info_outline), findsAtLeastNWidgets(1));
      expect(find.byIcon(Icons.favorite_border), findsAtLeastNWidgets(1));
      expect(
        find.byIcon(Icons.health_and_safety_outlined),
        findsAtLeastNWidgets(1),
      );
      expect(find.byIcon(Icons.home_outlined), findsAtLeastNWidgets(1));
      expect(
        find.byIcon(Icons.video_call_outlined),
        findsAtLeastNWidgets(1),
      );
    });

    testWidgets('TC-PDP-017: renders TabBar', (WidgetTester tester) async {
      await pumpReady(tester, buildTestWidget());
      expect(find.byType(TabBar), findsOneWidget);
    });

    testWidgets('TC-PDP-018: renders diagnoses in header', (WidgetTester tester) async {
      await pumpReady(tester, buildTestWidget());
      expect(find.text('Type 2 Diabetes'), findsOneWidget);
      expect(find.text('Hypertension'), findsOneWidget);
      expect(find.text('Chronic Fatigue Syndrome'), findsOneWidget);
    });

    testWidgets('TC-PDP-019: renders allergies in header', (WidgetTester tester) async {
      await pumpReady(tester, buildTestWidget());
      // Allergies are rendered as "allergen (severity)" when severity is present.
      expect(find.textContaining('Penicillin'), findsOneWidget);
      expect(find.textContaining('Shellfish'), findsOneWidget);
    });

    testWidgets('TC-PDP-020: Info tab shows contact phone by default',
        (WidgetTester tester) async {
      await pumpReady(tester, buildTestWidget());
      expect(find.text('(555) 123-4567'), findsWidgets);
    });

    testWidgets('TC-PDP-021: Info tab shows email', (WidgetTester tester) async {
      await pumpReady(tester, buildTestWidget());
      expect(find.text('sarah.johnson@email.com'), findsOneWidget);
    });

    testWidgets('TC-PDP-022: Info tab shows emergency contact name',
        (WidgetTester tester) async {
      await pumpReady(tester, buildTestWidget());
      expect(find.text('Michael Johnson'), findsOneWidget);
    });

    testWidgets('TC-PDP-023: Info tab shows emergency contact relationship',
        (WidgetTester tester) async {
      await pumpReady(tester, buildTestWidget());
      expect(find.text('Spouse'), findsOneWidget);
    });

    testWidgets('TC-PDP-024: Info tab shows emergency contact phone',
        (WidgetTester tester) async {
      await pumpReady(tester, buildTestWidget());
      expect(find.text('(555) 987-6543'), findsWidgets);
    });

    testWidgets('TC-PDP-025: builds with isCaregiver true', (WidgetTester tester) async {
      await pumpReady(tester, buildTestWidget(isCaregiver: true));
      expect(find.text('Sarah Johnson'), findsWidgets);
    });

    testWidgets('caregiver opens medication form for the selected patient',
        (WidgetTester tester) async {
      await pumpReady(tester, buildTestWidget(isCaregiver: true));

      await tester.tap(find.text('Health'));
      await tester.pumpAndSettle();

      final addButton = find.byKey(const Key('add-medication-button'));
      await tester.ensureVisible(addButton);
      await tester.tap(addButton);
      await tester.pumpAndSettle();

      final modal = tester.widget<AddMedicationModal>(
        find.byType(AddMedicationModal),
      );
      expect(modal.targetPatientId, 42);

      modal.onMedicationAdded(const Medication(
        patientId: 42,
        medicationName: 'Metformin',
        dosage: '500 mg',
        frequency: 'Twice daily',
        route: 'oral',
        isActive: true,
      ));
      await tester.pump();
    });

    testWidgets('TC-PDP-026: builds with patient role UserProvider',
        (WidgetTester tester) async {
      await pumpReady(
        tester,
        buildTestWidget(
          provider: MockUserProvider(
            mockUser: MockUser(role: 'PATIENT', patientId: 5),
          ),
        ),
      );
      expect(find.byType(PatientDetailsPage), findsOneWidget);
    });

    testWidgets('TC-PDP-027: invalid patientId shows error state',
        (WidgetTester tester) async {
      await pumpReady(tester, buildTestWidget(patientId: 'invalid_id'));
      expect(find.byType(PatientDetailsPage), findsOneWidget);
      expect(find.textContaining('Invalid patient ID'), findsWidgets);
    });

    testWidgets('TC-PDP-028: builds with empty patientId shows error',
        (WidgetTester tester) async {
      await pumpReady(tester, buildTestWidget(patientId: ''));
      expect(find.byType(PatientDetailsPage), findsOneWidget);
      expect(find.textContaining('Invalid patient ID'), findsWidgets);
    });
  });

  // resolvePatientUserId picks the patient's login account id (users.id), which video calls
  // and mood history are addressed by. The page's patientId is the patient record id
  // (patient.id), a different number for every patient but the first seeded one.
  group('resolvePatientUserId', () {
    // Scenario: the caregiver link carries the account id; it wins over the other sources.
    test('prefers the caregiver link patientUserId', () {
      final id = resolvePatientUserId(
        detailsPayload: {
          'user': {'id': 8},
        },
        profilePayload: {
          'user': {'id': 7},
        },
        caregiverData: {
          'link': {'patientUserId': 9},
        },
      );

      expect(id, 9);
    });

    // Scenario: without a link (patient viewing their own page) the details user is used.
    test('falls back to the details payload user id', () {
      final id = resolvePatientUserId(
        detailsPayload: {
          'user': {'id': '12'},
        },
        profilePayload: const {},
        caregiverData: null,
      );

      expect(id, 12);
    });

    // Scenario: only the profile payload carries the user.
    test('falls back to the profile payload user id', () {
      final id = resolvePatientUserId(
        detailsPayload: const {},
        profilePayload: {
          'user': {'id': 5},
        },
        caregiverData: const {'link': <String, dynamic>{}},
      );

      expect(id, 5);
    });

    // Scenario: patient2 (record id 2) is a different account from user 2 (caregiver@). With
    // no account id loaded the result is 0, never the record id, so a call or mood lookup
    // cannot silently target someone else's account.
    test('returns 0 rather than any other id when no account id is loaded', () {
      final id = resolvePatientUserId(
        detailsPayload: {
          'id': 2,
          'user': {'id': 0},
        },
        profilePayload: {'id': 2},
        caregiverData: {
          'link': {'patientUserId': null},
        },
      );

      expect(id, 0);
    });
  });
  // ───────────────────── Medicare tab (WBS 6.2.58) ─────────────────────
  group('PatientDetailsPage – Medicare tab', () {
    late HttpClientAdapter original;
    late RouteAdapter medicare;

    setUp(() {
      original = ApiClient.instance.debugHttpClientAdapter;
      medicare = RouteAdapter({
        '/v1/api/medicare/visits': envelope(fixtureResources('eob-bundle.json')),
        '/v1/api/medicare/coverage':
            envelope(fixtureResources('coverage-bundle.json')),
      });
      ApiClient.instance.debugSetHttpClientAdapter(medicare);
    });
    tearDown(() => ApiClient.instance.debugSetHttpClientAdapter(original));

    List<Uri> medicareCalls() =>
        medicare.uris.where((u) => u.path.contains('/medicare/')).toList();

    /// Dio runs outside the fake clock, so give it real time to answer.
    Future<void> openTab(WidgetTester tester, String label) async {
      await tester.tap(find.text(label));
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets(
        'TC-MCR-CG-016: a caregiver gets a sixth Medicare tab that reads this '
        'patient and keeps its result across tabs', (tester) async {
      await pumpReady(
          tester, buildTestWidget(patientId: '42', isCaregiver: true));
      expect(find.text('Medicare'), findsOneWidget);
      expect(find.byType(Tab), findsNWidgets(6));
      // Nothing is read until the caregiver opens the tab.
      expect(medicareCalls(), isEmpty);

      await openTab(tester, 'Medicare');
      expect(find.text('Coverage'), findsOneWidget);
      expect(medicareCalls().map((u) => u.queryParameters['patientId']),
          ['42', '42']);

      await openTab(tester, 'Info');
      await openTab(tester, 'Medicare');
      expect(find.text('Coverage'), findsOneWidget);
      expect(medicareCalls(), hasLength(2));
    });

    testWidgets(
        'TC-MCR-CG-022: a patient viewing their own page keeps the five tabs '
        'and no Medicare read', (tester) async {
      await pumpReady(
        tester,
        buildTestWidget(
          provider: MockUserProvider(
            mockUser: MockUser(role: 'PATIENT', patientId: 42),
          ),
        ),
      );
      expect(find.byType(Tab), findsNWidgets(5));
      expect(find.text('Medicare'), findsNothing);
      expect(medicareCalls(), isEmpty);
    });

    // ───── Testing Lead (PR #364 review): TC-MCR-CG-032, 033 ─────

    Future<void> pumpThemed(WidgetTester tester, ThemeData theme,
        {Size size = const Size(1200, 2400)}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await http.runWithClient(() async {
        await tester.pumpWidget(ChangeNotifierProvider<UserProvider>.value(
          value: MockUserProvider(
              mockUser: MockUser(role: 'CAREGIVER', caregiverId: 10)),
          child: MaterialApp(
            theme: theme,
            home: const PatientDetailsPage(patientId: '42', isCaregiver: true),
          ),
        ));
        for (var i = 0; i < 30; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }, () => _globalMockClient);
    }

    testWidgets(
        'TC-MCR-CG-032: on a 320 dp screen the six tabs scroll, and the '
        'Medicare tab can be reached, is labelled and is at least 48 dp '
        '(WCAG 2.1 SC 1.4.10, 2.5.5)', (tester) async {
      // The inherited Info-tab cards overflow at 320 dp in the widget-test
      // font (Test Plan section 11); drop only their reports, not the strip's.
      final original = FlutterError.onError;
      FlutterError.onError = (d) {
        final text = d.toString();
        if (text.contains('A RenderFlex overflowed') &&
            (text.contains('contact_info_card.dart') ||
                text.contains('emergency_contact_card.dart') ||
                text.contains('communication_history_card.dart'))) {
          return;
        }
        original?.call(d);
      };
      final handle = tester.ensureSemantics();
      await pumpThemed(tester, AppTheme.lightTheme,
          size: const Size(320, 2400));
      expect(tester.takeException(), isNull);
      expect(tester.widget<TabBar>(find.byType(TabBar)).isScrollable, isTrue);
      await tester.dragUntilVisible(find.text('Medicare'), find.byType(TabBar),
          const Offset(-100, 0));
      await tester.pumpAndSettle();
      final tab = find.ancestor(of: find.text('Medicare'), matching: find.byType(Tab));
      expect(tester.getSize(tab).height, greaterThanOrEqualTo(48));
      expect(tester.getSemantics(tab), isSemantics(label: 'Medicare\nTab 6 of 6'));
      await openTab(tester, 'Medicare');
      expect(find.text('Coverage'), findsOneWidget);
      handle.dispose();
      FlutterError.onError = original;
    });

    for (final theme in {
      'light': AppTheme.lightTheme,
      'dark': AppTheme.darkTheme,
    }.entries) {
      testWidgets(
          'TC-MCR-CG-033: the Medicare tab label has at least 4.5:1 contrast '
          'and its selected underline at least 3:1 in the ${theme.key} theme '
          '(WCAG 2.1 SC 1.4.3, 1.4.11)', (tester) async {
        await pumpThemed(tester, theme.value);
        // Unselected first, then selected.
        var low = lowContrastText(tester, find.byType(TabBar))
            .where((l) => l.startsWith('"Medicare"'))
            .toList();
        expect(low, isEmpty, reason: 'unselected: ${low.join('\n')}');
        await openTab(tester, 'Medicare');
        low = lowContrastText(tester, find.byType(TabBar))
            .where((l) => l.startsWith('"Medicare"'))
            .toList();
        expect(low, isEmpty, reason: 'selected: ${low.join('\n')}');
        final bar = tester.widget<TabBar>(find.byType(TabBar));
        final underline = (bar.indicator! as UnderlineTabIndicator).borderSide.color;
        final behind = backgroundOf(tester.element(find.text('Medicare')));
        expect(contrastRatio(underline, behind), greaterThanOrEqualTo(3.0),
            reason: 'underline ${contrastRatio(underline, behind).toStringAsFixed(2)}:1');
      });
    }
  });

  // ───────────────────── Testing Lead (PR #364 review) ─────────────────────
  // TC-PDP-029…054: the inherited page's own behaviour, which PR #364 changes
  // the file of and CI's whole-file coverage gate scores. A route table sits
  // in front of the Sarah mocks; requests are recorded; pushed screens are
  // captured by an observer and removed before they build.
  group('PatientDetailsPage – Testing Lead (TC-PDP)', () {
    late List<http.Request> requests;
    late _Pushes pushes;
    late HttpClientAdapter originalDio;
    late Map<String, http.Response Function(http.Request)> table;

    setUp(() {
      requests = [];
      table = {};
      pushes = _Pushes();
      final defaults = _httpHandler;
      _httpHandler = (req) async {
        requests.add(req);
        for (final e in table.entries) {
          final i = e.key.indexOf(' ');
          if (req.method == e.key.substring(0, i) &&
              RegExp(e.key.substring(i + 1)).hasMatch(req.url.path)) {
            return e.value(req);
          }
        }
        return defaults(req);
      };
      originalDio = ApiClient.instance.debugHttpClientAdapter;
      // The Medicare tab is never opened here; answer it anyway.
      ApiClient.instance.debugSetHttpClientAdapter(RouteAdapter({
        '/v1/api/medicare/visits': envelope(const []),
        '/v1/api/medicare/coverage': envelope(const []),
      }));
    });
    tearDown(
        () => ApiClient.instance.debugSetHttpClientAdapter(originalDio));

    /// 'METHOD path-regex' → response, checked before the Sarah defaults.
    void routes(Map<String, http.Response Function(http.Request)> more) =>
        table.addAll(more);

    http.Response json(Object body, [int status = 200]) =>
        http.Response(jsonEncode(body), status);

    List<http.Request> sent(String method, String pathPattern) => requests
        .where((r) =>
            r.method == method && RegExp(pathPattern).hasMatch(r.url.path))
        .toList();

    MockUserProvider caregiver() => MockUserProvider(
        mockUser: MockUser(role: 'CAREGIVER', caregiverId: 10));

    Future<void> pumpPage(WidgetTester t,
        {bool isCaregiver = true, MockUserProvider? provider}) async {
      t.view.physicalSize = const Size(1200, 2400);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await http.runWithClient(() async {
        await t.pumpWidget(ChangeNotifierProvider<UserProvider>.value(
          value: provider ?? (isCaregiver ? caregiver() : MockUserProvider()),
          child: MaterialApp(
            navigatorObservers: [pushes],
            home: PatientDetailsPage(patientId: '42', isCaregiver: isCaregiver),
          ),
        ));
        for (var i = 0; i < 30; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
      }, () => _globalMockClient);
    }

    /// Runs [body] where the page's http.get/post calls reach the mock, then
    /// lets the page settle.
    Future<void> act(WidgetTester t, Future<void> Function() body,
        {int frames = 20}) async {
      await http.runWithClient(() async {
        await body();
        for (var i = 0; i < frames; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
      }, () => _globalMockClient);
    }

    Future<void> openTab(WidgetTester t, String label) =>
        act(t, () => t.tap(find.text(label)), frames: 10);

    /// The inherited check-in status filter is a fixed 190 dp wide, and in
    /// the widget-test font its row overflows by 11 px (Test Plan §11). This
    /// drops only that report, so a check-in case fails on what it names.
    /// Returns the restore call, made at the end of the test body.
    void Function() ignoreFilterOverflow() {
      final original = FlutterError.onError;
      FlutterError.onError = (d) {
        final text = d.toString();
        if (text.contains('A RenderFlex overflowed') &&
            text.contains('DropdownButtonFormField') &&
            text.contains('patient_details_page.dart')) {
          return;
        }
        original?.call(d);
      };
      return () => FlutterError.onError = original;
    }

    /// Drops only the inherited CommunicationHistoryCard's debug report that a
    /// call's ListTile sits in a coloured DecoratedBox (Test Plan §11).
    void Function() ignoreCallTileInk() {
      final original = FlutterError.onError;
      FlutterError.onError = (d) {
        if (d.toString().contains(
            'ListTile background color or ink splashes may be invisible')) {
          return;
        }
        original?.call(d);
      };
      return () => FlutterError.onError = original;
    }

    String? snack(WidgetTester t) {
      final s = find.byType(SnackBar);
      if (s.evaluate().isEmpty) return null;
      return (t.widget<SnackBar>(s.last).content as Text).data;
    }

    /// A second SnackBar waits behind the first; clear the queue first.
    Future<void> clearSnacks(WidgetTester t) async {
      ScaffoldMessenger.of(t.element(find.byType(PatientDetailsPage)))
          .clearSnackBars();
      await t.pumpAndSettle();
    }

    // ── caregiver view, call and messaging policy ──

    Map<String, dynamic> caregiverView({Object? calls = 'false'}) => {
          'patient': {'firstName': 'Sarah', 'lastName': 'Johnson'},
          'link': {
            'linkId': '77',
            'patientUserId': 500,
            'patientVideoCallsEnabled': calls,
            'patientMessagingEnabled': true,
          },
        };

    testWidgets(
        'TC-PDP-029: a caregiver\'s page reads the caregiver view, takes mood '
        'and calls for the link\'s patient user, and shows both policies',
        (t) async {
      routes({
        r'GET /caregivers/10/patients/42$': (_) => json(caregiverView()),
      });
      await pumpPage(t);
      expect(sent('GET', r'/caregivers/10/patients/42$'), hasLength(1));
      expect(sent('GET', r'/patient/500/mood$'), hasLength(1));
      final calls = find.widgetWithText(
          SwitchListTile, 'Allow Patient-Initiated Video Calls');
      expect(t.widget<SwitchListTile>(calls).value, isFalse);
      expect(find.text('Patient-initiated video calls are currently blocked.'),
          findsOneWidget);
      expect(
          t
              .widget<SwitchListTile>(
                  find.widgetWithText(SwitchListTile, 'Allow Patient Messaging'))
              .value,
          isTrue);
      expect(find.text('This patient can send messages to their care team.'),
          findsOneWidget);
    });

    testWidgets(
        'TC-PDP-030: turning patient-initiated calls on saves it for the link '
        'and says so; a failed save turns it back and says to retry',
        (t) async {
      var status = 200;
      routes({
        r'GET /caregivers/10/patients/42$': (_) => json(caregiverView()),
        r'POST /caregiver-patient-links/77/patient-video-calls$': (_) =>
            json({}, status),
      });
      await pumpPage(t);
      final calls = find.widgetWithText(
          SwitchListTile, 'Allow Patient-Initiated Video Calls');
      await act(t, () => t.tap(calls));
      final posts =
          sent('POST', r'/caregiver-patient-links/77/patient-video-calls$');
      expect(posts, hasLength(1));
      expect(jsonDecode(posts.single.body), {'enabled': true});
      expect(snack(t), 'Patient-initiated calls are enabled.');
      expect(t.widget<SwitchListTile>(calls).value, isTrue);

      status = 500;
      await clearSnacks(t);
      await act(t, () => t.tap(calls), frames: 40);
      expect(t.widget<SwitchListTile>(calls).value, isTrue);
      expect(find.text('Unable to update patient call policy. Please retry.'),
          findsOneWidget);
    });

    testWidgets(
        'TC-PDP-031: turning patient messaging off saves it and says so; a '
        'failed save turns it back and says to retry', (t) async {
      var status = 200;
      routes({
        r'GET /caregivers/10/patients/42$': (_) => json(caregiverView()),
        r'POST /caregiver-patient-links/77/patient-messaging$': (_) =>
            json({}, status),
      });
      await pumpPage(t);
      final messaging =
          find.widgetWithText(SwitchListTile, 'Allow Patient Messaging');
      await act(t, () => t.tap(messaging));
      expect(
          jsonDecode(sent('POST', r'/patient-messaging$').single.body),
          {'enabled': false});
      expect(snack(t), 'Patient messaging is disabled.');
      expect(find.text('Patient messaging is currently blocked.'),
          findsOneWidget);

      status = 500;
      await clearSnacks(t);
      await act(t, () => t.tap(messaging), frames: 40);
      expect(t.widget<SwitchListTile>(messaging).value, isFalse);
      expect(
          find.text('Unable to update patient messaging policy. Please retry.'),
          findsOneWidget);
    });

    testWidgets(
        'TC-PDP-032: a link with no call setting allows calls, and a patient '
        'viewing their page gets no policy switches', (t) async {
      routes({
        r'GET /caregivers/10/patients/42$': (_) =>
            json(caregiverView(calls: null)),
      });
      await pumpPage(t);
      expect(
          t
              .widget<SwitchListTile>(find.widgetWithText(
                  SwitchListTile, 'Allow Patient-Initiated Video Calls'))
              .value,
          isTrue);

      await t.pumpWidget(const SizedBox());
      requests.clear();
      await pumpPage(t, isCaregiver: false);
      expect(find.byType(SwitchListTile), findsNothing);
      expect(sent('GET', r'/caregivers/'), isEmpty);
    });

    // ── personalization ──

    testWidgets(
        'TC-PDP-033: a caregiver edits personalization; Save sends the edits '
        'over the stored profile and shows the saved values', (t) async {
      routes({
        r'PUT /patients/42/profile$': (req) {
          final sent = jsonDecode(req.body) as Map<String, dynamic>;
          return json({'data': sent});
        },
      });
      await pumpPage(t);
      expect(find.text('Not set'), findsNWidgets(5));
      await act(t, () => t.tap(find.text('Edit')),
          frames: 2);
      await t.enterText(find.widgetWithText(TextField, 'Likes'), ' Gardening ');
      await t.enterText(find.widgetWithText(TextField, 'Phobias'), 'Heights');
      await t.tap(find.byType(DropdownButtonFormField<String>).first);
      await t.pumpAndSettle();
      await t.tap(find.text('Visual').last);
      await t.pumpAndSettle();
      await act(t, () => t.tap(find.text('Save')));

      final put = sent('PUT', r'/patients/42/profile$').single;
      final body = jsonDecode(put.body) as Map<String, dynamic>;
      expect(body['likes'], 'Gardening');
      expect(body['phobias'], 'Heights');
      expect(body['dislikes'], '');
      expect(body['preferredCommunicationMethod'], 'visual');
      expect(body['firstName'], 'Sarah', reason: 'stored fields are kept');
      expect(snack(t), 'Personalization saved');
      expect(find.text('Gardening'), findsOneWidget);
      expect(find.text('Visual'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
    });

    testWidgets(
        'TC-PDP-034: a failed personalization save says so with its status '
        'and leaves edit mode', (t) async {
      routes({r'PUT /patients/42/profile$': (_) => json({}, 500)});
      await pumpPage(t);
      await act(t, () => t.tap(find.text('Edit')),
          frames: 2);
      await act(t, () => t.tap(find.text('Save')));
      expect(snack(t), 'Save failed: 500');
      expect(find.widgetWithText(TextField, 'Likes'), findsNothing);
    });

    testWidgets(
        'TC-PDP-035: a patient sees personalization read-only, with a known '
        'method capitalised and an unknown one as Not set', (t) async {
      var method = 'WRITTEN';
      routes({
        r'GET /patients/42/profile$': (_) => json({
              'data': {
                ..._sarahProfilePayload(),
                'likes': 'Jazz',
                'preferred_communication_method': method,
              }
            }),
      });
      await pumpPage(t, isCaregiver: false);
      expect(find.text('Jazz'), findsOneWidget);
      expect(find.text('Written'), findsOneWidget);
      expect(find.text('Edit'), findsNothing);

      method = 'telepathy';
      await t.pumpWidget(const SizedBox());
      await pumpPage(t, isCaregiver: false);
      expect(find.text('Telepathy'), findsNothing);
      expect(find.text('Not set'), findsNWidgets(4));
    });

    // ── mood and symptoms ──

    testWidgets(
        'TC-PDP-036: mood history is mapped and ordered newest first, and the '
        'newest mood is the header\'s current mood', (t) async {
      final now = DateTime.now();
      routes({
        r'GET /patient/\d+/mood$': (_) => json([
              {
                'score': 9,
                'createdAt': now.subtract(const Duration(days: 3)).toIso8601String(),
                'note': 'Great walk'
              },
              {
                'score': '3',
                'label': 'Low',
                'timestamp': now.subtract(const Duration(hours: 2)).toIso8601String(),
              },
              {'score': 7, 'date': now.subtract(const Duration(days: 1)).toIso8601String()},
              {'score': 1, 'label': 'feeling sad', 'date': now.subtract(const Duration(days: 5)).toIso8601String()},
              'not a map',
            ]),
      });
      await pumpPage(t);
      final header = t.widget<PatientHeaderCard>(find.byType(PatientHeaderCard));
      expect(header.currentMoodLabel, 'Low');
      expect(header.currentMoodEmoji, '😟');
      await openTab(t, 'Mood');
      final entries =
          t.widget<MoodHistorySection>(find.byType(MoodHistorySection)).entries;
      expect(entries.map((e) => e.label), ['Low', 'Good', 'Excellent', 'feeling sad']);
      expect(entries.map((e) => e.score5), [3, 4, 5, 1]);
      expect(entries.map((e) => e.emoji), ['😟', '🙂', '😄', '😟']);
      expect(entries[2].note, 'Great walk');
    });

    testWidgets(
        'TC-PDP-037: the newest symptom sets the pain card, and symptoms are '
        'listed newest first with their severity', (t) async {
      final now = DateTime.now();
      routes({
        r'GET /symptoms/patient/42$': (_) => json({'data': [
              {
                'id': 1,
                'symptomKey': 'Back pain',
                'severity': 3,
                'takenAt': now.subtract(const Duration(days: 2)).toIso8601String(),
              },
              {
                'id': 2,
                'symptomKey': 'Headache',
                'symptomValue': 'throbbing',
                'severity': 5,
                'createdAt': now.subtract(const Duration(minutes: 30)).toIso8601String(),
                'clinicalNotes': 'after lunch',
              },
              {'id': 3, 'severity': 'x', 'takenAt': now.subtract(const Duration(hours: 5)).toIso8601String()},
            ]}),
      });
      await pumpPage(t);
      await openTab(t, 'Health');
      final pain = t.widget<PainLevelCard>(find.byType(PainLevelCard));
      expect(pain.currentPain, 8);
      expect(pain.location, 'Headache throbbing');
      expect(pain.lastReportedText, '30m ago');
      final symptoms = t
          .widget<sympt.RecentSymptomsSection>(
              find.byType(sympt.RecentSymptomsSection))
          .entries;
      expect(symptoms.map((s) => s.name), ['Headache throbbing', 'Symptom', 'Back pain']);
      expect(symptoms.map((s) => s.severity), ['Severe', 'Mild', 'Moderate']);
      expect(symptoms.first.note, 'after lunch');
    });

    testWidgets(
        'TC-PDP-057: severity on the backend 1-5 scale reads as the patient '
        'logged it (1-2 Mild, 3-4 Moderate, 5 Severe), and a Severe latest '
        'symptom sets the pain card', (t) async {
      final now = DateTime.now();
      routes({
        r'GET /symptoms/patient/42$': (_) => json({'data': [
              for (var s = 1; s <= 5; s++)
                {
                  'id': s,
                  'symptomKey': 'Symptom $s',
                  'severity': s,
                  'takenAt': now.subtract(Duration(hours: 6 - s)).toIso8601String(),
                },
            ]}),
      });
      await pumpPage(t);
      await openTab(t, 'Health');
      final symptoms = t
          .widget<sympt.RecentSymptomsSection>(
              find.byType(sympt.RecentSymptomsSection))
          .entries;
      expect(symptoms.map((s) => s.name),
          ['Symptom 5', 'Symptom 4', 'Symptom 3', 'Symptom 2', 'Symptom 1']);
      expect(symptoms.map((s) => s.severity),
          ['Severe', 'Moderate', 'Moderate', 'Mild', 'Mild']);
      final pain = t.widget<PainLevelCard>(find.byType(PainLevelCard));
      expect(pain.currentPain, 8);
      expect(pain.dizziness, 4);
      expect(pain.fatigue, 10);
    });

    // DEF-MCR-36: TC-PDP-057 sets the pain card only from a Severe entry.
    for (final (severity, label, pain, dizziness, fatigue) in [
      (3, 'Moderate', 5, 3, 10),
      (1, 'Mild', 2, 1, 4),
    ]) {
      testWidgets(
          'TC-PDP-058: a $label latest symptom (backend $severity) sets the pain '
          'card to $pain, dizziness $dizziness, fatigue $fatigue', (t) async {
        final now = DateTime.now();
        routes({
          r'GET /symptoms/patient/42$': (_) => json({'data': [
                {
                  'id': 1,
                  'symptomKey': 'Older',
                  'severity': 5,
                  'takenAt': now.subtract(const Duration(days: 1)).toIso8601String(),
                },
                {
                  'id': 2,
                  'symptomKey': 'Latest',
                  'severity': severity,
                  'takenAt': now.subtract(const Duration(hours: 1)).toIso8601String(),
                },
              ]}),
        });
        await pumpPage(t);
        await openTab(t, 'Health');
        final card = t.widget<PainLevelCard>(find.byType(PainLevelCard));
        expect(card.location, 'Latest');
        expect(card.currentPain, pain);
        expect(card.dizziness, dizziness);
        expect(card.fatigue, fatigue);
      });
    }

    testWidgets(
        'TC-PDP-059: a missing or 0 severity reads Mild, and a value above 5 '
        'reads Severe', (t) async {
      final now = DateTime.now();
      final values = <Object?>[null, 0, 6, 10];
      routes({
        r'GET /symptoms/patient/42$': (_) => json({'data': [
              for (var i = 0; i < values.length; i++)
                {
                  'id': i + 1,
                  'symptomKey': 'Value ${values[i]}',
                  'severity': values[i],
                  'takenAt': now.subtract(Duration(hours: i + 1)).toIso8601String(),
                },
            ]}),
      });
      await pumpPage(t);
      await openTab(t, 'Health');
      final symptoms = t
          .widget<sympt.RecentSymptomsSection>(
              find.byType(sympt.RecentSymptomsSection))
          .entries;
      expect({for (final s in symptoms) s.name: s.severity}, {
        'Value null': 'Mild',
        'Value 0': 'Mild',
        'Value 6': 'Severe',
        'Value 10': 'Severe',
      });
    });

    testWidgets(
        'TC-PDP-060: for the same symptoms the caregiver page and the '
        "patient's own symptom tab show the same severity", (t) async {
      final now = DateTime.now();
      final values = <Object?>[null, 0, 1, 2, 3, 4, 5, 6, 10];
      final payload = {
        'data': [
          for (var i = 0; i < values.length; i++)
            {
              'id': i + 1,
              'patientId': 42,
              'symptomKey': 'Value ${values[i]}',
              'severity': values[i],
              'takenAt': now.subtract(Duration(hours: i + 1)).toIso8601String(),
            },
        ]
      };
      routes({r'GET /symptoms/patient/42$': (_) => json(payload)});

      await pumpPage(t);
      await openTab(t, 'Health');
      final caregiverSees = {
        for (final s in t
            .widget<sympt.RecentSymptomsSection>(
                find.byType(sympt.RecentSymptomsSection))
            .entries)
          s.name: s.severity.toLowerCase(),
      };

      await http.runWithClient(() async {
        await t.pumpWidget(ChangeNotifierProvider<UserProvider>.value(
          value: MockUserProvider(
              mockUser: MockUser(id: 1, role: 'PATIENT', patientId: 42)),
          child: const MaterialApp(
              home: Scaffold(body: SymptomTab(patientId: '42'))),
        ));
        for (var i = 0; i < 20; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
      }, () => _globalMockClient);
      final patientSees = {
        for (final c in t.widgetList<SymptomCard>(find.byType(SymptomCard)))
          c.title: c.severity,
      };

      expect(patientSees, hasLength(values.length));
      expect(caregiverSees, patientSees);
      expect(caregiverSees['Value 5'], 'severe');
      expect(caregiverSees['Value 3'], 'moderate');
    });

    // ── medications and known risks ──

    testWidgets(
        'TC-PDP-038: medications that fail to load say so with Retry, and '
        'Retry loads them', (t) async {
      var status = 500;
      routes({
        r'GET /patients/42/medications$': (_) => json([], status),
      });
      await pumpPage(t);
      await openTab(t, 'Health');
      expect(find.text('Failed to load medications: 500'), findsOneWidget);
      status = 200;
      await act(t, () => t.tap(find.text('Retry')));
      expect(find.text('Failed to load medications: 500'), findsNothing);
      expect(sent('GET', r'/patients/42/medications$'), hasLength(2));
    });

    final riskTypes = [
      {'id': 1, 'name': 'Fall risk'},
      {'id': '2', 'name': 'Wandering'},
      {'id': 'x', 'name': 'Broken type'},
    ];

    testWidgets(
        'TC-PDP-039: flagged risks show in the banner and the Known Risks card; '
        'a caregiver\'s edit adds and removes flags and says saved',
        (t) async {
      var flagged = [
        {'id': 11, 'riskTypeId': 1},
        {'id': 'bad', 'riskTypeId': 'x'},
      ];
      routes({
        r'GET /risk-types$': (_) => json(riskTypes),
        r'GET /patients/42/risks$': (_) => json(flagged),
        r'POST /patients/42/risks$': (_) => json({'id': 12}, 201),
        r'DELETE /patients/42/risks/11$': (_) => http.Response('', 204),
      });
      await pumpPage(t);
      expect(find.text('Known Risks: Fall risk'), findsOneWidget);
      await openTab(t, 'Health');
      expect(find.text('Fall risk'), findsOneWidget);
      await act(t, () => t.tap(find.text('Edit')),
          frames: 2);
      expect(find.byType(CheckboxListTile), findsNWidgets(2));
      await act(t, () => t.tap(find.widgetWithText(CheckboxListTile, 'Wandering')),
          frames: 1);
      await act(t, () => t.tap(find.widgetWithText(CheckboxListTile, 'Fall risk')),
          frames: 1);
      flagged = [
        {'id': 12, 'riskTypeId': 2},
      ];
      await act(t, () => t.tap(find.text('Save')));
      expect(jsonDecode(sent('POST', r'/patients/42/risks$').single.body),
          {'riskTypeId': 2});
      expect(sent('DELETE', r'/patients/42/risks/11$'), hasLength(1));
      expect(snack(t), 'Known risks saved');
      expect(find.text('Known Risks: Wandering'), findsOneWidget);
      expect(find.byType(CheckboxListTile), findsNothing);
    });

    testWidgets(
        'TC-PDP-040: a risk that fails to add or to remove is reported with '
        'its status, and the card stays in edit mode', (t) async {
      routes({
        r'GET /risk-types$': (_) => json(riskTypes),
        r'GET /patients/42/risks$': (_) => json([
              {'id': 11, 'riskTypeId': 1}
            ]),
        r'POST /patients/42/risks$': (_) => json({}, 500),
        r'DELETE /patients/42/risks/11$': (_) => json({}, 500),
      });
      await pumpPage(t);
      await openTab(t, 'Health');
      await act(t, () => t.tap(find.text('Edit')),
          frames: 2);
      await act(t, () => t.tap(find.widgetWithText(CheckboxListTile, 'Wandering')),
          frames: 1);
      await act(t, () => t.tap(find.text('Save')));
      expect(snack(t), 'Failed to add risk: 500');
      expect(find.byType(CheckboxListTile), findsNWidgets(2));

      await t.pumpWidget(const SizedBox());
      await pumpPage(t);
      await openTab(t, 'Health');
      await act(t, () => t.tap(find.text('Edit')),
          frames: 2);
      await act(t, () => t.tap(find.widgetWithText(CheckboxListTile, 'Fall risk')),
          frames: 1);
      await act(t, () => t.tap(find.text('Save')));
      expect(snack(t), 'Failed to remove risk: 500');
    });

    testWidgets(
        'TC-PDP-041: a patient sees Known Risks without Edit, and no flags '
        'reads "No risks flagged."; risk types that fail to load leave no '
        'banner', (t) async {
      routes({r'GET /risk-types$': (_) => json({}, 500)});
      await pumpPage(t, isCaregiver: false);
      expect(find.textContaining('Known Risks:'), findsNothing);
      await openTab(t, 'Health');
      expect(find.text('No risks flagged.'), findsOneWidget);
      expect(find.text('Edit'), findsNothing);
    });

    // ── virtual check-ins ──

    Map<String, dynamic> summary(int id,
            {String? submitted, String? reviewed, int questions = 2}) =>
        {
          'checkInId': id,
          'patientId': 42,
          'createdAt': '2026-10-0${id}T09:00:00',
          'submittedAt': submitted,
          'reviewedAt': reviewed,
          'questionCount': questions,
        };

    Map<String, dynamic> page(List<Map<String, dynamic>> items,
            {int number = 0, int pages = 1}) =>
        {
          'items': items,
          'page': number,
          'size': 5,
          'totalElements': items.length,
          'totalPages': pages,
        };

    testWidgets(
        'TC-PDP-042: check-ins show as draft, submitted or reviewed, and the '
        'pager reads the next and previous pages', (t) async {
      final restore = ignoreFilterOverflow();
      routes({
        r'GET /checkins/patients/42/search$': (req) =>
            req.url.queryParameters['page'] == '1'
                ? json(page([summary(4, questions: 1)], number: 1, pages: 2))
                : json(page([
                    summary(1),
                    summary(2, submitted: '2026-10-02T10:00:00'),
                    summary(3,
                        submitted: '2026-10-03T10:00:00',
                        reviewed: '2026-10-03T12:00:00'),
                  ], pages: 2)),
      });
      await pumpPage(t);
      await openTab(t, 'Virtual Check-In');
      final entries = t
          .widget<VirtualCheckInHistoryCard>(
              find.byType(VirtualCheckInHistoryCard))
          .entries;
      expect(entries.map((e) => e.status), [
        CheckInStatus.draft,
        CheckInStatus.submitted,
        CheckInStatus.reviewed,
      ]);
      expect(entries.map((e) => e.summary), [
        '2 configured questions pending patient submission.',
        '2 question responses submitted and pending caregiver review.',
        '2 question responses reviewed by caregiver.',
      ]);
      expect(find.text('Page 1 of 2'), findsOneWidget);

      await act(t, () => t.tap(find.widgetWithIcon(IconButton, Icons.chevron_right)));
      expect(find.text('Page 2 of 2'), findsOneWidget);
      expect(
          sent('GET', r'/search$').last.url.queryParameters['page'], '1');
      await act(t, () => t.tap(find.widgetWithIcon(IconButton, Icons.chevron_left)));
      expect(find.text('Page 1 of 2'), findsOneWidget);
      expect(
          sent('GET', r'/search$').last.url.queryParameters['page'], '0');
      restore();
    });

    testWidgets(
        'TC-PDP-043: the status filter and a date range narrow the check-in '
        'search, and Clear dates removes the range', (t) async {
      final restore = ignoreFilterOverflow();
      routes({
        r'GET /checkins/patients/42/search$': (_) => json(page([summary(1)])),
      });
      await pumpPage(t);
      await openTab(t, 'Virtual Check-In');
      await act(t, () => t.tap(find.byType(DropdownButtonFormField<String>)),
          frames: 5);
      await act(t, () => t.tap(find.text('Submitted').last));
      expect(sent('GET', r'/search$').last.url.queryParameters['status'],
          'submitted');

      await act(t, () => t.tap(find.text('Date range')),
          frames: 5);
      await act(t, () => t.tap(find.text('Save')));
      final q = sent('GET', r'/search$').last.url.queryParameters;
      expect(q['startDate'], isNotNull);
      expect(q['endDate'], isNotNull);
      expect(q['page'], '0');
      expect(find.text('Clear dates'), findsOneWidget);

      await act(t, () => t.tap(find.text('Clear dates')));
      expect(sent('GET', r'/search$').last.url.queryParameters.containsKey('startDate'),
          isFalse);
      expect(find.text('Date range'), findsOneWidget);
      restore();
    });

    testWidgets(
        'TC-PDP-044: without the search endpoint the older list is read, and '
        'with no check-ins at all the patient record\'s own list is shown',
        (t) async {
      final restore = ignoreFilterOverflow();
      var older = [summary(1)];
      routes({
        r'GET /checkins/patients/42/search$': (_) => json({}, 404),
        r'GET /checkins/patients/42$': (_) => json(older),
        r'GET /v1/api/patients/42$': (_) => json({
              ..._sarahProfilePayload(),
              'virtualCheckIns': [
                {
                  'id': 'v1',
                  'type': 'follow_up',
                  'status': 'missed',
                  'caregiverName': 'Nurse Kim',
                  'startedAt': '2026-09-01T09:00:00',
                  'durationMinutes': '15',
                  'summary': 'Called twice',
                },
                {'id': 'v2', 'type': 'urgent', 'status': 'canceled'},
                {'id': 'v3', 'status': 'done'},
              ],
            }),
      });
      await pumpPage(t);
      await openTab(t, 'Virtual Check-In');
      expect(sent('GET', r'/checkins/patients/42$'), hasLength(1));
      expect(find.text('Page 1 of 1'), findsOneWidget);

      older = [];
      await t.pumpWidget(const SizedBox());
      await pumpPage(t);
      await openTab(t, 'Virtual Check-In');
      final entries = t
          .widget<VirtualCheckInHistoryCard>(
              find.byType(VirtualCheckInHistoryCard))
          .entries;
      expect(entries.map((e) => e.type),
          [CheckInType.followUp, CheckInType.urgent, CheckInType.routine]);
      expect(entries.map((e) => e.status), [
        CheckInStatus.missed,
        CheckInStatus.cancelled,
        CheckInStatus.completed,
      ]);
      expect(entries.first.clinicianName, 'Nurse Kim');
      expect(entries.first.durationMinutes, 10, reason: 'clamped to 0..10');
      expect(entries[1].clinicianName, 'Care Team');
      expect(find.text('No pages'), findsOneWidget);
      restore();
    });

    Map<String, dynamic> detail(String status) => {
          'checkInId': 2,
          'patientId': 42,
          'status': status,
          'submittedAt': '2026-10-02T10:05:00',
          'answers': [
            {'questionId': 1, 'prompt': 'How is your pain?', 'type': 'TEXT', 'ordinal': 1, 'valueText': 'A little'},
            {'questionId': 2, 'prompt': 'Slept well?', 'type': 'BOOLEAN', 'ordinal': 2, 'valueBoolean': false},
            {'questionId': 3, 'prompt': 'Pain score', 'type': 'NUMBER', 'ordinal': 3, 'valueNumber': 4},
            {'questionId': 4, 'prompt': 'Anything else?', 'type': 'TEXT', 'ordinal': 4},
          ],
        };

    testWidgets(
        'TC-PDP-045: a submitted check-in opens its answers, and Mark as '
        'reviewed saves the review and reloads', (t) async {
      final restore = ignoreFilterOverflow();
      routes({
        r'GET /checkins/patients/42/search$': (_) => json(page([
              summary(2, submitted: '2026-10-02T10:00:00'),
            ])),
        r'GET /checkins/2/detail$': (_) => json(detail('submitted')),
        r'POST /checkins/2/review$': (_) => json({}),
      });
      await pumpPage(t);
      await openTab(t, 'Virtual Check-In');
      await act(t,
          () => t.tap(find.text(
              '2 question responses submitted and pending caregiver review.')));
      expect(find.text('Check-in #2 details'), findsOneWidget);
      expect(find.text('Submitted at: 2026-10-02 10:05'), findsOneWidget);
      expect(find.text('Reviewed at: N/A'), findsOneWidget);
      expect(find.text('Answer: A little'), findsOneWidget);
      expect(find.text('Answer: No'), findsOneWidget);
      expect(find.text('Answer: 4'), findsOneWidget);
      expect(find.text('Answer: No answer submitted'), findsOneWidget);
      final searches = sent('GET', r'/search$').length;
      await act(t, () => t.tap(find.text('Mark as reviewed')));
      expect(sent('POST', r'/checkins/2/review$'), hasLength(1));
      expect(find.text('Check-in #2 details'), findsNothing);
      expect(sent('GET', r'/search$').length, searches + 1);
      restore();
    });

    testWidgets(
        'TC-PDP-046: a review that fails is reported and the dialog stays; '
        'Close leaves without a review; a detail that fails to load says so',
        (t) async {
      final restore = ignoreFilterOverflow();
      var detailStatus = 200;
      routes({
        r'GET /checkins/patients/42/search$': (_) => json(page([
              summary(2, submitted: '2026-10-02T10:00:00'),
            ])),
        r'GET /checkins/2/detail$': (_) => json(detail('submitted'), detailStatus),
        r'POST /checkins/2/review$': (_) => json({}, 500),
      });
      await pumpPage(t);
      await openTab(t, 'Virtual Check-In');
      final tile = find.text(
          '2 question responses submitted and pending caregiver review.');
      await act(t, () => t.tap(tile));
      await act(t, () => t.tap(find.text('Mark as reviewed')));
      expect(snack(t), 'Failed to mark check-in as reviewed');
      expect(find.text('Check-in #2 details'), findsOneWidget);
      final searches = sent('GET', r'/search$').length;
      await act(t, () => t.tap(find.text('Close')));
      expect(find.text('Check-in #2 details'), findsNothing);
      expect(sent('GET', r'/search$').length, searches);

      detailStatus = 500;
      await clearSnacks(t);
      await act(t, () => t.tap(tile), frames: 40);
      expect(find.text('Failed to load check-in details'), findsOneWidget);
      restore();
    });

    testWidgets(
        'TC-PDP-047: a reviewed check-in offers no Mark as reviewed, and a '
        'patient\'s page has no check-in filters or pager', (t) async {
      final restore = ignoreFilterOverflow();
      routes({
        r'GET /checkins/patients/42/search$': (_) => json(page([
              summary(3,
                  submitted: '2026-10-03T10:00:00',
                  reviewed: '2026-10-03T12:00:00'),
            ])),
        r'GET /checkins/3/detail$': (_) => json({
              ...detail('reviewed'),
              'checkInId': 3,
              'reviewedAt': '2026-10-03T12:00:00',
            }),
      });
      await pumpPage(t);
      await openTab(t, 'Virtual Check-In');
      await act(t,
          () => t.tap(find.text('2 question responses reviewed by caregiver.')));
      expect(find.text('Reviewed at: 2026-10-03 12:00'), findsOneWidget);
      expect(find.text('Mark as reviewed'), findsNothing);

      await t.pumpWidget(const SizedBox());
      await pumpPage(t, isCaregiver: false);
      await openTab(t, 'Virtual Check-In');
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      expect(find.textContaining('Page '), findsNothing);
      restore();
    });

    // ── call history ──

    List<Map<String, dynamic>> callEvents() => [
          {
            'callId': 'call-a',
            'eventType': 'CALL_START',
            'actorUserId': 500,
            'occurredAt': '2026-10-10T09:00:00Z',
          },
          {
            'callId': 'call-b',
            'eventType': 'CALL_START',
            'actorUserId': 1,
            'targetUserId': 2,
            'metadataJson': jsonEncode({'contextPatientUserIds': ['500']}),
            'occurredAt': '2026-10-12T09:00:00Z',
          },
          {
            'callId': 'call-c',
            'eventType': 'CALL_START',
            'actorUserId': 1,
            'metadataJson': {'contextPatientUserId': 500},
            'occurredAt': 'not a date',
          },
          {
            'callId': 'other',
            'eventType': 'CALL_START',
            'actorUserId': 1,
            'targetUserId': 3,
            'metadataJson': '{bad json',
            'occurredAt': '2026-10-13T09:00:00Z',
          },
        ];

    testWidgets(
        'TC-PDP-048: call history keeps only this patient\'s calls, newest '
        'first, and a call opens its summary', (t) async {
      final restore = ignoreCallTileInk();
      routes({
        r'GET /caregivers/10/patients/42$': (_) => json(caregiverView()),
        r'GET /calls/telemetry/my$': (_) => json(callEvents()),
      });
      await pumpPage(t);
      final events = t
          .widget<CommunicationHistoryCard>(find.byType(CommunicationHistoryCard))
          .events;
      expect(events.map((e) => e['callId']), ['call-b', 'call-a', 'call-c']);

      await t.tap(find.text('View details').first);
      final route = pushes.takeLast();
      final screen = (route as MaterialPageRoute)
          .builder(t.element(find.byType(PatientDetailsPage)));
      expect(screen, isA<PostCallTelemetrySummaryScreen>());
      expect((screen as PostCallTelemetrySummaryScreen).callId,
          isIn(['call-a', 'call-b', 'call-c']));
      expect(screen.recipientName, 'Sarah Johnson');
      restore();
    });

    testWidgets(
        'TC-PDP-049: the dev-only Delete Call History asks first; Cancel '
        'deletes nothing, Delete removes the patient\'s calls and reports the '
        'counts', (t) async {
      routes({
        r'GET /caregivers/10/patients/42$': (_) => json(caregiverView()),
        r'DELETE /calls/patients/500/telemetry$': (_) => json({
              'deletedEvents': 3,
              'deletedCalls': 1,
              'deletedSummaries': 1,
              'deletedTranscriptSegments': 4,
              'deletedTranscriptArchives': 0,
              'deletedRecordingRows': 2,
              'deletedRecordingS3Objects': 2,
            }),
      });
      await pumpPage(t);
      final button = find.text('Delete Call History (Dev)');
      await act(t, () => t.tap(button), frames: 5);
      await act(t, () => t.tap(find.text('Cancel')), frames: 5);
      expect(sent('DELETE', r'/telemetry$'), isEmpty);

      await act(t, () => t.tap(button), frames: 5);
      await act(t, () => t.tap(find.widgetWithText(FilledButton, 'Delete')),
          frames: 30);
      expect(sent('DELETE', r'/calls/patients/500/telemetry$'), hasLength(1));
      expect(
          snack(t),
          'Deleted 3 telemetry event(s) across 1 call(s) in dev mode. Removed '
          '1 summary row(s), 4 transcript segment(s), 0 transcript archive(s), '
          '2 recording row(s), and 2 recording object(s).');
    });

    // ── video calls ──

    Future<Map<String, String>?> startCall(WidgetTester t,
        {required MockUserProvider provider,
        required bool isCaregiver,
        bool finalizesLate = true}) async {
      Map<String, String>? query;
      final router = GoRouter(
        observers: [pushes],
        routes: [
          GoRoute(
            path: '/',
            builder: (_, __) =>
                PatientDetailsPage(patientId: '42', isCaregiver: isCaregiver),
          ),
          GoRoute(
            path: '/video-call-chime',
            builder: (context, state) {
              query = state.uri.queryParameters;
              return Scaffold(
                body: TextButton(
                  onPressed: () => context.pop(),
                  child: const Text('End call'),
                ),
              );
            },
          ),
        ],
      );
      var polls = 0;
      routes({
        r'GET /calls/[^/]+/telemetry$': (_) => json(
            (++polls > 1 || !finalizesLate) ? [{'eventType': 'call_end'}] : []),
      });
      t.view.physicalSize = const Size(1200, 2400);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await http.runWithClient(() async {
        await t.pumpWidget(ChangeNotifierProvider<UserProvider>.value(
          value: provider,
          child: MaterialApp.router(routerConfig: router),
        ));
        for (var i = 0; i < 30; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
      }, () => _globalMockClient);
      await act(t, () => t.tap(find.text('Start Video Call').first));
      if (find.text('End call').evaluate().isNotEmpty) {
        final before = sent('GET', r'/telemetry/my$').length;
        await act(t, () => t.tap(find.text('End call')), frames: 40);
        expect(polls, finalizesLate ? 2 : 1);
        expect(sent('GET', r'/telemetry/my$').length, before + 2,
            reason: 'reload, then the follow-up read');
        expect(find.byType(PatientDetailsPage), findsOneWidget);
      }
      return query;
    }

    testWidgets(
        'TC-PDP-050: a caregiver linked to the patient starts a video call '
        'that returns to this page, which reloads and waits for the call\'s '
        'end', (t) async {
      routes({
        // The page calls the patient's account id from the caregiver link
        // (resolvePatientUserId), never the patient record id.
        r'GET /caregivers/10/patients/42$': (_) => json({
              'link': {'patientUserId': 42}
            }),
        r'GET /caregivers/10/patients$': (_) => json([
              {
                'link': {'patientUserId': 42}
              }
            ]),
      });
      final q = await startCall(t, provider: caregiver(), isCaregiver: true);
      expect(q, isNotNull);
      expect(q!['recipientId'], '42');
      expect(q['userRole'], 'CAREGIVER');
      expect(q['recipientName'], 'Sarah Johnson');
      expect(q['returnPatientDetailsId'], '42');
      expect(q['returnAsCaregiver'], 'true');
      expect(q['callId'], startsWith('chime_call_'));
    });

    testWidgets(
        'TC-PDP-051: a caregiver who may not call the patient is told so and '
        'no call starts', (t) async {
      // The account id is known, but the caregiver isn't linked to it.
      routes({
        r'GET /caregivers/10/patients/42$': (_) => json({
              'link': {'patientUserId': 42}
            }),
      });
      final q = await startCall(t, provider: caregiver(), isCaregiver: true);
      expect(q, isNull);
      expect(snack(t), 'You are not allowed to start this video call.');
    });

    testWidgets(
        'TC-PDP-052: a patient calls their first linked caregiver; with none '
        'linked they are told so', (t) async {
      var linked = <Map<String, dynamic>>[];
      routes({
        r'GET /caregiver-patient-links/patients/1/caregivers$': (_) =>
            json(linked),
      });
      final none = await startCall(t,
          provider: MockUserProvider(), isCaregiver: false);
      expect(none, isNull);
      expect(snack(t), 'No assigned caregiver found for video call.');

      linked = [
        {'caregiverUserId': '9'},
        {'caregiverUserId': 'x'},
      ];
      await t.pumpWidget(const SizedBox());
      final q = await startCall(t,
          provider: MockUserProvider(),
          isCaregiver: false,
          finalizesLate: false);
      expect(q!['recipientId'], '9');
      expect(q['recipientName'], 'Caregiver');
      expect(q['userRole'], 'PATIENT');
      expect(q['returnAsCaregiver'], 'false');
    });

    testWidgets(
        'TC-PDP-053: any other role is told video calling is not available',
        (t) async {
      final q = await startCall(t,
          provider: MockUserProvider(
              mockUser: MockUser(role: 'FAMILY_LINK', patientId: null)),
          isCaregiver: false);
      expect(q, isNull);
      expect(snack(t), 'Video calling is not available for this role.');
    });

    // ── in-home cards, load failure, identity fallbacks ──

    testWidgets(
        'TC-PDP-054: each In-home card opens its screen for this patient, and '
        'only a caregiver gets the Audit Log', (t) async {
      await pumpPage(t);
      await openTab(t, 'In-home');
      final expected = <String, Type>{
        'ADL / IADL management': AdlIadlManagementScreen,
        'Log Behavior': BehavioralIncidentFormScreen,
        'File incident report': IncidentReportWizardScreen,
        'Dashboards': DashboardsScreen,
        'Behavioral history': BehavioralIncidentHistoryScreen,
        'Incident report history': IncidentReportHistoryScreen,
        'Audit Log': AuditLogScreen,
      };
      final ctx = t.element(find.byType(PatientDetailsPage));
      for (final e in expected.entries) {
        await t.scrollUntilVisible(find.text(e.key), 200,
            scrollable: find.byType(Scrollable).last);
        await t.tap(find.text(e.key));
        final route = pushes.takeLast() as MaterialPageRoute;
        await t.pumpAndSettle();
        final screen = route.builder(ctx);
        expect(screen.runtimeType, e.value, reason: e.key);
        final fields = (screen as dynamic);
        expect(fields.clientId, 42, reason: e.key);
        expect(fields.clientName, 'Sarah Johnson', reason: e.key);
      }

      await t.pumpWidget(const SizedBox());
      await pumpPage(t, isCaregiver: false);
      await openTab(t, 'In-home');
      expect(find.text('Dashboards'), findsOneWidget);
      expect(find.text('Audit Log'), findsNothing);
    });

    testWidgets(
        'TC-PDP-055: a patient record that fails to load shows the error with '
        'Retry, and Retry loads the page', (t) async {
      var broken = true;
      routes({
        r'GET /v1/api/patients/42$': (_) => broken
            ? http.Response('not json', 200)
            : json(_sarahProfilePayload()),
      });
      await pumpPage(t);
      expect(find.textContaining('Error loading patient details'), findsOneWidget);
      expect(find.text('Patient Details'), findsOneWidget);
      broken = false;
      await act(t, () => t.tap(find.text('Retry')),
          frames: 30);
      expect(find.textContaining('Error loading patient details'), findsNothing);
      expect(find.textContaining('MRN-2024-0156'), findsWidgets);
    });

    testWidgets(
        'TC-PDP-056: identity falls back across field names: wrapped profile, '
        'conditions, a single diagnosis, plain allergies, maNumber, gender and '
        'contact defaults', (t) async {
      routes({
        r'GET /v1/api/patients/42$': (_) => json({}),
        r'GET /patients/42/family-members$': (_) => json([]),
        r'GET /patients/42/profile$': (_) => json({
              'data': {
                'firstName': 'Alex',
                'lastName': 'Rivera',
                'maNumber': 'MA-77',
                'sex': 'NON_BINARY',
                'phone': '555-0100',
                'dateOfBirth': '1990-01-02',
                'conditions': [
                  {'name': 'Asthma'},
                  {'label': ''},
                  'Gout',
                ],
                'diagnosis': 'COPD',
                'allergies': ['Latex', {'allergen': ''}, {'allergen': 'Nuts'}],
                'address': {'addressLine1': '9 Elm', 'postalCode': '20001'},
              }
            }),
      });
      await pumpPage(t, isCaregiver: false);
      final header = t.widget<PatientHeaderCard>(find.byType(PatientHeaderCard));
      expect(header.fullName, 'Alex Rivera');
      expect(header.mrn, 'MA-77');
      expect(header.sex, 'Non Binary');
      expect(header.diagnoses, ['Asthma', 'Gout', 'COPD']);
      expect(header.allergies, ['Latex', 'Nuts']);
      expect(header.emergencyPhones, ['555-0100']);
      final contact =
          t.widget<EmergencyContactCard>(find.byType(EmergencyContactCard));
      expect(contact.contactName, 'Emergency Contact');
      expect(contact.relationship, 'Primary Contact');
      expect(contact.phone, '555-0100');
    });
  });
}

/// Records pushed routes. [takeLast] removes the newest one before it builds,
/// so a test can check what a tap opens without running that screen.
class _Pushes extends NavigatorObserver {
  final List<Route<dynamic>> routes = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      routes.add(route);

  Route<dynamic> takeLast() {
    final route = routes.removeLast();
    route.navigator?.removeRoute(route);
    return route;
  }
}
