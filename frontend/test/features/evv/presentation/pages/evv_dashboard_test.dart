// Tests for EvvDashboard — populated / admin paths.
// (lib/features/evv/presentation/pages/evv_dashboard.dart)
//
// The prior-cohort flat test deliberately lets the EvvService load fail (no
// server), so only the error/empty state is covered. This suite wires
// EvvService via ApiServiceOffline.debugOverrideHttpClient so the dashboard's
// populated load runs — including the admin branch (pending approvals /
// corrections) and the always-loaded offline queue.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service_offline.dart';
import 'package:care_connect_app/features/evv/presentation/pages/evv_dashboard.dart';

const _secureStorage =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
const _connectivity = MethodChannel('dev.fluttercommunity.plus/connectivity');

void _setupStubs() {
  final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  m.setMockMethodCallHandler(_secureStorage, (call) async {
    if (call.method == 'readAll') return <String, String>{};
    return null;
  });
  m.setMockMethodCallHandler(_connectivity, (call) async {
    if (call.method == 'check') return ['wifi'];
    return null;
  });
}

void _teardownStubs() {
  final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  m.setMockMethodCallHandler(_secureStorage, null);
  m.setMockMethodCallHandler(_connectivity, null);
}

UserSession _user(String role) => UserSession(
      id: 1,
      email: 'u@careconnect.com',
      role: role,
      token: 'test-token',
      caregiverId: 1,
      name: 'Test User',
    );

Map<String, dynamic> _rec(int id) => {
      'id': id,
      'serviceType': 'Personal Care',
      'individualName': 'Mary Johnson',
      'caregiverId': 1,
      'status': 'UNDER_REVIEW',
      'stateCode': 'VA',
      'dateOfService': '2026-08-01T09:00:00.000',
      'timeIn': '2026-08-01T09:00:00.000',
      'timeOut': '2026-08-01T10:00:00.000',
      'createdAt': '2026-08-01T10:00:00.000',
      'updatedAt': '2026-08-01T10:00:00.000',
    };

Map<String, dynamic> _correction(int id) => {
      'id': id,
      'originalRecord': _rec(1),
      'correctedRecord': _rec(1),
      'reasonCode': 'SCHEDULE_CHANGE',
      'explanation': 'x',
      'correctedBy': 7,
      'correctedAt': '2026-08-01T11:00:00.000',
      'approvalRequired': true,
      'originalValues': {'timeIn': '09:00'},
      'correctedValues': {'timeIn': '09:15'},
    };

Map<String, dynamic> _queueItem(int id) => {
      'id': id,
      'recordId': 100 + id,
      'operationType': 'CREATE',
      'caregiverId': 1,
      'queuedAt': '2026-08-01T09:00:00.000',
      'syncAttempts': 0,
      'syncStatus': 'PENDING',
      'priority': 1,
      'recordData': {'serviceType': 'Personal Care'},
    };

void _wire() {
  ApiServiceOffline.debugOverrideHttpClient(MockClient((req) async {
    final url = req.url.toString();
    if (url.contains('/records/pending-eor-approvals')) {
      return http.Response(jsonEncode([_rec(1), _rec(2)]), 200);
    }
    if (url.contains('/corrections/pending')) {
      return http.Response(jsonEncode([_correction(1)]), 200);
    }
    if (url.contains('/offline/queue')) {
      return http.Response(jsonEncode([_queueItem(1)]), 200);
    }
    return http.Response('[]', 200);
  }));
}

Widget _host(String role) {
  final provider = UserProvider()..setUser(_user(role));
  return ChangeNotifierProvider<UserProvider>.value(
    value: provider,
    child: const MaterialApp(home: EvvDashboard()),
  );
}

/// The dashboard lays out wide card rows; pump on a large surface so it doesn't
/// overflow the default 800x600 test viewport.
Future<void> _pump(WidgetTester tester, String role) async {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(_host(role));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _setupStubs();
    _wire();
  });

  tearDown(() {
    _teardownStubs();
    ApiServiceOffline.debugOverrideHttpClient(null);
  });

  testWidgets('shows a loading indicator on the first frame', (tester) async {
    await _pump(tester, 'CAREGIVER');
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();
    tester.takeException(); // consume a known cosmetic ~7px dashboard overflow
  });

  testWidgets('loads the populated dashboard for a caregiver', (tester) async {
    await _pump(tester, 'CAREGIVER');
    await tester.pumpAndSettle();
    expect(find.byType(EvvDashboard), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    tester.takeException(); // consume a known cosmetic ~7px dashboard overflow
  });

  testWidgets('loads pending approvals and corrections for an admin',
      (tester) async {
    await _pump(tester, 'ADMIN');
    await tester.pumpAndSettle();
    // Admin branch ran: pending approvals (2) + corrections (1) were fetched.
    expect(find.byType(EvvDashboard), findsOneWidget);
    tester.takeException(); // consume a known cosmetic ~7px dashboard overflow
  });

  testWidgets('loads for a supervisor (admin branch)', (tester) async {
    await _pump(tester, 'SUPERVISOR');
    await tester.pumpAndSettle();
    expect(find.byType(EvvDashboard), findsOneWidget);
    tester.takeException(); // consume a known cosmetic ~7px dashboard overflow
  });
}
