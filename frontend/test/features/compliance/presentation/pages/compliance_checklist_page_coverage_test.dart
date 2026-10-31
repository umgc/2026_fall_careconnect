// Coverage tests for ComplianceChecklistPage
// (lib/features/compliance/presentation/pages/compliance_checklist_page.dart):
// the status-history bottom sheet (all documents and per item, empty and
// populated, load failure), the per-item popup menu, cancelling the
// change-status dialog and a failed status update.

import 'dart:convert';

import 'package:care_connect_app/features/compliance/presentation/pages/compliance_checklist_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const MethodChannel _secureStorage =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

Map<String, dynamic> _checklist() => {
      'subjectType': 'EMPLOYEE',
      'subjectId': 3,
      'subjectName': 'Erin Employee',
      'items': [
        {
          'documentType': 'CARE_PLAN',
          'status': 'MISSING',
          'tracked': false,
          'fileCount': 0,
          'hasStructuredEntry': false,
        },
      ],
      'requiredCount': 1,
      'missingCount': 1,
      'inProgressCount': 0,
      'completeCount': 0,
      'rejectedCount': 0,
      'percentComplete': 0,
    };

final List<Map<String, dynamic>> _history = [
  {
    'documentType': 'CARE_PLAN',
    'previousStatus': 'MISSING',
    'newStatus': 'COMPLETE',
    'changedBy': 9,
    'changedByName': 'Coordinator Cole',
    'reason': 'Signed copy received',
    'changedAt': '2026-03-04T05:06:00',
  },
  {
    'documentType': 'CARE_PLAN',
    'newStatus': 'REJECTED',
    'changedBy': 11,
    'reason': 'Illegible scan',
  },
  {
    'documentType': 'CARE_PLAN',
    'previousStatus': 'REJECTED',
    'newStatus': 'IN_PROGRESS',
    'changedBy': 11,
    'reason': 'Re-uploaded',
  },
  {
    'documentType': 'CARE_PLAN',
    'previousStatus': 'IN_PROGRESS',
    'newStatus': 'MISSING',
    'changedBy': 11,
    'reason': 'File removed',
  },
];

class _Backend {
  int historyStatus = 200;
  List<Map<String, dynamic>> history = _history;
  int putStatus = 200;
  final List<http.Request> requests = [];

  Future<http.Response> handle(http.Request r) async {
    requests.add(r);
    if (r.url.path.contains('/history/')) {
      if (historyStatus != 200) {
        return http.Response(jsonEncode({'error': 'history down'}), 500);
      }
      return http.Response(jsonEncode(history), 200);
    }
    if (r.method == 'PUT') {
      if (putStatus != 200) {
        return http.Response(jsonEncode({'error': 'not allowed'}), putStatus);
      }
      return http.Response(
          jsonEncode({'documentType': 'CARE_PLAN', 'status': 'COMPLETE'}), 200);
    }
    return http.Response(jsonEncode(_checklist()), 200);
  }
}

Widget _page({bool canEdit = true, String? name}) => MaterialApp(
      home: ComplianceChecklistPage(
        subjectType: 'EMPLOYEE',
        subjectId: 3,
        subjectName: name,
        canEdit: canEdit,
      ),
    );

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

  Future<void> run(Future<void> Function() body) =>
      http.runWithClient(body, () => MockClient(backend.handle));

  testWidgets('history action lists every change with who, when and why',
      (tester) async {
    await run(() async {
      await tester.pumpWidget(_page(canEdit: false));
      await tester.pumpAndSettle();
      // Title falls back to the checklist's subject name.
      expect(find.text('Erin Employee - Documents'), findsOneWidget);

      await tester.tap(find.byTooltip('Status change history'));
      await tester.pumpAndSettle();

      expect(find.text('Status change history'), findsWidgets);
      expect(find.text('Care Plan: Missing → Complete'), findsOneWidget);
      expect(find.text('Care Plan: Untracked → Rejected'), findsOneWidget);
      expect(find.text('Reason: Signed copy received'), findsOneWidget);
      expect(find.text('By Coordinator Cole on 2026-03-04 05:06'),
          findsOneWidget);
      expect(find.text('By user #11'), findsWidgets);
      expect(find.byIcon(Icons.hourglass_top), findsOneWidget);
      expect(find.byIcon(Icons.cancel), findsOneWidget);
    });
    final historyCall =
        backend.requests.firstWhere((r) => r.url.path.contains('/history/'));
    expect(historyCall.url.queryParameters.containsKey('documentType'), false);
  });

  testWidgets('empty history shows a placeholder', (tester) async {
    backend.history = [];
    await run(() async {
      await tester.pumpWidget(_page(name: 'Named Subject'));
      await tester.pumpAndSettle();
      expect(find.text('Named Subject - Documents'), findsOneWidget);
      await tester.tap(find.byTooltip('Status change history'));
      await tester.pumpAndSettle();
    });
    expect(find.text('No status changes recorded yet'), findsOneWidget);
  });

  testWidgets('history failure shows an error snackbar', (tester) async {
    backend.historyStatus = 500;
    await run(() async {
      await tester.pumpWidget(_page());
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Status change history'));
      await tester.pumpAndSettle();
    });
    expect(find.textContaining('Failed to load history'), findsOneWidget);
    expect(find.textContaining('history down'), findsOneWidget);
  });

  testWidgets('item menu opens the per-document history', (tester) async {
    await run(() async {
      await tester.pumpWidget(_page());
      await tester.pumpAndSettle();
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      expect(find.text('Change status...'), findsOneWidget);
      await tester.tap(find.text('View history'));
      await tester.pumpAndSettle();
    });
    expect(find.text('Care Plan history'), findsOneWidget);
    final historyCall =
        backend.requests.firstWhere((r) => r.url.path.contains('/history/'));
    expect(historyCall.url.queryParameters['documentType'], 'CARE_PLAN');
  });

  testWidgets('item menu change opens the dialog, which can be cancelled',
      (tester) async {
    await run(() async {
      await tester.pumpWidget(_page());
      await tester.pumpAndSettle();
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Change status...'));
      await tester.pumpAndSettle();
      expect(find.text('Update Care Plan'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
    expect(find.byType(AlertDialog), findsNothing);
    expect(backend.requests.where((r) => r.method == 'PUT'), isEmpty);
  });

  testWidgets('a rejected status update shows the failure', (tester) async {
    backend.putStatus = 403;
    await run(() async {
      await tester.pumpWidget(_page());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Care Plan'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Because');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pumpAndSettle();
    });
    expect(find.textContaining('Failed to update status'), findsOneWidget);
    expect(find.textContaining('not allowed'), findsOneWidget);
  });
}
