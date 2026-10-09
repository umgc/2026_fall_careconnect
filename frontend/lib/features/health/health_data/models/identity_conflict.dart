enum ConflictStatus { pending, accepted, rejected }

class IdentityConflict {
  final int id;
  final String fieldName;
  final String canonicalValueBefore;
  final String incomingValue;
  final String? canonicalSourceLabel;
  final String? incomingSourceLabel;
  final ConflictStatus status;
  final DateTime? detectedAt;

  const IdentityConflict({
    required this.id,
    required this.fieldName,
    required this.canonicalValueBefore,
    required this.incomingValue,
    this.canonicalSourceLabel,
    this.incomingSourceLabel,
    this.status = ConflictStatus.pending,
    this.detectedAt,
  });

  bool get isDob => fieldName == 'date_of_birth';
  bool get isPending => status == ConflictStatus.pending;

  String get fieldLabel {
    switch (fieldName) {
      case 'date_of_birth':
        return 'Date of birth';
      default:
        return fieldName;
    }
  }

  factory IdentityConflict.fromJson(Map<String, dynamic> j) {
    ConflictStatus parseStatus(String? s) {
      switch (s) {
        case 'ACCEPTED':
          return ConflictStatus.accepted;
        case 'REJECTED':
          return ConflictStatus.rejected;
        default:
          return ConflictStatus.pending;
      }
    }

    return IdentityConflict(
      id: (j['id'] as num?)?.toInt() ?? 0,
      fieldName: j['fieldName'] as String? ?? j['field_name'] as String? ?? '',
      canonicalValueBefore: j['canonicalValueBefore'] as String? ??
          j['canonical_value_before'] as String? ??
          '',
      incomingValue:
          j['incomingValue'] as String? ?? j['incoming_value'] as String? ?? '',
      canonicalSourceLabel: j['canonicalSourceLabel'] as String?,
      incomingSourceLabel: j['incomingSourceLabel'] as String?,
      status: parseStatus(j['status'] as String?),
      detectedAt: j['detectedAt'] != null
          ? DateTime.tryParse(j['detectedAt'].toString())
          : null,
    );
  }
}