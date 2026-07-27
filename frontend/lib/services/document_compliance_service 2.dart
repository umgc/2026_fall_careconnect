import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_service.dart';
import 'auth_token_manager.dart';

/// One dashboard row: a subject's aggregate document compliance position.
class ComplianceSummary {
  final String subjectType; // EMPLOYEE | CARE_CIRCLE
  final int subjectId;
  final String subjectName;
  final int requiredCount;
  final int missingCount;
  final int inProgressCount;
  final int completeCount;
  final int rejectedCount;
  final int percentComplete;
  final bool blocked;

  ComplianceSummary({
    required this.subjectType,
    required this.subjectId,
    required this.subjectName,
    required this.requiredCount,
    required this.missingCount,
    required this.inProgressCount,
    required this.completeCount,
    required this.rejectedCount,
    required this.percentComplete,
    required this.blocked,
  });

  factory ComplianceSummary.fromJson(Map<String, dynamic> json) {
    return ComplianceSummary(
      subjectType: json['subjectType'] ?? '',
      subjectId: json['subjectId'] ?? 0,
      subjectName: json['subjectName'] ?? '',
      requiredCount: json['requiredCount'] ?? 0,
      missingCount: json['missingCount'] ?? 0,
      inProgressCount: json['inProgressCount'] ?? 0,
      completeCount: json['completeCount'] ?? 0,
      rejectedCount: json['rejectedCount'] ?? 0,
      percentComplete: json['percentComplete'] ?? 0,
      blocked: json['blocked'] ?? false,
    );
  }
}

/// One required document on a subject's checklist with its current status
/// and the evidence (uploads / digitized record) behind it.
class ChecklistItem {
  final String documentType;
  final String status; // MISSING | IN_PROGRESS | COMPLETE | REJECTED
  final bool tracked;
  final int fileCount;
  final bool hasStructuredEntry;
  final int? latestFileId;
  final String? latestFilename;
  final DateTime? latestUploadAt;
  final String? notes;
  final DateTime? updatedAt;

  ChecklistItem({
    required this.documentType,
    required this.status,
    required this.tracked,
    required this.fileCount,
    required this.hasStructuredEntry,
    this.latestFileId,
    this.latestFilename,
    this.latestUploadAt,
    this.notes,
    this.updatedAt,
  });

  factory ChecklistItem.fromJson(Map<String, dynamic> json) {
    return ChecklistItem(
      documentType: json['documentType'] ?? '',
      status: json['status'] ?? 'MISSING',
      tracked: json['tracked'] ?? false,
      fileCount: json['fileCount'] ?? 0,
      hasStructuredEntry: json['hasStructuredEntry'] ?? false,
      latestFileId: json['latestFileId'],
      latestFilename: json['latestFilename'],
      latestUploadAt: json['latestUploadAt'] != null
          ? DateTime.tryParse(json['latestUploadAt'])
          : null,
      notes: json['notes'],
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'])
          : null,
    );
  }
}

/// A subject's full required-document checklist.
class DocumentChecklist {
  final String subjectType;
  final int subjectId;
  final String subjectName;
  final List<ChecklistItem> items;
  final int requiredCount;
  final int missingCount;
  final int inProgressCount;
  final int completeCount;
  final int rejectedCount;
  final int percentComplete;

  DocumentChecklist({
    required this.subjectType,
    required this.subjectId,
    required this.subjectName,
    required this.items,
    required this.requiredCount,
    required this.missingCount,
    required this.inProgressCount,
    required this.completeCount,
    required this.rejectedCount,
    required this.percentComplete,
  });

  factory DocumentChecklist.fromJson(Map<String, dynamic> json) {
    return DocumentChecklist(
      subjectType: json['subjectType'] ?? '',
      subjectId: json['subjectId'] ?? 0,
      subjectName: json['subjectName'] ?? '',
      items: (json['items'] as List<dynamic>? ?? [])
          .map((e) => ChecklistItem.fromJson(e))
          .toList(),
      requiredCount: json['requiredCount'] ?? 0,
      missingCount: json['missingCount'] ?? 0,
      inProgressCount: json['inProgressCount'] ?? 0,
      completeCount: json['completeCount'] ?? 0,
      rejectedCount: json['rejectedCount'] ?? 0,
      percentComplete: json['percentComplete'] ?? 0,
    );
  }
}

/// One outstanding required form (MISSING or REJECTED).
class MissingDocument {
  final String subjectType;
  final int subjectId;
  final String subjectName;
  final String documentType;
  final String status;
  final String? notes;
  final DateTime? updatedAt;

  MissingDocument({
    required this.subjectType,
    required this.subjectId,
    required this.subjectName,
    required this.documentType,
    required this.status,
    this.notes,
    this.updatedAt,
  });

  factory MissingDocument.fromJson(Map<String, dynamic> json) {
    return MissingDocument(
      subjectType: json['subjectType'] ?? '',
      subjectId: json['subjectId'] ?? 0,
      subjectName: json['subjectName'] ?? '',
      documentType: json['documentType'] ?? '',
      status: json['status'] ?? 'MISSING',
      notes: json['notes'],
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'])
          : null,
    );
  }
}

/// One audit-trail entry: who changed a document's status, when and why.
class StatusHistoryEntry {
  final String documentType;
  final String? previousStatus;
  final String newStatus;
  final int? changedBy;
  final String? changedByName;
  final String reason;
  final DateTime? changedAt;

