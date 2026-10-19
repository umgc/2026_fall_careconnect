/// Represents a notification scheduled to be delivered to a user
/// at a specific time. This can include reminders, alerts, or
/// emergency messages tied to a task.
///
/// A `ScheduledNotification` typically originates from the backend
/// and is mapped to Dart via JSON serialization/deserialization.
/// It can track delivery status, scheduled vs. sent times, and
/// any error information if delivery fails.
class ScheduledNotification {
  /// Unique identifier for this scheduled notification (optional).
  final int? id;

  /// The ID of the task this notification is associated with.
  /// May be null if not tied to a specific task.
  final int? taskId;

  /// The ID of the user who will receive this notification.
  int receiverId;

  /// Title of the notification (short summary shown in the UI).
  String title;

  /// Body of the notification (detailed message content).
  String body;

  /// Type of notification (e.g., "REMINDER", "ALERT", "EMERGENCY").
  String? notificationType;

  /// The date and time when this notification is scheduled to be sent.
  DateTime scheduledTime;

  /// The date and time when this notification was actually sent.
  /// Will remain null until the notification is dispatched.
  DateTime? sentTime;

  /// Current status of the notification.
  ///
  /// Possible values:
  /// - "PENDING": waiting to be sent
  /// - "SENT": successfully delivered
  /// - "FAILED": delivery attempt failed
  /// - "CANCELLED": notification was cancelled before sending
  String status;

  /// Identifier returned by the notification service provider
  String? messageId;

  /// Error message in case sending fails.
  String? errorMessage;

  /// Creates a new [ScheduledNotification] instance.
  ///
  /// By default, the [status] is set to `"PENDING"` if not provided.
  ScheduledNotification({
    this.id,
    this.taskId,
    required this.receiverId,
    required this.title,
    required this.body,
    this.notificationType,
    required this.scheduledTime,
    this.sentTime,
    this.status = "PENDING",
    this.messageId,
    this.errorMessage,
  });

  /// Creates a [ScheduledNotification] from a JSON map.
  ///
  /// This is typically used when receiving data from an API.
  /// Ensures date strings are parsed into [DateTime] objects.
  factory ScheduledNotification.fromJson(Map<String, dynamic> json) {
    return ScheduledNotification(
      id: json['id'] ?? -1,
      taskId: json['taskId'],
      receiverId: json['receiverId'],
      title: json['title'],
      body: json['body'],
      notificationType: json['notificationType'],
      scheduledTime: DateTime.parse(json['scheduledTime']),
      sentTime:
          json['sentTime'] != null ? DateTime.parse(json['sentTime']) : null,
      status: json['status'] ?? "PENDING",
      messageId: json['messageId'],
      errorMessage: json['errorMessage'],
    );
  }

  /// Converts this [ScheduledNotification] to a JSON map.
  ///
  /// Useful for sending data to an API (e.g., when creating a
  /// new scheduled notification on the backend).
  ///
  /// Note: Fields like [id], [sentTime], [status], [messageId],
  /// and [errorMessage] are excluded since they are usually set
  /// by the backend or after delivery.
  Map<String, dynamic> toJson() {
    return {
      'taskId': taskId,
      'receiverId': receiverId,
      'title': title,
      'body': body,
      'notificationType': notificationType,
      'scheduledTime': scheduledTime.toIso8601String(),
    };
  }
}
