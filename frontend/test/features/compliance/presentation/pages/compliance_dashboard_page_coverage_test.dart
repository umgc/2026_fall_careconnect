// Coverage tests for ComplianceDashboardPage
// (lib/features/compliance/presentation/pages/compliance_dashboard_page.dart):
// the subject filter chips, refresh, missing-forms load and export failures,
// copying the CSV, the missing-forms filters and opening a checklist from a
// missing row.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:care_connect_app/features/compliance/presentation/pages/compliance_checklist_page.dart';
import 'package:care_connect_app/features/compliance/presentation/pages/compliance_dashboard_page.dart';

const MethodChannel _secureStorage =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

final _summaries = [
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
];

final _missing = [
  {
    'subjectType': 'EMPLOYEE',
    'subjectId': 2,
    'subjectName': 'Jane Caregiver',
    'documentType': 'TAX_FORM',
    'status': 'MISSING',
  },
];

class _Backend {
  int missingStatus = 200;
  int exportStatus = 200;
  final List<Uri> calls = [];

  Future<http.Response> handle(http.Request r) async {
    calls.add(r.url);
    final p = r.url.path;
    if (p.contains('/dashboard')) {
      return http.Response(jsonEncode(_summaries), 200);
    }
    if (p.contains('/missing/export')) {
      return exportStatus == 200
          ? http.Response('Subject,Doc\nJane,TAX_FORM\n', 200)
          : http.Response(jsonEncode({'error': 'export broke'}), exportStatus);
    }
    if (p.contains('/missing')) {
      return missingStatus == 200
          ? http.Response(jsonEncode(_missing), 200)
          : http.Response(jsonEncode({'error': 'missing broke'}), 500);
    }
    return http.Response(
        jsonEncode({
          'subjectType': 'EMPLOYEE',
          'subjectId': 2,
          'subjectName': 'Jane Caregiver',
          'items': [],
          'requiredCount': 0,
          'missingCount': 0,
          'inProgressCount': 0,
          'completeCount': 0,
          'rejectedCount': 0,
          'percentComplete': 0,
        }),
        200);
  }
}

void main() {
  late _Backend backend;

  setUp(() {
    backend = _Backend();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorage, (call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorage, null);
  });

  Future<void> run(WidgetTester tester, Future<void> Function() body) =>
      http.runWithClient(() async {
        await tester.pumpWidget(
            const MaterialApp(home: ComplianceDashboardPage()));
        await tester.pumpAndSettle();
        await body();
      }, () => MockClient(backend.handle));

  int count(String fragment) =>
      backend.calls.where((u) => u.path.contains(fragment)).length;

  testWidgets('subject chips filter the overview and refresh reloads',
      (tester) async {
    await run(tester, () async {
      expect(find.text('Employees'), findsOneWidget);
      expect(find.text('Care circles'), findsOneWidget);
      await tester.tap(find.text('Employees'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pumpAndSettle();
    });
    expect(count('/dashboard'), 3);
    expect(
        backend.calls.where((u) =>
            u.path.contains('/dashboard') &&
            u.queryParameters['subjectType'] == 'EMPLOYEE'),
        isNotEmpty);
  });

  testWidgets('missing-forms load error is shown', (tester) async {
    backend.missingStatus = 500;
    await run(tester, () async {
      await tester.tap(find.text('Missing Forms'));
      await tester.pumpAndSettle();
    });
    expect(find.textContaining('missing broke'), findsOneWidget);
  });

  testWidgets('a failed export shows a snackbar', (tester) async {
    backend.exportStatus = 500;
    await run(tester, () async {
      await tester.tap(find.text('Missing Forms'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Export as CSV'));
      await tester.pumpAndSettle();
    });
    expect(find.textContaining('Export failed'), findsOneWidget);
  });

  testWidgets('Copy CSV copies and closes the dialog', (tester) async {
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await run(tester, () async {
      await tester.tap(find.text('Missing Forms'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Export as CSV'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy CSV'));
      await tester.pumpAndSettle();
    });
    expect(find.text('Missing documents export (CSV)'), findsNothing);
    expect(find.text('CSV copied to clipboard'), findsOneWidget);
    expect(copied, contains('TAX_FORM'));
  });

  testWidgets('missing-forms filters reload with the chosen values',
      (tester) async {
    await run(tester, () async {
      await tester.tap(find.text('Missing Forms'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Care circles').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<String>).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tax Form').last);
      await tester.pumpAndSettle();
    });
    final last = backend.calls.lastWhere((u) => u.path.endsWith('/missing'));
    expect(last.queryParameters['subjectType'], 'CARE_CIRCLE');
    expect(last.queryParameters['documentType'], 'TAX_FORM');
  });

  testWidgets('tapping a missing row opens the checklist', (tester) async {
    await run(tester, () async {
      await tester.tap(find.text('Missing Forms'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tax Form').last);
      await tester.pumpAndSettle();
    });
    expect(find.byType(ComplianceChecklistPage), findsOneWidget);
  });
}
