/// Models for clinician Tier-2 HITL queue / review APIs.
class HitlQueueItem {
  final String heldItemId;
  final int patientId;
  final List<String> triggerCodes;
  final String? queryPreview;
  final String? sourceSurface;
  final DateTime? createdAt;
  final DateTime? expiresAt;

  const HitlQueueItem({
    required this.heldItemId,
    required this.patientId,
    this.triggerCodes = const [],
    this.queryPreview,
    this.sourceSurface,
    this.createdAt,
    this.expiresAt,
  });

  factory HitlQueueItem.fromJson(Map<String, dynamic> json) {
    final heldItemId = json['heldItemId'];
    if (heldItemId is! String || heldItemId.trim().isEmpty) {
      throw const FormatException('HITL queue heldItemId must be a non-empty string');
    }
    final patientIdRaw = json['patientId'];
    final int patientId;
    if (patientIdRaw is int) {
      patientId = patientIdRaw;
    } else if (patientIdRaw is num) {
      patientId = patientIdRaw.toInt();
    } else {
      throw const FormatException('HITL queue patientId must be an integer');
    }
    final triggers = <String>[];
    final codes = json['triggerCodes'];
    if (codes is List) {
      for (final code in codes) {
        if (code is String && code.trim().isNotEmpty) {
          triggers.add(code.trim());
        }
      }
    }
    return HitlQueueItem(
      heldItemId: heldItemId,
      patientId: patientId,
      triggerCodes: triggers,
      queryPreview: _optionalString(json, 'queryPreview'),
      sourceSurface: _optionalString(json, 'sourceSurface'),
      createdAt: _optionalInstant(json, 'createdAt'),
      expiresAt: _optionalInstant(json, 'expiresAt'),
    );
  }
}

class HitlDetail {
  final String heldItemId;
  final int patientId;
  final int? requesterUserId;
  final String status;
  final String deliveryStatus;
  final List<String> triggerCodes;
  final String? queryText;
  final String? draftAnswer;
  final String? finalAnswer;
  final String? citationsJson;
  final String? validationFindingsJson;
  final DateTime? createdAt;
  final DateTime? expiresAt;
  final DateTime? reviewedAt;
  final int? reviewerUserId;
  final String? reviewNotes;

  const HitlDetail({
    required this.heldItemId,
    required this.patientId,
    required this.status,
    required this.deliveryStatus,
    this.requesterUserId,
    this.triggerCodes = const [],
    this.queryText,
    this.draftAnswer,
    this.finalAnswer,
    this.citationsJson,
    this.validationFindingsJson,
    this.createdAt,
    this.expiresAt,
    this.reviewedAt,
    this.reviewerUserId,
    this.reviewNotes,
  });

  bool get isPending => status == 'PENDING_REVIEW';

  bool get requiresEditedAnswer =>
      triggerCodes.any((c) => c.toUpperCase() == 'UNSUPPORTED_CLAIM');

  factory HitlDetail.fromJson(Map<String, dynamic> json) {
    final heldItemId = json['heldItemId'];
    if (heldItemId is! String || heldItemId.trim().isEmpty) {
      throw const FormatException('HITL detail heldItemId must be a non-empty string');
    }
    final patientIdRaw = json['patientId'];
    final int patientId;
    if (patientIdRaw is int) {
      patientId = patientIdRaw;
    } else if (patientIdRaw is num) {
      patientId = patientIdRaw.toInt();
    } else {
      throw const FormatException('HITL detail patientId must be an integer');
    }
    final status = json['status'];
    final deliveryStatus = json['deliveryStatus'];
    if (status is! String || status.trim().isEmpty) {
      throw const FormatException('HITL detail status must be a non-empty string');
    }
    if (deliveryStatus is! String || deliveryStatus.trim().isEmpty) {
      throw const FormatException(
        'HITL detail deliveryStatus must be a non-empty string',
      );
    }
    final triggers = <String>[];
    final codes = json['triggerCodes'];
    if (codes is List) {
      for (final code in codes) {
        if (code is String && code.trim().isNotEmpty) {
          triggers.add(code.trim());
        }
      }
    }
    return HitlDetail(
      heldItemId: heldItemId,
      patientId: patientId,
      requesterUserId: _optionalInt(json, 'requesterUserId'),
      status: status,
      deliveryStatus: deliveryStatus,
      triggerCodes: triggers,
      queryText: _optionalString(json, 'queryText'),
      draftAnswer: _optionalString(json, 'draftAnswer'),
      finalAnswer: _optionalString(json, 'finalAnswer'),
      citationsJson: _optionalString(json, 'citationsJson'),
      validationFindingsJson: _optionalString(json, 'validationFindingsJson'),
      createdAt: _optionalInstant(json, 'createdAt'),
      expiresAt: _optionalInstant(json, 'expiresAt'),
      reviewedAt: _optionalInstant(json, 'reviewedAt'),
      reviewerUserId: _optionalInt(json, 'reviewerUserId'),
      reviewNotes: _optionalString(json, 'reviewNotes'),
    );
  }
}

class HitlApiException implements Exception {
  final int statusCode;
  final String message;
  final String? errorCode;

  const HitlApiException(this.statusCode, this.message, {this.errorCode});

  @override
  String toString() => message;
}

String? _optionalString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String) {
    throw FormatException('HITL $key must be a string');
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

int? _optionalInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  throw FormatException('HITL $key must be an integer');
}

DateTime? _optionalInstant(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('HITL $key must be an ISO-8601 string');
  }
  return DateTime.tryParse(value);
}
