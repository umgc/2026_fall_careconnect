// Gap tests for ComplianceChecklistPage: the change-status dialog (validation,
// request body, success and failure), the status-history sheet, and the
// per-row popup menu that the existing suite does not exercise.
//
// HTTP is replaced with http.runWithClient + MockClient, and the auth token
// comes from FlutterSecureStorage.setMockInitialValues, so nothing goes over
// the network.

import 'dart:convert';

import 'package:care_connect_app/features/compliance/presentation/pages/compliance_checklist_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> _checklist() => {
      'subjectType': 'CARE_CIRCLE',
      'subjectId': 7,
      'subjectName': 'Pat Recipient',
      'requiredCount': 2,
      'missingCount': 1,
      'inProgressCount': 0,
      'completeCount': 1,
      'rejectedCount': 0,
      'percentComplete': 50,
      'items': [
        {
          'documentType': 'CONSENT_FORM',
          'status': 'MISSING',
          'tracked': true,
          'fileCount': 0,
          'hasStructuredEntry': false,
        },
        {
          'documentType': 'CARE_PLAN',
          'status': 'COMPLETE',
          'tracked': true,
          'fileCount': 1,
          'hasStructuredEntry': false,
          'latestFilename': 'plan.pdf',
        },
      ],
    };

List<Map<String, dynamic>> _history() => [
      {
        'documentType': 'CONSENT_FORM',
        'previousStatus': 'MISSING',
        'newStatus': 'COMPLETE',
        'changedBy': 5,
        'changedByName': 'Alice Test',
        'reason': 'Signed copy received',
        'changedAt': '2026-03-04T09:05:00',
      },
      {
        'documentType': 'CARE_PLAN',
        'newStatus': 'REJECTED',
        'changedBy': 9,
        'reason': 'Wrong patient',
      },
    ];

class _Recorder {
  final requests = <http.Request>[];
  int status = 200;
  int historyStatus = 200;
  int putStatus = 200;
  List<Map<String, dynamic>> history = _history();

  MockClient client() => MockClient((req) async {
        requests.add(req);
        final path = req.url.path;
        if (req.method == 'PUT') {
          return putStatus == 200
              ? http.Response(
                  jsonEncode({
                    'documentType': 'CONSENT_FORM',
                    'status': 'COMPLETE',
                  }),
                  200)
              : http.Response(jsonEncode({'error': 'Not allowed'}), putStatus);
        }
        if (path.contains('/history/')) {
          return historyStatus == 200
              ? http.Response(jsonEncode(history), 200)
              : http.Response('oops', historyStatus);
        }
        if (path.contains('/checklist/')) {
          return http.Response(jsonEncode(_checklist()), status);
        }
        return http.Response('{}', 404);
      });

  int get checklistLoads =>
      requests.where((r) => r.url.path.contains('/checklist/')).length;
}

