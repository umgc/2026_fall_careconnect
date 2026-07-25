/// Result of generating a patient profile share link.
class ProfileShareResult {
  final int tokenId;
  final String token;
  final String shareUrl;
  final String status;
  final DateTime? expiresAt;

  const ProfileShareResult({
    required this.tokenId,
    required this.token,
    required this.shareUrl,
    required this.status,
    this.expiresAt,
  });

  factory ProfileShareResult.fromJson(Map<String, dynamic> json) {
    return ProfileShareResult(
      tokenId: (json['tokenId'] as num?)?.toInt() ?? 0,
      token: json['token'] as String? ?? '',
      shareUrl: json['shareUrl'] as String? ?? '',
      status: json['status'] as String? ?? 'UNKNOWN',
      expiresAt: json['expiresAt'] != null
          ? DateTime.tryParse(json['expiresAt'].toString())
          : null,
    );
  }
}
