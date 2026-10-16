// Widget tests for ComplianceDashboardPage.
//
// Covered behaviour:
//   - Overview lists a summary card per subject with progress and counts.
//   - Blocked subjects carry a "Blocked" badge; the blocked-only filter hides
//     compliant subjects.
//   - Missing Forms tab lists outstanding forms with subject context and
//     status chips, and shows an empty state when nothing is outstanding.
//   - Export opens a dialog with the CSV content and a copy action.
//   - Error state renders with a Retry button.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:care_connect_app/features/compliance/presentation/pages/compliance_dashboard_page.dart';

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

Widget _page() => const MaterialApp(home: ComplianceDashboardPage());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    _secureStore.clear();
    _setupSecureStorageStub();
    _secureStore['jwt_token'] = 'test-jwt-token';
    _secureStore['token_expiry'] = '2000000000';
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, null);
  });

  testWidgets('overview shows one summary card per subject with counts',
      (tester) async {
    await http.runWithClient(() async {
      await tester.pumpWidget(_page());
      await tester.pumpAndSettle();

      expect(find.text('Jane Caregiver'), findsOneWidget);
      expect(find.text('Pat Recipient'), findsOneWidget);
      expect(find.text('Employee'), findsOneWidget);
      expect(find.text('Care circle'), findsOneWidget);
      expect(
          find.text('1/9 complete · 6 missing · 1 in progress · 1 rejected'),
          findsOneWidget);
      expect(find.text('4/4 complete'), findsOneWidget);
      // Only the blocked subject carries the badge
      expect(find.text('Blocked'), findsOneWidget);
    }, () => _client());
  });

  testWidgets('blocked-only filter hides compliant subjects', (tester) async {
    await http.runWithClient(() async {
      await tester.pumpWidget(_page());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Blocked only'));
      await tester.pumpAndSettle();

      expect(find.text('Jane Caregiver'), findsOneWidget);
      expect(find.text('Pat Recipient'), findsNothing);
    }, () => _client());
  });

  testWidgets('missing forms tab lists outstanding forms with status chips',
      (tester) async {
    await http.runWithClient(() async {
      await tester.pumpWidget(_page());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Missing Forms'));
      await tester.pumpAndSettle();

      expect(find.text('Tax Form'), findsOneWidget);
      expect(find.text('Background Check'), findsOneWidget);
      expect(find.text('Missing'), findsOneWidget);
      expect(find.text('Rejected'), findsOneWidget);
      expect(find.text('Note: Screening expired'), findsOneWidget);
      expect(find.textContaining('Jane Caregiver · Employee'), findsNWidgets(2));
    }, () => _client());
  });

  testWidgets('missing forms tab shows the empty state when nothing is due',
      (tester) async {
    await http.runWithClient(() async {
      await tester.pumpWidget(_page());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Missing Forms'));
      await tester.pumpAndSettle();

      expect(find.text('No missing or rejected required forms 🎉'),
          findsOneWidget);
    }, () => _client(missing: []));
  });

  testWidgets('export opens a dialog with the CSV content', (tester) async {
    const csv = 'Subject Type,Subject ID,Subject Name\nEMPLOYEE,2,Jane\n';

    await http.runWithClient(() async {
      await tester.pumpWidget(_page());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Missing Forms'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Export as CSV'));
      await tester.pumpAndSettle();

      expect(find.text('Missing documents export (CSV)'), findsOneWidget);
      expect(find.textContaining('EMPLOYEE,2,Jane'), findsOneWidget);
      // ElevatedButton.icon builds a private subclass, so find by label text
      expect(find.text('Copy CSV'), findsOneWidget);
    }, () => _client(exportCsv: csv));
  });

  testWidgets('overview error state renders with Retry', (tester) async {
    await http.runWithClient(() async {
      await tester.pumpWidget(_page());
      await tester.pumpAndSettle();

      expect(find.textContaining('Something went wrong'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Retry'), findsOneWidget);
    }, () => _client(dashboardStatus: 500));
  });
}
