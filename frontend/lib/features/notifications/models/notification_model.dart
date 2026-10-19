import 'dart:convert';

class Notification_dto {
  final int id;
  final String title;
  final String message;
  final DateTime timestamp;
  final bool isRead;

  Notification_dto({
    required this.id,
    required this.title,
    required this.message,
    required this.timestamp,
    this.isRead = false,
  });

  factory Notification_dto.fromJson(Map<String, dynamic> json) {
    return Notification_dto(
      id: json['id'],
      title: json['title'],
      message: json['message'],
      timestamp: DateTime.parse(json['timestamp']),
      isRead: json['isRead'] ?? false,
    );
  }

  String toJson() {
    return jsonEncode({
      'id': id,
      'title': title,
      'message': message,
      'timestamp': timestamp.toIso8601String(),
      'isRead': isRead,
    });
  }
}
