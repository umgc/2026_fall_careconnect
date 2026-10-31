// Gap tests for ComplianceDashboardPage: filter chips and dropdowns (and the
// query strings they send), CSV export actions and failures, refresh, retry,
// and drilling into a subject's checklist and back.
//
// HTTP is replaced with http.runWithClient + MockClient; the clipboard is a
// recording stub on the platform channel; the token comes from
// FlutterSecureStorage.setMockInitialValues.

import 'dart:convert';

import 'package:care_connect_app/features/compliance/presentation/pages/compliance_checklist_page.dart';
import 'package:care_connect_app/features/compliance/presentation/pages/compliance_dashboard_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> _summary(String type, int id, String name,
        {bool blocked = false, int required = 4, int complete = 2}) =>
    {
      'subjectType': type,
      'subjectId': id,
      'subjectName': name,
      'requiredCount': required,
      'missingCount': required - complete,
      'inProgressCount': 0,
      'completeCount': complete,
      'rejectedCount': 0,
      'percentComplete': required == 0 ? 0 : complete * 100 ~/ required,
      'blocked': blocked,
    };

class _Backend {
  final requests = <Uri>[];
  List<Map<String, dynamic>> summaries = [
    _summary('EMPLOYEE', 2, 'Jane Caregiver', blocked: true),
    _summary('CARE_CIRCLE', 7, 'Pat Recipient', required: 0, complete: 0),
  ];
  List<Map<String, dynamic>> missing = [
    {
      'subjectType': 'EMPLOYEE',
      'subjectId': 2,
      'subjectName': 'Jane Caregiver',
      'documentType': 'TAX_FORM',
      'status': 'MISSING',
    },
    {
      'subjectType': 'CARE_CIRCLE',
      'subjectId': 7,
      'subjectName': 'Pat Recipient',
      'documentType': 'CONSENT_FORM',
      'status': 'REJECTED',
    },
  ];
  int dashboardStatus = 200;
  int missingStatus = 200;
  int exportStatus = 200;

  int count(String fragment) =>
      requests.where((u) => u.path.contains(fragment)).length;

