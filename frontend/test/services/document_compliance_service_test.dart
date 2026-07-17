// Tests for DocumentComplianceService and its models.
//
// Coverage strategy:
//   Model fromJson parsing — all fields plus null/missing fallbacks.
//   prettify — token formatting for statuses and document types.
//   HTTP methods tested via http.runWithClient + MockClient, with
//   AuthTokenManager.getAuthHeaders() intercepted via a FlutterSecureStorage
//   MethodChannel stub (same pattern as enhanced_file_service_test.dart).
//
//   Branches tested:
//     getDashboard — 200 → list, subjectType filter param, non-200 → throws.
//     getChecklist — 200 → checklist with items, non-200 error body → message.
//     getMissing — filters passed as query params, 200 → list.
//     exportMissingCsv — 200 → raw CSV text returned.
//     updateStatus — PUT with all fields in body, 200 → item, 400 → throws.
//     getHistory — 200 → entries, documentType filter param.

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:care_connect_app/services/document_compliance_service.dart';

// ─── Secure storage stub ──────────────────────────────────────────────────────

const MethodChannel _secureStorageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

final Map<String, String?> _secureStore = {};

void _setupSecureStorageStub() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_secureStorageChannel, (call) async {
    switch (call.method) {
      case 'write':
        _secureStore[call.arguments['key'] as String] =
            call.arguments['value'] as String?;
        return null;
      case 'read':
        return _secureStore[call.arguments['key'] as String];
      case 'delete':
        _secureStore.remove(call.arguments['key'] as String);
        return null;
      case 'deleteAll':
        _secureStore.clear();
        return null;
      default:
        return null;
    }
  });
}

void _seedAuthToken() {
  _secureStore['jwt_token'] = 'test-jwt-token';
  _secureStore['token_expiry'] = '2000000000';
}

// ─── Sample payloads ──────────────────────────────────────────────────────────

Map<String, dynamic> _summaryJson() => {
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
    };

Map<String, dynamic> _itemJson() => {
      'documentType': 'CERTIFICATION',
      'status': 'IN_PROGRESS',
      'tracked': false,
      'fileCount': 2,
      'hasStructuredEntry': false,
      'latestFileId': 10,
      'latestFilename': 'cpr.pdf',
      'latestUploadAt': '2026-07-01T10:30:00',
      'notes': 'awaiting review',
      'updatedAt': '2026-07-02T08:00:00',
    };

Map<String, dynamic> _checklistJson() => {
      'subjectType': 'EMPLOYEE',
      'subjectId': 2,
      'subjectName': 'Jane Caregiver',
      'items': [_itemJson()],
      'requiredCount': 9,
      'missingCount': 8,
      'inProgressCount': 1,
      'completeCount': 0,
      'rejectedCount': 0,
      'percentComplete': 0,
    };

