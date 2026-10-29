/// A caregiver-patient connection request as returned by
/// `/v1/api/connection-requests/incoming` and `/outgoing`.
class ConnectionRequestSummary {
  final int id;
  final String caregiverName;
  final String caregiverEmail;
  final String patientName;
  final String patientEmail;
  final String? relationshipType;
  final String? message;
  final String status;
  final DateTime? requestedAt;

  const ConnectionRequestSummary({
    required this.id,
    required this.caregiverName,
    required this.caregiverEmail,
    required this.patientName,
    required this.patientEmail,
    required this.status,
    this.relationshipType,
    this.message,
    this.requestedAt,
  });

  factory ConnectionRequestSummary.fromJson(Map<String, dynamic> json) {
    final requestedAt = json['requestedAt'];
    return ConnectionRequestSummary(
      id: (json['id'] as num).toInt(),
      caregiverName: json['caregiverName'] as String? ?? '',
      caregiverEmail: json['caregiverEmail'] as String? ?? '',
      patientName: json['patientName'] as String? ?? '',
      patientEmail: json['patientEmail'] as String? ?? '',
      relationshipType: json['relationshipType'] as String?,
      message: json['message'] as String?,
      status: json['status'] as String? ?? 'PENDING',
      requestedAt:
          requestedAt is String ? DateTime.tryParse(requestedAt) : null,
    );
  }
}
