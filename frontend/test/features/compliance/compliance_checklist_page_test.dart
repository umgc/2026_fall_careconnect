// Widget tests for ComplianceChecklistPage.
//
// Covered behaviour:
//   - Required-document checklist renders one row per item with distinct
//     status chips (Missing / In Progress / Complete / Rejected).
//   - Uploaded files and digitized records are surfaced as evidence text.
//   - Rejection reason (notes) is shown on the item.
//   - Error state renders with a Retry button.
//   - canEdit=false hides the status-change affordances.
//   - Change-status dialog enforces a reason and submits a PUT; the checklist
//     reloads and a confirmation snackbar appears.
//
// HTTP intercepted via http.runWithClient + MockClient; auth headers via a
// FlutterSecureStorage MethodChannel stub (repo-standard pattern).

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:care_connect_app/features/compliance/presentation/pages/compliance_checklist_page.dart';

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

Map<String, dynamic> _checklistJson() => {
      'subjectType': 'CARE_CIRCLE',
      'subjectId': 7,
      'subjectName': 'Pat Recipient',
      'items': [
        {
          'documentType': 'CONSENT_FORM',
          'status': 'IN_PROGRESS',
          'tracked': true,
          'fileCount': 2,
          'hasStructuredEntry': false,
          'latestFilename': 'consent-signed.pdf',
        },
        {
          'documentType': 'INSURANCE_DOCUMENT',
          'status': 'COMPLETE',
          'tracked': true,
          'fileCount': 1,
          'hasStructuredEntry': true,
        },
        {
          'documentType': 'CARE_PLAN',
          'status': 'MISSING',
          'tracked': false,
          'fileCount': 0,
          'hasStructuredEntry': false,
        },
        {
          'documentType': 'EMERGENCY_CONTACT',
          'status': 'REJECTED',
          'tracked': true,
          'fileCount': 1,
          'hasStructuredEntry': false,
          'notes': 'Phone number unreadable',
        },
      ],
      'requiredCount': 4,
      'missingCount': 1,
      'inProgressCount': 1,
      'completeCount': 1,
      'rejectedCount': 1,
      'percentComplete': 25,
    };

Widget _page({bool canEdit = true}) => const MaterialApp(
      home: ComplianceChecklistPage(
        subjectType: 'CARE_CIRCLE',
        subjectId: 7,
        subjectName: 'Pat Recipient',
        canEdit: true,
      ),
    );

Widget _pageReadOnly() => const MaterialApp(
      home: ComplianceChecklistPage(
        subjectType: 'CARE_CIRCLE',
        subjectId: 7,
        subjectName: 'Pat Recipient',
        canEdit: false,
      ),
    );

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

  testWidgets('renders every required document with its distinct status',
      (tester) async {
    final client = MockClient(
        (request) async => http.Response(jsonEncode(_checklistJson()), 200));

    await http.runWithClient(() async {
      await tester.pumpWidget(_page());
      await tester.pumpAndSettle();

      // One row per required document
      expect(find.text('Consent Form'), findsOneWidget);
      expect(find.text('Insurance Document'), findsOneWidget);
      expect(find.text('Care Plan'), findsOneWidget);
      expect(find.text('Emergency Contact'), findsOneWidget);

      // Distinct status chips for all four states
      expect(find.text('In Progress'), findsOneWidget);
      expect(find.text('Complete'), findsOneWidget);
      expect(find.text('Missing'), findsOneWidget);
      expect(find.text('Rejected'), findsOneWidget);

      // Summary header
      expect(find.text('1 of 4 required documents complete (25%)'),
          findsOneWidget);
      expect(find.text('Care circle documents'), findsOneWidget);
    }, () => client);
  });

  testWidgets('surfaces uploaded files and digitized records as evidence',
      (tester) async {
    final client = MockClient(
        (request) async => http.Response(jsonEncode(_checklistJson()), 200));

    await http.runWithClient(() async {
      await tester.pumpWidget(_page());
      await tester.pumpAndSettle();

      // Uploaded-only evidence
      expect(find.text('2 uploaded files'), findsOneWidget);
      expect(find.text('Latest: consent-signed.pdf'), findsOneWidget);
      // Uploaded + digitized structured record
      expect(find.text('1 uploaded file · digitized record'), findsOneWidget);
      // Nothing on file
      expect(find.text('No documents on file'), findsOneWidget);
      // Rejection reason surfaced
      expect(find.text('Note: Phone number unreadable'), findsOneWidget);
    }, () => client);
  });

  testWidgets('error state shows the message and a Retry button',
      (tester) async {
    final client = MockClient((request) async =>
        http.Response(jsonEncode({'error': 'No access to this patient'}), 403));

    await http.runWithClient(() async {
      await tester.pumpWidget(_page());
      await tester.pumpAndSettle();

      expect(find.textContaining('Could not load checklist'), findsOneWidget);
      expect(find.textContaining('No access to this patient'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Retry'), findsOneWidget);
    }, () => client);
  });

  testWidgets('read-only mode hides the change-status affordances',
      (tester) async {
    final client = MockClient(
        (request) async => http.Response(jsonEncode(_checklistJson()), 200));

    await http.runWithClient(() async {
      await tester.pumpWidget(_pageReadOnly());
      await tester.pumpAndSettle();

      expect(find.byType(PopupMenuButton<String>), findsNothing);

      // Tapping an item must not open the change-status dialog
      await tester.tap(find.text('Care Plan'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    }, () => client);
  });

  testWidgets(
      'change-status dialog requires a reason, submits PUT and reloads',
      (tester) async {
    String? putBody;
    var checklistLoads = 0;
    final client = MockClient((request) async {
      if (request.method == 'PUT' && request.url.path.contains('/status')) {
        putBody = request.body;
        return http.Response(
            jsonEncode({'documentType': 'CARE_PLAN', 'status': 'COMPLETE'}),
            200);
      }
      checklistLoads++;
      return http.Response(jsonEncode(_checklistJson()), 200);
    });

    await http.runWithClient(() async {
      await tester.pumpWidget(_page());
      await tester.pumpAndSettle();
      expect(checklistLoads, 1);

      // Open the dialog by tapping an editable item
      await tester.tap(find.text('Care Plan'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Reason (required)'), findsOneWidget);

      // Saving without a reason is blocked by validation
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pumpAndSettle();
      expect(find.text('A reason is required for the audit trail'),
          findsOneWidget);
      expect(putBody, isNull);

      // Pick a new status and provide the mandatory reason
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Complete').last);
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byType(TextFormField), 'Verified with the family');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pumpAndSettle();

      // PUT carried the transition + reason; checklist reloaded; snackbar shown
      expect(putBody, isNotNull);
      final body = jsonDecode(putBody!) as Map<String, dynamic>;
      expect(body['subjectType'], 'CARE_CIRCLE');
      expect(body['subjectId'], 7);
      expect(body['documentType'], 'CARE_PLAN');
      expect(body['status'], 'COMPLETE');
      expect(body['reason'], 'Verified with the family');
      expect(checklistLoads, 2);
      expect(find.text('Status updated'), findsOneWidget);
    }, () => client);
  });
}
