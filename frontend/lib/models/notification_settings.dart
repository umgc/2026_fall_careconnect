class NotificationSettings {
  final int? id;
  final int userId;
  final bool gamification;
  final bool emergency;
  final bool videoCall;
  final bool audioCall;
  final bool sms;
  final bool significantVitals;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  NotificationSettings({
    this.id,
    required this.userId,
    required this.gamification,
    required this.emergency,
    required this.videoCall,
    required this.audioCall,
    required this.sms,
    required this.significantVitals,
    this.createdAt,
    this.updatedAt,
  });

  factory NotificationSettings.fromJson(Map<String, dynamic> json) {
    return NotificationSettings(
      id: json['id'],
      userId: json['userId'],
      gamification: json['gamification'] ?? false,
      emergency: json['emergency'] ?? true,
      videoCall: json['videoCall'] ?? true,
      audioCall: json['audioCall'] ?? true,
      sms: json['sms'] ?? true,
      significantVitals: json['significantVitals'] ?? true,
      createdAt:
          json['createdAt'] != null ? DateTime.parse(json['createdAt']) : null,
      updatedAt:
          json['updatedAt'] != null ? DateTime.parse(json['updatedAt']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'gamification': gamification,
      'emergency': emergency,
      'videoCall': videoCall,
      'audioCall': audioCall,
      'sms': sms,
      'significantVitals': significantVitals,
    };
  }

  NotificationSettings copyWith({
    int? id,
    int? userId,
    bool? gamification,
    bool? emergency,
    bool? videoCall,
    bool? audioCall,
    bool? sms,
    bool? significantVitals,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return NotificationSettings(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      gamification: gamification ?? this.gamification,
      emergency: emergency ?? this.emergency,
      videoCall: videoCall ?? this.videoCall,
      audioCall: audioCall ?? this.audioCall,
      sms: sms ?? this.sms,
      significantVitals: significantVitals ?? this.significantVitals,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
