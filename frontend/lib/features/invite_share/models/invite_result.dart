/// Result of generating a care-circle invite (issue #69).
///
/// Mirrors the backend CreateInviteResponse from POST
/// /v1/api/care-circle/{linkId}/invite (issue #53):
///   { tokenId, token, inviteUrl, linkId, linkType, status, expiresAt, createdAt }
class InviteResult {
  final int tokenId;
  final String token;
  final String inviteUrl;
  final int linkId;
  final String linkType;
  final String status;
  final DateTime? expiresAt;

  const InviteResult({
    required this.tokenId,
    required this.token,
    required this.inviteUrl,
    required this.linkId,
    required this.linkType,
    required this.status,
    required this.expiresAt,
  });

  factory InviteResult.fromJson(Map<String, dynamic> json) {
    return InviteResult(
      tokenId: (json['tokenId'] as num?)?.toInt() ?? 0,
      token: json['token'] as String? ?? '',
      inviteUrl: json['inviteUrl'] as String? ?? '',
      linkId: (json['linkId'] as num?)?.toInt() ?? 0,
      linkType: json['linkType'] as String? ?? 'UNKNOWN',
      status: json['status'] as String? ?? 'UNKNOWN',
      expiresAt: json['expiresAt'] != null
          ? DateTime.tryParse(json['expiresAt'].toString())
          : null,
    );
  }
}
