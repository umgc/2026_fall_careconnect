class ConversationPreviewDto {
  final int peerId;
  final String peerName;
  final String peerRole;
  final String content; // last message
  final DateTime timestamp;
  final bool hasUnread;

  ConversationPreviewDto({
    required this.peerId,
    required this.peerName,
    required this.peerRole,
    required this.content,
    required this.timestamp,
    this.hasUnread = false,
  });

  /// Human-readable relationship label derived from the peer's role.
  String get relationshipLabel {
    switch (peerRole.toUpperCase()) {
      case 'CAREGIVER':
        return 'Caregiver';
      case 'PATIENT':
        return 'Patient';
      case 'FAMILY_LINK':
        return 'Family';
      case 'ADMIN':
        return 'Admin';
      default:
        return '';
    }
  }

  factory ConversationPreviewDto.fromJson(Map<String, dynamic> json) {
    return ConversationPreviewDto(
      peerId: (json['peerId'] as num).toInt(),
      peerName: (json['peerName'] as String?) ??
          (json['peerEmail'] as String?) ??
          'Unknown',
      peerRole: (json['peerRole'] as String?) ?? '',
      content: (json['content'] as String?) ?? '',
      timestamp: json['timestamp'] is String
          ? DateTime.parse(json['timestamp'] as String)
          : DateTime.now(),
      hasUnread: json['hasUnread'] as bool? ?? false,
    );
  }
}
