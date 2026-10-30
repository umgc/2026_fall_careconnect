// Page-title tests for ComplianceDashboardPage (lib/features/compliance/presentation/pages/compliance_dashboard_page.dart).
// Setup copied from compliance_dashboard_page_test.dart; adds the page-title
// checks (WCAG 2.4.2) for this PR's TitledMaterialPageRoute changes.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:care_connect_app/features/compliance/presentation/pages/compliance_dashboard_page.dart';
import '../../../../helpers/titled_route_probe.dart';

const MethodChannel _secureStorageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

final Map<String, String?> _secureStore = {};

void _setupSecureStorageStub() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_secureStorageChannel, (call) async {
    switch (call.method) {
      case 'read':
        return _secureStore[call.arguments['key'] as String];
      case 'write':
        _secureStore[call.arguments['key'] as String] =
            call.arguments['value'] as String?;
        return null;
      default:
        return null;
    }
  });
}

List<Map<String, dynamic>> _summaries() => [
      {
        'subjectType': 'EMPLOYEE',
        'subjectId': 2,
        'subjectName': 'Jane Caregiver',
        'requiredCount': 9,
        'missingCount': 6,
        'inProgressCount': 1,
        'completeCount': 1,
        'rejectedCount': 1,
        'percentComplete': 11,
        'blocked': true,
      },
      {
        'subjectType': 'CARE_CIRCLE',
        'subjectId': 7,
        'subjectName': 'Pat Recipient',
        'requiredCount': 4,
        'missingCount': 0,
        'inProgressCount': 0,
        'completeCount': 4,
        'rejectedCount': 0,
        'percentComplete': 100,
        'blocked': false,
      },
    ];

List<Map<String, dynamic>> _missingRows() => [
      {
        'subjectType': 'EMPLOYEE',
        'subjectId': 2,
        'subjectName': 'Jane Caregiver',
        'documentType': 'TAX_FORM',
        'status': 'MISSING',
      },
      {
        'subjectType': 'EMPLOYEE',
        'subjectId': 2,
        'subjectName': 'Jane Caregiver',
        'documentType': 'BACKGROUND_CHECK',
        'status': 'REJECTED',
        'notes': 'Screening expired',
      },
    ];

MockClient _client({
  List<Map<String, dynamic>>? summaries,
  List<Map<String, dynamic>>? missing,
  String exportCsv = 'Subject Type,Subject ID\n',
  int dashboardStatus = 200,
}) {
  return MockClient((request) async {
    final path = request.url.path;
    if (path.contains('/dashboard')) {
      if (dashboardStatus != 200) {
        return http.Response(jsonEncode({'error': 'boom'}), dashboardStatus);
      }
      return http.Response(jsonEncode(summaries ?? _summaries()), 200);
    }
    if (path.contains('/missing/export')) {
      return http.Response(exportCsv, 200);
    }
    if (path.contains('/missing')) {
      return http.Response(jsonEncode(missing ?? _missingRows()), 200);
    }
    return http.Response('{}', 404);
  });
}

Widget _page() =>
    MaterialApp(navigatorObservers: [probe], home: ComplianceDashboardPage());

TitledRouteProbe probe = TitledRouteProbe();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    probe = TitledRouteProbe();
    _secureStore.clear();
    _setupSecureStorageStub();
    _secureStore['jwt_token'] = 'test-jwt-token';
    _secureStore['token_expiry'] = '2000000000';
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, null);
  });

  testWidgets('opening a subject pushes a page titled "Compliance Checklist"',
      (tester) async {
    await http.runWithClient(() async {
      await tester.pumpWidget(_page());
      await tester.pumpAndSettle();
      expect(await probe.tapAndReadTitle(tester, find.text('Jane Caregiver')),
          'Compliance Checklist');
    }, () => _client());
  });
}
