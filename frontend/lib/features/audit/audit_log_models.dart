class AuditLogItem {
  final String type;
  final String summary;
  final String caregiverName;
  final DateTime createdAt;

  const AuditLogItem({
    required this.type,
    required this.summary,
    required this.caregiverName,
    required this.createdAt,
  });

  factory AuditLogItem.fromJson(Map<String, dynamic> json) {
    return AuditLogItem(
      type: (json['type'] ?? '').toString(),
      summary: (json['summary'] ?? '').toString(),
      caregiverName: (json['caregiverName'] ?? 'Unknown caregiver').toString(),
      createdAt: DateTime.parse(json['createdAt'].toString()),
    );
  }
}