Map<String, dynamic> _historyJson() => {
      'documentType': 'CERTIFICATION',
      'previousStatus': 'IN_PROGRESS',
      'newStatus': 'COMPLETE',
      'changedBy': 1,
      'changedByName': 'Coordinator',
      'reason': 'Verified against original',
      'changedAt': '2026-07-03T12:00:00',
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    _secureStore.clear();
    _setupSecureStorageStub();
    _seedAuthToken();
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, null);
  });

  // ─── Model parsing ─────────────────────────────────────────────────────────

  group('ComplianceSummary.fromJson', () {
    test('parses all fields', () {
      final s = ComplianceSummary.fromJson(_summaryJson());
      expect(s.subjectType, 'EMPLOYEE');
      expect(s.subjectId, 2);
      expect(s.subjectName, 'Jane Caregiver');
      expect(s.requiredCount, 9);
      expect(s.missingCount, 6);
      expect(s.inProgressCount, 1);
      expect(s.completeCount, 1);
      expect(s.rejectedCount, 1);
      expect(s.percentComplete, 11);
      expect(s.blocked, isTrue);
    });

    test('missing fields fall back to defaults', () {
      final s = ComplianceSummary.fromJson({});
      expect(s.subjectType, '');
      expect(s.subjectId, 0);
      expect(s.requiredCount, 0);
      expect(s.blocked, isFalse);
    });
  });

  group('ChecklistItem.fromJson', () {
    test('parses all fields including dates', () {
      final item = ChecklistItem.fromJson(_itemJson());
      expect(item.documentType, 'CERTIFICATION');
      expect(item.status, 'IN_PROGRESS');
      expect(item.tracked, isFalse);
      expect(item.fileCount, 2);
      expect(item.hasStructuredEntry, isFalse);
      expect(item.latestFileId, 10);
      expect(item.latestFilename, 'cpr.pdf');
      expect(item.latestUploadAt, DateTime(2026, 7, 1, 10, 30));
      expect(item.notes, 'awaiting review');
      expect(item.updatedAt, DateTime(2026, 7, 2, 8));
    });

    test('missing fields fall back to defaults', () {
      final item = ChecklistItem.fromJson({});
      expect(item.status, 'MISSING');
      expect(item.fileCount, 0);
      expect(item.hasStructuredEntry, isFalse);
      expect(item.latestUploadAt, isNull);
      expect(item.notes, isNull);
    });
  });

  group('DocumentChecklist.fromJson', () {
    test('parses items list and counts', () {
      final checklist = DocumentChecklist.fromJson(_checklistJson());
      expect(checklist.subjectName, 'Jane Caregiver');
      expect(checklist.items, hasLength(1));
      expect(checklist.items.first.documentType, 'CERTIFICATION');
      expect(checklist.requiredCount, 9);
      expect(checklist.missingCount, 8);
    });

    test('null items list becomes empty', () {
      final checklist = DocumentChecklist.fromJson({'subjectId': 1});
      expect(checklist.items, isEmpty);
    });
  });

  group('StatusHistoryEntry.fromJson', () {
    test('parses transition with who/when/why', () {
      final entry = StatusHistoryEntry.fromJson(_historyJson());
      expect(entry.previousStatus, 'IN_PROGRESS');
      expect(entry.newStatus, 'COMPLETE');
      expect(entry.changedBy, 1);
      expect(entry.changedByName, 'Coordinator');
      expect(entry.reason, 'Verified against original');
      expect(entry.changedAt, DateTime(2026, 7, 3, 12));
    });

    test('first transition has null previousStatus', () {
      final entry =
          StatusHistoryEntry.fromJson({'newStatus': 'IN_PROGRESS', 'reason': 'uploaded'});
      expect(entry.previousStatus, isNull);
      expect(entry.newStatus, 'IN_PROGRESS');
    });
  });

  group('MissingDocument.fromJson', () {
    test('parses subject context and status', () {
      final doc = MissingDocument.fromJson({
        'subjectType': 'CARE_CIRCLE',
        'subjectId': 7,
        'subjectName': 'Pat Recipient',
        'documentType': 'CONSENT_FORM',
        'status': 'REJECTED',
        'notes': 'signature missing',
      });
      expect(doc.subjectType, 'CARE_CIRCLE');
      expect(doc.subjectName, 'Pat Recipient');
      expect(doc.documentType, 'CONSENT_FORM');
      expect(doc.status, 'REJECTED');
      expect(doc.notes, 'signature missing');
    });
  });

  // ─── prettify ──────────────────────────────────────────────────────────────

  group('prettify', () {
    test('formats document type tokens', () {
      expect(DocumentComplianceService.prettify('BACKGROUND_CHECK'), 'Background Check');
      expect(DocumentComplianceService.prettify('IN_PROGRESS'), 'In Progress');
      expect(DocumentComplianceService.prettify('MISSING'), 'Missing');
    });

    test('handles empty string', () {
      expect(DocumentComplianceService.prettify(''), '');
    });
  });

  // ─── HTTP methods via MockClient ───────────────────────────────────────────

  group('getDashboard', () {
    test('200 → parsed summaries; subjectType filter in query', () async {
      Uri? captured;
      final client = MockClient((request) async {
        captured = request.url;
        return http.Response(jsonEncode([_summaryJson()]), 200,
            headers: {'content-type': 'application/json'});
      });

      final rows = await http.runWithClient(
        () => DocumentComplianceService.getDashboard(subjectType: 'EMPLOYEE'),
        () => client,
      );

      expect(rows, hasLength(1));
      expect(rows.first.subjectName, 'Jane Caregiver');
      expect(captured!.path, contains('/document-compliance/dashboard'));
      expect(captured!.queryParameters['subjectType'], 'EMPLOYEE');
    });

    test('403 with error body → throws with backend message', () async {
      final client = MockClient((request) async =>
          http.Response(jsonEncode({'error': 'Admin or caregiver role required'}), 403));

      expect(
        () => http.runWithClient(
            () => DocumentComplianceService.getDashboard(), () => client),
        throwsA(predicate((e) =>
            e.toString().contains('Admin or caregiver role required'))),
      );
    });
  });

  group('getChecklist', () {
    test('200 → checklist with items', () async {
      final client = MockClient((request) async {
        expect(request.url.path, contains('/checklist/EMPLOYEE/2'));
        return http.Response(jsonEncode(_checklistJson()), 200);
      });

      final checklist = await http.runWithClient(
        () => DocumentComplianceService.getChecklist('EMPLOYEE', 2),
        () => client,
      );

      expect(checklist.subjectName, 'Jane Caregiver');
      expect(checklist.items.first.status, 'IN_PROGRESS');
    });

    test('non-JSON error body → generic message with status code', () async {
      final client = MockClient((request) async => http.Response('boom', 500));

      expect(
        () => http.runWithClient(
            () => DocumentComplianceService.getChecklist('EMPLOYEE', 2), () => client),
        throwsA(predicate((e) => e.toString().contains('HTTP 500'))),
      );
    });
  });

  group('getMissing', () {
    test('filters are passed as query params', () async {
      Uri? captured;
      final client = MockClient((request) async {
        captured = request.url;
        return http.Response(jsonEncode([]), 200);
      });

      final rows = await http.runWithClient(
        () => DocumentComplianceService.getMissing(
            subjectType: 'CARE_CIRCLE', documentType: 'CONSENT_FORM'),
        () => client,
      );

      expect(rows, isEmpty);
      expect(captured!.queryParameters['subjectType'], 'CARE_CIRCLE');
      expect(captured!.queryParameters['documentType'], 'CONSENT_FORM');
    });
  });

  group('exportMissingCsv', () {
    test('200 → returns raw CSV body', () async {
      const csv =
          'Subject Type,Subject ID,Subject Name,Document Type,Status,Notes,Last Updated\n'
          'EMPLOYEE,2,Jane Caregiver,TAX_FORM,MISSING,,\n';
      final client = MockClient((request) async {
        expect(request.url.path, contains('/missing/export'));
        return http.Response(csv, 200, headers: {'content-type': 'text/csv'});
      });

      final result = await http.runWithClient(
        () => DocumentComplianceService.exportMissingCsv(),
        () => client,
      );

      expect(result, csv);
      expect(result.split('\n').first, startsWith('Subject Type,'));
    });
  });

  group('updateStatus', () {
    test('PUT body carries all fields; 200 → refreshed item', () async {
      Map<String, dynamic>? sentBody;
      String? method;
      final client = MockClient((request) async {
        method = request.method;
        sentBody = jsonDecode(request.body);
        return http.Response(
            jsonEncode({..._itemJson(), 'status': 'COMPLETE', 'tracked': true}), 200);
      });

      final item = await http.runWithClient(
        () => DocumentComplianceService.updateStatus(
          subjectType: 'EMPLOYEE',
          subjectId: 2,
          documentType: 'CERTIFICATION',
          status: 'COMPLETE',
          reason: 'Verified against original',
        ),
        () => client,
      );

      expect(method, 'PUT');
      expect(sentBody!['subjectType'], 'EMPLOYEE');
      expect(sentBody!['subjectId'], 2);
      expect(sentBody!['documentType'], 'CERTIFICATION');
      expect(sentBody!['status'], 'COMPLETE');
      expect(sentBody!['reason'], 'Verified against original');
      expect(item.status, 'COMPLETE');
      expect(item.tracked, isTrue);
    });

    test('400 missing reason → throws backend message', () async {
      final client = MockClient((request) async => http.Response(
          jsonEncode({'error': 'A reason is required for every status change'}), 400));

      expect(
        () => http.runWithClient(
          () => DocumentComplianceService.updateStatus(
            subjectType: 'EMPLOYEE',
            subjectId: 2,
            documentType: 'CERTIFICATION',
            status: 'REJECTED',
            reason: '',
          ),
          () => client,
        ),
        throwsA(predicate(
            (e) => e.toString().contains('A reason is required'))),
      );
    });
  });

  group('getHistory', () {
    test('200 → audit entries; documentType filter in query', () async {
      Uri? captured;
      final client = MockClient((request) async {
        captured = request.url;
        return http.Response(jsonEncode([_historyJson()]), 200);
      });

      final history = await http.runWithClient(
        () => DocumentComplianceService.getHistory('EMPLOYEE', 2,
            documentType: 'CERTIFICATION'),
        () => client,
      );

      expect(history, hasLength(1));
      expect(history.first.changedByName, 'Coordinator');
      expect(history.first.reason, 'Verified against original');
      expect(captured!.path, contains('/history/EMPLOYEE/2'));
      expect(captured!.queryParameters['documentType'], 'CERTIFICATION');
    });
  });
}
