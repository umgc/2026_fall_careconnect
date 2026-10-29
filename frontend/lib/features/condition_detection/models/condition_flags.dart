/// Models for `GET /api/v3/calls/{callId}/condition-flags` (AI condition screening).
///
/// Mirrors the backend `ConditionFlagsResponse` record field for field.
class ConditionFlagsResult {
  final String disclaimer;
  final List<ConditionModelRun> runs;

  const ConditionFlagsResult({required this.disclaimer, this.runs = const []});

  factory ConditionFlagsResult.fromJson(Map<String, dynamic> json) {
    final rawRuns = json['runs'];
    return ConditionFlagsResult(
      disclaimer:
          json['disclaimer'] is String ? json['disclaimer'] as String : '',
      runs: rawRuns is List
          ? rawRuns
              .whereType<Map>()
              .map((r) =>
                  ConditionModelRun.fromJson(Map<String, dynamic>.from(r)))
              .toList()
          : const [],
    );
  }
}

/// One screening model's status and results for a call.
class ConditionModelRun {
  /// Statuses still waiting on the backend worker.
  static const Set<String> inProgressStatuses = {'PENDING', 'PROCESSING'};

  final String modelId;
  final String displayName;
  final String inputKind;

  /// `PENDING`, `PROCESSING`, `COMPLETE`, `SKIPPED` or `FAILED`.
  final String status;
  final String? skipReason;
  final DateTime? completedAt;
  final List<ConditionFlagItem> flags;

  const ConditionModelRun({
    required this.modelId,
    required this.displayName,
    required this.inputKind,
    required this.status,
    this.skipReason,
    this.completedAt,
    this.flags = const [],
  });

  bool get isInProgress => inProgressStatuses.contains(status);

  factory ConditionModelRun.fromJson(Map<String, dynamic> json) {
    final rawFlags = json['flags'];
    final completedAt = json['completedAt'];
    return ConditionModelRun(
      modelId: (json['modelId'] as String?) ?? '',
      displayName: (json['displayName'] as String?) ?? '',
      inputKind: (json['inputKind'] as String?) ?? '',
      status: ((json['status'] as String?) ?? 'PENDING').toUpperCase(),
      skipReason: json['skipReason'] as String?,
      completedAt: completedAt is String
          ? DateTime.tryParse(completedAt)?.toLocal()
          : null,
      flags: rawFlags is List
          ? rawFlags
              .whereType<Map>()
              .map((f) =>
                  ConditionFlagItem.fromJson(Map<String, dynamic>.from(f)))
              .toList()
          : const [],
    );
  }
}

/// One condition's screening result.
class ConditionFlagItem {
  /// `DEPRESSION`, `ANXIETY`, `PTSD` or `BIPOLAR`.
  final String condition;

  /// 0 means no indicator; higher is more severe.
  final int severityLevel;
  final String severityLabel;
  final String? evidenceSummary;

  const ConditionFlagItem({
    required this.condition,
    required this.severityLevel,
    required this.severityLabel,
    this.evidenceSummary,
  });

  factory ConditionFlagItem.fromJson(Map<String, dynamic> json) {
    final level = json['severityLevel'];
    return ConditionFlagItem(
      condition: ((json['condition'] as String?) ?? '').toUpperCase(),
      severityLevel: level is num ? level.toInt() : 0,
      severityLabel: ((json['severityLabel'] as String?) ?? '').toUpperCase(),
      evidenceSummary: json['evidenceSummary'] as String?,
    );
  }
}
