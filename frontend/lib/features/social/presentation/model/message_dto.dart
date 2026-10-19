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
    );
  }
}
