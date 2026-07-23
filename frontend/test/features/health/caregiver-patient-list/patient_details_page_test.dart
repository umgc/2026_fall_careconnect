// Tests for PatientDetailsPage
// (lib/features/health/caregiver-patient-list/page/patient_details_page.dart).

import 'dart:convert';

import 'package:care_connect_app/features/health/caregiver-patient-list/page/patient_details_page.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../mock_user_provider.dart';

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
    if (path.contains('/search') || path.contains('/check-in') ||
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
  });

  // ───────────────────── constructor tests ─────────────────────
  group('PatientDetailsPage – constructor', () {
    test('creates with required patientId and default isCaregiver', () {
      const page = PatientDetailsPage(patientId: '123');
      expect(page.patientId, '123');
      expect(page.isCaregiver, isFalse);
    });

    test('creates with isCaregiver true', () {
      const page = PatientDetailsPage(patientId: '456', isCaregiver: true);
      expect(page.patientId, '456');
      expect(page.isCaregiver, isTrue);
    });

    test('isCaregiver defaults to false', () {
      const page = PatientDetailsPage(patientId: '789');
      expect(page.isCaregiver, isFalse);
    });

    test('is a StatefulWidget', () {
      const page = PatientDetailsPage(patientId: '1');
      expect(page, isA<StatefulWidget>());
    });

    test('createState returns non-null state', () {
      const page = PatientDetailsPage(patientId: '1');
      final state = page.createState();
      expect(state, isNotNull);
    });

    test('patientId stores various string values', () {
      const page1 = PatientDetailsPage(patientId: 'abc');
      expect(page1.patientId, 'abc');
      const page2 = PatientDetailsPage(patientId: '0');
      expect(page2.patientId, '0');
      const page3 = PatientDetailsPage(patientId: '');
      expect(page3.patientId, '');
    });

    test('isCaregiver explicitly set to false', () {
      const page = PatientDetailsPage(patientId: '1', isCaregiver: false);
      expect(page.isCaregiver, isFalse);
    });

    test('can be const-constructed', () {
      const page = PatientDetailsPage(patientId: '1');
      expect(page, isA<PatientDetailsPage>());
    });

    test('key parameter can be provided', () {
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
    testWidgets('renders PatientDetailsPage widget',
        (WidgetTester tester) async {
      await pumpReady(tester, buildTestWidget());
      expect(find.byType(PatientDetailsPage), findsOneWidget);
    });

    testWidgets('renders Scaffold', (WidgetTester tester) async {
      await pumpReady(tester, buildTestWidget());
      expect(find.byType(Scaffold), findsWidgets);
    });

    testWidgets('renders DefaultTabController',
        (WidgetTester tester) async {
      await pumpReady(tester, buildTestWidget());
      expect(find.byType(DefaultTabController), findsOneWidget);
    });

    testWidgets('renders AppBar', (WidgetTester tester) async {
      await pumpReady(tester, buildTestWidget());
      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('AppBar shows patient name Sarah Johnson',
        (WidgetTester tester) async {
      await pumpReady(tester, buildTestWidget());
      expect(find.text('Sarah Johnson'), findsWidgets);
    });

    testWidgets('AppBar shows MRN in subtitle', (WidgetTester tester) async {
      await pumpReady(tester, buildTestWidget());
      expect(find.textContaining('MRN-2024-0156'), findsWidgets);
    });

    testWidgets('AppBar subtitle contains Patient Details',
        (WidgetTester tester) async {
      await pumpReady(tester, buildTestWidget());
      expect(find.textContaining('Patient Details'), findsOneWidget);
    });

    testWidgets('renders all five tab labels', (WidgetTester tester) async {
      await pumpReady(tester, buildTestWidget());
      expect(find.text('Info'), findsOneWidget);
      expect(find.text('Mood'), findsOneWidget);
      expect(find.text('Health'), findsOneWidget);
      expect(find.text('In-home'), findsOneWidget);
      expect(find.text('Virtual Check-In'), findsOneWidget);
    });

    testWidgets('renders tab icons', (WidgetTester tester) async {
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

    testWidgets('renders TabBar', (WidgetTester tester) async {
      await pumpReady(tester, buildTestWidget());
      expect(find.byType(TabBar), findsOneWidget);
    });

    testWidgets('renders diagnoses in header', (WidgetTester tester) async {
      await pumpReady(tester, buildTestWidget());
      expect(find.text('Type 2 Diabetes'), findsOneWidget);
      expect(find.text('Hypertension'), findsOneWidget);
      expect(find.text('Chronic Fatigue Syndrome'), findsOneWidget);
    });

    testWidgets('renders allergies in header', (WidgetTester tester) async {
      await pumpReady(tester, buildTestWidget());
      // Allergies are rendered as "allergen (severity)" when severity is present.
      expect(find.textContaining('Penicillin'), findsOneWidget);
      expect(find.textContaining('Shellfish'), findsOneWidget);
    });

    testWidgets('Info tab shows contact phone by default',
        (WidgetTester tester) async {
      await pumpReady(tester, buildTestWidget());
      expect(find.text('(555) 123-4567'), findsWidgets);
    });

    testWidgets('Info tab shows email', (WidgetTester tester) async {
      await pumpReady(tester, buildTestWidget());
      expect(find.text('sarah.johnson@email.com'), findsOneWidget);
    });

    testWidgets('Info tab shows emergency contact name',
        (WidgetTester tester) async {
      await pumpReady(tester, buildTestWidget());
      expect(find.text('Michael Johnson'), findsOneWidget);
    });

    testWidgets('Info tab shows emergency contact relationship',
        (WidgetTester tester) async {
      await pumpReady(tester, buildTestWidget());
      expect(find.text('Spouse'), findsOneWidget);
    });

    testWidgets('Info tab shows emergency contact phone',
        (WidgetTester tester) async {
      await pumpReady(tester, buildTestWidget());
      expect(find.text('(555) 987-6543'), findsWidgets);
    });

    testWidgets('builds with isCaregiver true', (WidgetTester tester) async {
      await pumpReady(tester, buildTestWidget(isCaregiver: true));
      expect(find.text('Sarah Johnson'), findsWidgets);
    });

    testWidgets('builds with isCaregiver false', (WidgetTester tester) async {
      await pumpReady(tester, buildTestWidget(isCaregiver: false));
      expect(find.text('Sarah Johnson'), findsWidgets);
    });

    testWidgets('valid numeric patientId renders page',
        (WidgetTester tester) async {
      await pumpReady(tester, buildTestWidget(patientId: '42'));
      expect(find.byType(PatientDetailsPage), findsOneWidget);
    });

    testWidgets('builds with patient role UserProvider',
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

    testWidgets('invalid patientId shows error state',
        (WidgetTester tester) async {
      await pumpReady(tester, buildTestWidget(patientId: 'invalid_id'));
      expect(find.byType(PatientDetailsPage), findsOneWidget);
      expect(find.textContaining('Invalid patient ID'), findsWidgets);
    });

    testWidgets('builds with empty patientId shows error',
        (WidgetTester tester) async {
      await pumpReady(tester, buildTestWidget(patientId: ''));
      expect(find.byType(PatientDetailsPage), findsOneWidget);
      expect(find.textContaining('Invalid patient ID'), findsWidgets);
    });
  });
}