  MockClient client() => MockClient((req) async {
        requests.add(req.url);
        final p = req.url.path;
        if (p.contains('/dashboard')) {
          return http.Response(jsonEncode(summaries), dashboardStatus);
        }
        if (p.contains('/missing/export')) {
          return exportStatus == 200
              ? http.Response('Subject,Doc\nJane,TAX_FORM\n', 200)
              : http.Response(
                  jsonEncode({'error': 'Export denied'}), exportStatus);
        }
        if (p.contains('/missing')) {
          return http.Response(jsonEncode(missing), missingStatus);
        }
        if (p.contains('/checklist/')) {
          final parts = p.split('/');
          return http.Response(
              jsonEncode({
                'subjectType': parts[parts.length - 2],
                'subjectId': int.parse(parts.last),
                'subjectName': 'Loaded Subject',
                'items': [],
                'requiredCount': 0,
              }),
              200);
        }
        return http.Response('{}', 404);
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Backend backend;
  final clipboard = <String>[];

  setUp(() {
    backend = _Backend();
    clipboard.clear();
    FlutterSecureStorage.setMockInitialValues({
      'jwt_token': 'test-jwt',
      'token_expiry': '2000000000',
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> open(WidgetTester tester, Future<void> Function() body) async {
    await http.runWithClient(() async {
      await tester
          .pumpWidget(const MaterialApp(home: ComplianceDashboardPage()));
      await tester.pumpAndSettle();
      await body();
    }, () => backend.client());
  }

  Future<void> openMissingTab(WidgetTester tester) async {
    await tester.tap(find.text('Missing Forms'));
    await tester.pumpAndSettle();
  }

  group('overview', () {
    testWidgets('subject chips reload the dashboard with the chosen type',
        (tester) async {
      await open(tester, () async {
        expect(backend.requests.first.queryParameters, isEmpty);

        await tester.tap(find.text('Employees'));
        await tester.pumpAndSettle();
        expect(
            backend.requests.last.queryParameters['subjectType'], 'EMPLOYEE');

        await tester.tap(find.text('Care circles'));
        await tester.pumpAndSettle();
        expect(backend.requests.last.queryParameters['subjectType'],
            'CARE_CIRCLE');

        await tester.tap(find.text('All'));
        await tester.pumpAndSettle();
        expect(backend.requests.last.queryParameters, isEmpty);
      });
    });

    testWidgets('a subject with no required documents shows 0/0',
        (tester) async {
      await open(tester, () async {
        expect(find.text('0/0 complete'), findsOneWidget);
        expect(find.text('2/4 complete · 2 missing'), findsOneWidget);
      });
    });

    testWidgets('blocked-only with nobody blocked shows the empty message',
        (tester) async {
      backend.summaries = [_summary('EMPLOYEE', 2, 'Jane Caregiver')];
      await open(tester, () async {
        await tester.tap(find.text('Blocked only'));
        await tester.pumpAndSettle();
        expect(find.text('No subjects to show'), findsOneWidget);
        expect(find.text('Jane Caregiver'), findsNothing);
      });
    });

    testWidgets('retry after a failed load fetches the dashboard again',
        (tester) async {
      backend.dashboardStatus = 500;
      await open(tester, () async {
        expect(find.textContaining('Something went wrong'), findsOneWidget);
        final before = backend.count('/dashboard');

        backend.dashboardStatus = 200;
        await tester.tap(find.text('Retry'));
        await tester.pumpAndSettle();

        expect(backend.count('/dashboard'), before + 1);
        expect(find.text('Jane Caregiver'), findsOneWidget);
        expect(find.textContaining('Something went wrong'), findsNothing);
      });
    });

    testWidgets('app bar refresh reloads both tabs', (tester) async {
      await open(tester, () async {
        final dash = backend.count('/dashboard');
        final miss = backend.count('/missing');
        await tester.tap(find.byIcon(Icons.refresh));
        await tester.pumpAndSettle();
        expect(backend.count('/dashboard'), dash + 1);
        expect(backend.count('/missing'), miss + 1);
      });
    });

    testWidgets('tapping a card opens its checklist and returning reloads',
        (tester) async {
      await open(tester, () async {
        final dash = backend.count('/dashboard');
        final miss = backend.count('/missing');

        await tester.tap(find.text('Jane Caregiver'));
        await tester.pumpAndSettle();

        expect(find.byType(ComplianceChecklistPage), findsOneWidget);
        expect(find.text('Jane Caregiver - Documents'), findsOneWidget);
        expect(backend.requests.last.path, endsWith('/checklist/EMPLOYEE/2'));
        // The checklist is opened for editing from the coordinator dashboard.
        final page = tester.widget<ComplianceChecklistPage>(
            find.byType(ComplianceChecklistPage));
        expect(page.canEdit, isTrue);

        Navigator.of(tester.element(find.byType(ComplianceChecklistPage)))
            .pop();
        await tester.pumpAndSettle();

        expect(find.byType(ComplianceChecklistPage), findsNothing);
        expect(backend.count('/dashboard'), dash + 1);
        expect(backend.count('/missing'), miss + 1);
      });
    });
  });

  group('missing forms', () {
    testWidgets('subject and document-type dropdowns filter the report',
        (tester) async {
      await open(tester, () async {
        await openMissingTab(tester);

        // Subject dropdown -> Care circles
        await tester.tap(
            find.widgetWithText(DropdownButtonFormField<String>, 'All').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Care circles').last);
        await tester.pumpAndSettle();
        expect(backend.requests.last.path, endsWith('/missing'));
        expect(backend.requests.last.queryParameters['subjectType'],
            'CARE_CIRCLE');

        // Document dropdown offers the types present in the report.
        await tester.tap(find.byType(DropdownButtonFormField<String>).last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Tax Form').last);
        await tester.pumpAndSettle();
        expect(backend.requests.last.queryParameters, {
          'subjectType': 'CARE_CIRCLE',
          'documentType': 'TAX_FORM',
        });
      });
    });

    testWidgets('export sends the active filters and Close dismisses it',
        (tester) async {
      await open(tester, () async {
        await openMissingTab(tester);
        await tester.tap(find.byType(DropdownButtonFormField<String>).last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Tax Form').last);
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('Export as CSV'));
        await tester.pumpAndSettle();

        final export = backend.requests
            .lastWhere((u) => u.path.endsWith('/missing/export'));
        expect(export.queryParameters['documentType'], 'TAX_FORM');
        expect(find.textContaining('Jane,TAX_FORM'), findsOneWidget);

        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        expect(find.text('Missing documents export (CSV)'), findsNothing);
        expect(clipboard, isEmpty);
      });
    });

    testWidgets('Copy CSV puts the report on the clipboard and confirms',
        (tester) async {
      await open(tester, () async {
        await openMissingTab(tester);
        await tester.tap(find.byTooltip('Export as CSV'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Copy CSV'));
        await tester.pumpAndSettle();

        expect(clipboard, ['Subject,Doc\nJane,TAX_FORM\n']);
        expect(find.text('Missing documents export (CSV)'), findsNothing);
        expect(find.text('CSV copied to clipboard'), findsOneWidget);
      });
    });

    testWidgets('a failed export shows the server message', (tester) async {
      backend.exportStatus = 403;
      await open(tester, () async {
        await openMissingTab(tester);
        await tester.tap(find.byTooltip('Export as CSV'));
        await tester.pumpAndSettle();

        expect(find.text('Export failed: Exception: Export denied'),
            findsOneWidget);
        expect(find.byType(AlertDialog), findsNothing);
      });
    });

    testWidgets('a failed load shows an error and Retry reloads the report',
        (tester) async {
      backend.missingStatus = 500;
      await open(tester, () async {
        await openMissingTab(tester);
        expect(find.textContaining('Something went wrong'), findsOneWidget);
        final before = backend.count('/missing');

        backend.missingStatus = 200;
        await tester.tap(find.text('Retry'));
        await tester.pumpAndSettle();

        expect(backend.count('/missing'), before + 1);
        expect(find.text('Tax Form'), findsOneWidget);
      });
    });

    testWidgets('tapping a row opens that subject checklist', (tester) async {
      await open(tester, () async {
        await openMissingTab(tester);
        await tester.tap(find.text('Consent Form'));
        await tester.pumpAndSettle();

        expect(find.byType(ComplianceChecklistPage), findsOneWidget);
        expect(find.text('Pat Recipient - Documents'), findsOneWidget);
        expect(
            backend.requests.last.path, endsWith('/checklist/CARE_CIRCLE/7'));
      });
    });
  });
}
