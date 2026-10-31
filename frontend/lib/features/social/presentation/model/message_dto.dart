enum ShareKind {
  medicare,
  health;

  String get wireValue => name.toUpperCase();

  String get destinationTab => name;

  String get description => switch (this) {
        ShareKind.medicare => 'their Medicare records',
        ShareKind.health => 'their health information',
      };

  static ShareKind? parse(dynamic value) {
    if (value is! String) return null;
    return switch (value.trim().toUpperCase()) {
      'MEDICARE' => ShareKind.medicare,
      'HEALTH' => ShareKind.health,
      _ => null,
    };
  }
}

class MessageDto {
  final int id;
  final int senderId;
  final int receiverId;
  final String content;
  final DateTime timestamp;
  final bool queuedOffline;
  final int? attachmentId;
  final String? attachmentName;
  final String? attachmentContentType;
  final int? attachmentSize;
  final ShareKind? shareKind;
  final int? sharePatientId;

  bool get hasAttachment => attachmentId != null;
  bool get isImage => attachmentContentType?.startsWith('image/') ?? false;
  bool get isAudio => attachmentContentType?.startsWith('audio/') ?? false;

  MessageDto({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.content,
    required this.timestamp,
    this.queuedOffline = false,
    this.attachmentId,
    this.attachmentName,
    this.attachmentContentType,
    this.attachmentSize,
    this.shareKind,
    this.sharePatientId,
  });

  factory MessageDto.fromJson(Map<String, dynamic> json) {
    return MessageDto(
      id: (json['id'] as num).toInt(),
      senderId: (json['senderId'] as num).toInt(),
      receiverId: (json['receiverId'] as num).toInt(),
      content: json['content'] as String? ?? '',
      timestamp: DateTime.parse(json['timestamp'] as String),
      queuedOffline: json['queuedOffline'] == true,
      attachmentId: (json['attachmentId'] as num?)?.toInt(),
      attachmentName: json['attachmentName'] as String?,
      attachmentContentType: json['attachmentContentType'] as String?,
      attachmentSize: (json['attachmentSize'] as num?)?.toInt(),
      shareKind: ShareKind.parse(json['shareKind']),
      sharePatientId: (json['sharePatientId'] as num?)?.toInt(),
    );
  }

  static MessageDto? fromWebSocketEvent(
    Map<String, dynamic> event, {
    required int receiverId,
  }) {
    final senderIdRaw = event['senderId'];
    final senderId = senderIdRaw is num
        ? senderIdRaw.toInt()
        : int.tryParse(senderIdRaw?.toString() ?? '');
    if (senderId == null) return null;

    final timestampRaw = event['timestamp'];
    return MessageDto(
      id: event['messageId'] is num
          ? (event['messageId'] as num).toInt()
          : int.tryParse(event['messageId']?.toString() ?? '') ?? 0,
      senderId: senderId,
      receiverId: receiverId,
      content: event['content'] as String? ?? '',
      timestamp: timestampRaw is String
          ? DateTime.tryParse(timestampRaw) ?? DateTime.now()
          : DateTime.now(),
      shareKind: ShareKind.parse(event['shareKind']),
      sharePatientId: (event['sharePatientId'] as num?)?.toInt(),
    );
  }
}