void main() {
  late _Recorder rec;

  setUp(() {
    rec = _Recorder();
    FlutterSecureStorage.setMockInitialValues({
      'jwt_token': 'test-jwt',
      'token_expiry': '2000000000',
    });
  });

  Future<void> open(WidgetTester tester,
      {bool canEdit = true,
      String? name = 'Pat Recipient',
      required Future<void> Function() body}) async {
    await http.runWithClient(() async {
      await tester.pumpWidget(MaterialApp(
        home: ComplianceChecklistPage(
          subjectType: 'CARE_CIRCLE',
          subjectId: 7,
          subjectName: name,
          canEdit: canEdit,
        ),
      ));
      await tester.pumpAndSettle();
      await body();
    }, () => rec.client());
  }

  testWidgets('title falls back to the checklist subject name', (tester) async {
    await open(tester, name: null, body: () async {
      expect(find.text('Pat Recipient - Documents'), findsOneWidget);
      expect(find.text('Care circle documents'), findsOneWidget);
    });
  });

  testWidgets('title is generic while the checklist is still loading',
      (tester) async {
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(
        home: ComplianceChecklistPage(subjectType: 'EMPLOYEE', subjectId: 7),
      ));
      expect(find.text('Checklist - Documents'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pumpAndSettle();
    }, () => rec.client());
  });

  testWidgets('refresh button reloads the checklist', (tester) async {
    await open(tester, body: () async {
      expect(rec.checklistLoads, 1);
      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pumpAndSettle();
      expect(rec.checklistLoads, 2);
    });
  });

  testWidgets('read-only users get no popup menu and tapping a row is inert',
      (tester) async {
    await open(tester, canEdit: false, body: () async {
      expect(find.byType(PopupMenuButton<String>), findsNothing);
      await tester.tap(find.text('Consent Form'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });
  });

  group('change status dialog', () {
    testWidgets('requires a reason before saving', (tester) async {
      await open(tester, body: () async {
        await tester.tap(find.text('Consent Form'));
        await tester.pumpAndSettle();
        expect(find.text('Update Consent Form'), findsOneWidget);

        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();

        expect(find.text('A reason is required for the audit trail'),
            findsOneWidget);
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(rec.requests.where((r) => r.method == 'PUT'), isEmpty);
      });
    });

    testWidgets('cancel closes the dialog without calling the API',
        (tester) async {
      await open(tester, body: () async {
        await tester.tap(find.text('Consent Form'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsNothing);
        expect(rec.requests.where((r) => r.method == 'PUT'), isEmpty);
      });
    });

    testWidgets('saves the chosen status and reason, then reloads',
        (tester) async {
      await open(tester, body: () async {
        await tester.tap(find.text('Consent Form'));
        await tester.pumpAndSettle();

        // Open the status dropdown and pick "Complete".
        await tester.tap(find.byType(DropdownButtonFormField<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Complete').last);
        await tester.pumpAndSettle();

        await tester.enterText(
            find.byType(TextFormField), '  Signed copy received  ');
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();

        final put = rec.requests.singleWhere((r) => r.method == 'PUT');
        expect(put.url.path, endsWith('/status'));
        expect(jsonDecode(put.body), {
          'subjectType': 'CARE_CIRCLE',
          'subjectId': 7,
          'documentType': 'CONSENT_FORM',
          'status': 'COMPLETE',
          'reason': 'Signed copy received',
        });
        expect(find.text('Status updated'), findsOneWidget);
        expect(rec.checklistLoads, 2);
      });
    });

    testWidgets('shows the server error when the update is rejected',
        (tester) async {
      rec.putStatus = 403;
      await open(tester, body: () async {
        await tester.tap(find.text('Consent Form'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextFormField), 'Because');
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();

        expect(find.text('Failed to update status: Exception: Not allowed'),
            findsOneWidget);
        expect(find.text('Status updated'), findsNothing);
        expect(rec.checklistLoads, 1);
      });
    });
  });

  group('history', () {
    testWidgets('app bar button lists every status change', (tester) async {
      await open(tester, body: () async {
        await tester.tap(find.byTooltip('Status change history'));
        await tester.pumpAndSettle();

        final req = rec.requests.last;
        expect(req.url.path, endsWith('/history/CARE_CIRCLE/7'));
        expect(req.url.queryParameters.containsKey('documentType'), isFalse);

        expect(find.text('Status change history'), findsWidgets);
        expect(find.text('Consent Form: Missing → Complete'), findsOneWidget);
        expect(find.text('Reason: Signed copy received'), findsOneWidget);
        expect(find.text('By Alice Test on 2026-03-04 09:05'), findsOneWidget);
        // No previous status and no name: fall back to the documented labels.
        expect(find.text('Care Plan: Untracked → Rejected'), findsOneWidget);
        expect(find.text('By user #9'), findsOneWidget);
      });
    });

    testWidgets('shows an empty message when nothing was recorded',
        (tester) async {
      rec.history = [];
      await open(tester, body: () async {
        await tester.tap(find.byTooltip('Status change history'));
        await tester.pumpAndSettle();
        expect(find.text('No status changes recorded yet'), findsOneWidget);
      });
    });

    testWidgets('reports a snackbar when history cannot be loaded',
        (tester) async {
      rec.historyStatus = 500;
      await open(tester, body: () async {
        await tester.tap(find.byTooltip('Status change history'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Failed to load history'), findsOneWidget);
        expect(find.text('No status changes recorded yet'), findsNothing);
      });
    });

    testWidgets('row menu "View history" scopes the request to that document',
        (tester) async {
      await open(tester, body: () async {
        await tester.tap(find.byType(PopupMenuButton<String>).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('View history'));
        await tester.pumpAndSettle();

        expect(rec.requests.last.url.queryParameters['documentType'],
            'CONSENT_FORM');
        expect(find.text('Consent Form history'), findsOneWidget);
      });
    });

    testWidgets('row menu "Change status..." opens the update dialog',
        (tester) async {
      await open(tester, body: () async {
        await tester.tap(find.byType(PopupMenuButton<String>).last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Change status...'));
        await tester.pumpAndSettle();

        expect(find.text('Update Care Plan'), findsOneWidget);
        expect(find.text('Reason (required)'), findsOneWidget);
      });
    });
  });
}