  StatusHistoryEntry({
    required this.documentType,
    this.previousStatus,
    required this.newStatus,
    this.changedBy,
    this.changedByName,
    required this.reason,
    this.changedAt,
  });

  factory StatusHistoryEntry.fromJson(Map<String, dynamic> json) {
    return StatusHistoryEntry(
      documentType: json['documentType'] ?? '',
      previousStatus: json['previousStatus'],
      newStatus: json['newStatus'] ?? '',
      changedBy: json['changedBy'],
      changedByName: json['changedByName'],
      reason: json['reason'] ?? '',
      changedAt: json['changedAt'] != null
          ? DateTime.tryParse(json['changedAt'])
          : null,
    );
  }
}

/// API client for the Document Completion and Compliance Tracking endpoints.
class DocumentComplianceService {
  static const List<String> statuses = [
    'MISSING',
    'IN_PROGRESS',
    'COMPLETE',
    'REJECTED',
  ];

  /// Human-readable label for a status or document-type token.
  static String prettify(String token) {
    return token
        .split('_')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
        .join(' ');
  }

  /// Compliance summaries for the coordinator dashboard.
  /// [subjectType] filters to 'EMPLOYEE' or 'CARE_CIRCLE'; null returns both.
  static Future<List<ComplianceSummary>> getDashboard({
    String? subjectType,
  }) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    final uri = Uri.parse('${ApiConstants.documentCompliance}/dashboard')
        .replace(queryParameters: {
      if (subjectType != null) 'subjectType': subjectType,
    });
    final response =
        await http.get(uri, headers: headers).timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw Exception(_errorFrom(response, 'Failed to load compliance dashboard'));
    }
    final List<dynamic> rows = json.decode(response.body);
    return rows.map((e) => ComplianceSummary.fromJson(e)).toList();
  }

  /// Required-document checklist for one employee or care circle.
  static Future<DocumentChecklist> getChecklist(
    String subjectType,
    int subjectId,
  ) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    final response = await http
        .get(
          Uri.parse(
              '${ApiConstants.documentCompliance}/checklist/$subjectType/$subjectId'),
          headers: headers,
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw Exception(_errorFrom(response, 'Failed to load checklist'));
    }
    return DocumentChecklist.fromJson(json.decode(response.body));
  }

  /// Outstanding required forms, filterable by subject and document type.
  static Future<List<MissingDocument>> getMissing({
    String? subjectType,
    String? documentType,
  }) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    final uri = Uri.parse('${ApiConstants.documentCompliance}/missing')
        .replace(queryParameters: {
      if (subjectType != null) 'subjectType': subjectType,
      if (documentType != null) 'documentType': documentType,
    });
    final response =
        await http.get(uri, headers: headers).timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw Exception(_errorFrom(response, 'Failed to load missing documents'));
    }
    final List<dynamic> rows = json.decode(response.body);
    return rows.map((e) => MissingDocument.fromJson(e)).toList();
  }

  /// The missing-forms report as CSV text (for export).
  static Future<String> exportMissingCsv({
    String? subjectType,
    String? documentType,
  }) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    final uri = Uri.parse('${ApiConstants.documentCompliance}/missing/export')
        .replace(queryParameters: {
      if (subjectType != null) 'subjectType': subjectType,
      if (documentType != null) 'documentType': documentType,
    });
    final response =
        await http.get(uri, headers: headers).timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw Exception(_errorFrom(response, 'Failed to export missing documents'));
    }
    return response.body;
  }

  /// Manually transition a document's status. [reason] is mandatory and is
  /// recorded in the audit trail with the acting user and timestamp.
  static Future<ChecklistItem> updateStatus({
    required String subjectType,
    required int subjectId,
    required String documentType,
    required String status,
    required String reason,
  }) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    final response = await http
        .put(
          Uri.parse('${ApiConstants.documentCompliance}/status'),
          headers: headers,
          body: jsonEncode({
            'subjectType': subjectType,
            'subjectId': subjectId,
            'documentType': documentType,
            'status': status,
            'reason': reason,
          }),
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw Exception(_errorFrom(response, 'Failed to update status'));
    }
    return ChecklistItem.fromJson(json.decode(response.body));
  }

  /// Status-transition audit trail for a subject.
  static Future<List<StatusHistoryEntry>> getHistory(
    String subjectType,
    int subjectId, {
    String? documentType,
  }) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    final uri = Uri.parse(
            '${ApiConstants.documentCompliance}/history/$subjectType/$subjectId')
        .replace(queryParameters: {
      if (documentType != null) 'documentType': documentType,
    });
    final response =
        await http.get(uri, headers: headers).timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw Exception(_errorFrom(response, 'Failed to load history'));
    }
    final List<dynamic> rows = json.decode(response.body);
    return rows.map((e) => StatusHistoryEntry.fromJson(e)).toList();
  }

  static String _errorFrom(http.Response response, String fallback) {
    try {
      final body = json.decode(response.body);
      if (body is Map && body['error'] != null) {
        return body['error'];
      }
    } catch (_) {
      // Non-JSON error body; fall through to the generic message.
    }
    return '$fallback (HTTP ${response.statusCode})';
  }
}
