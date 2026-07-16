/// Non-enumerating invite preview (issue #59) consumed by the acceptance
/// handoff (issue #75).
///
/// Mirrors the backend InvitePreviewResponse from GET /v1/api/invite/{token}:
///   { valid, status, nextAction, linkId, linkType, inviterName, patientName,
///     inviteReason, invitedEmail, expiresAt }
class InvitePreview {
  final bool valid;
  final String status;      // VALID | EXPIRED | REVOKED | ACCEPTED | INVALID
  final String nextAction;  // ACCEPT | SIGN_IN | REQUEST_NEW | NONE
  final int? linkId;
  final String? linkType;
  final String? inviterName;
  final String? patientName;
  final String? inviteReason;
  final String? invitedEmail;
  final DateTime? expiresAt;

  const InvitePreview({
    required this.valid,
    required this.status,
    required this.nextAction,
    this.linkId,
    this.linkType,
    this.inviterName,
    this.patientName,
    this.inviteReason,
    this.invitedEmail,
    this.expiresAt,
  });

  factory InvitePreview.fromJson(Map<String, dynamic> json) {
    return InvitePreview(
      valid: json['valid'] as bool? ?? false,
      status: json['status'] as String? ?? 'INVALID',
      nextAction: json['nextAction'] as String? ?? 'NONE',
      linkId: (json['linkId'] as num?)?.toInt(),
      linkType: json['linkType'] as String?,
      inviterName: json['inviterName'] as String?,
      patientName: json['patientName'] as String?,
      inviteReason: json['inviteReason'] as String?,
      invitedEmail: json['invitedEmail'] as String?,
      expiresAt: json['expiresAt'] != null
          ? DateTime.tryParse(json['expiresAt'].toString())
          : null,
    );
  }

  /// A short, human-readable summary of who invited the user and why.
  String get contextSummary {
    final inviter = inviterName ?? 'Someone';
    final patient = patientName != null ? ' to join $patientName\'s care circle' : ' to join a care circle';
    final reason = (inviteReason != null && inviteReason!.isNotEmpty) ? '\n\n"$inviteReason"' : '';
    return '$inviter has invited you$patient.$reason';
  }
}
