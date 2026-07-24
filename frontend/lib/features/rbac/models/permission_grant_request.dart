class PermissionGrantRequest {
  final String targetUserId;
  final String feature; // 'MEDICATIONS', 'INVOICES', 'TRANSCRIPTS', 'SUMMARIES'

  PermissionGrantRequest({
    required this.targetUserId,
    required this.feature,
  });

  Map<String, dynamic> toJson() {
    return {
      'targetUserId': targetUserId,
      'feature': feature,
    };
  }
}