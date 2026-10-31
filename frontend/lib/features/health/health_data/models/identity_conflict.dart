enum ConflictStatus { pending, accepted, rejected }

/// Which detail from the new record the patient is asked to confirm.
enum IdentityCheckType { phone, email, zip }

/// A second detail from the new record, so the patient can tell whether the
/// record is really theirs: name and date of birth alone can match two people
/// (M3 feedback). The backend picks phone first, then email, then ZIP code.
/// Only a hidden form of the value is ever kept: the last 4 digits of a phone,
/// an email with its name part hidden, or a 5-digit ZIP code.
class IdentityCheck {
  final IdentityCheckType type;
  final String value;

  const IdentityCheck._(this.type, this.value);

  /// Null if [value] can't be shown safely (too short, not an email, ...).
  static IdentityCheck? of(IdentityCheckType type, String? value) {
    final shown = switch (type) {
      IdentityCheckType.phone => phoneLast4(value),
      IdentityCheckType.email => maskEmail(value),
      IdentityCheckType.zip => zip5(value),
    };
    return shown == null ? null : IdentityCheck._(type, shown);
  }

  /// Reads {"type": "PHONE" | "EMAIL" | "ZIP", "value": "..."}.
  static IdentityCheck? fromJson(Object? json) {
    if (json is! Map) return null;
    final type = switch ('${json['type']}'.toUpperCase()) {
      'PHONE' => IdentityCheckType.phone,
      'EMAIL' => IdentityCheckType.email,
      'ZIP' => IdentityCheckType.zip,
      _ => null,
    };
    return type == null ? null : of(type, json['value']?.toString());
  }

  /// A trailing extension ("ext 45", "x45", "#45", ";ext=45"): the phone
  /// column holds the FHIR value as sent, so it can have one (DEF-EHR-REC-07).
  static final _extension = RegExp(
      r'\s*(?:;\s*ext=|extension|ext\.?|x|#)\s*\d+\s*$',
      caseSensitive: false);

  /// The last 4 digits of the number (not of its extension), or null if there
  /// are fewer than 4. A full number is cut down, so it is never kept or shown.
  static String? phoneLast4(String? phone) {
    final digits = (phone ?? '')
        .replaceFirst(_extension, '')
        .replaceAll(RegExp(r'\D'), '');
    return digits.length < 4 ? null : digits.substring(digits.length - 4);
  }

  /// "jane.doe@gmail.com" -> "j•••@gmail.com". Null if it isn't an email.
  static String? maskEmail(String? email) {
    final e = (email ?? '').trim();
    final at = e.lastIndexOf('@');
    if (at < 1 || at == e.length - 1) return null;
    return '${e[0]}\u2022\u2022\u2022${e.substring(at)}';
  }

  /// The 5-digit ZIP code ("21201-1234" -> "21201"), or null.
  static String? zip5(String? zip) {
    final m = RegExp(r'^\s*(\d{5})(?:-?\d{4})?\s*$').firstMatch(zip ?? '');
    return m?.group(1);
  }
}

class IdentityConflict {
  final int id;
  final String fieldName;
  final String canonicalValueBefore;
  final String incomingValue;
  final String? canonicalSourceLabel;
  final String? incomingSourceLabel;
  final ConflictStatus status;
  final DateTime? detectedAt;

  /// A detail from the new record for the patient to confirm before choosing
  /// a date, or null when the record has no phone, email or ZIP code.
  final IdentityCheck? identityCheck;

  const IdentityConflict({
    required this.id,
    required this.fieldName,
    required this.canonicalValueBefore,
    required this.incomingValue,
    this.canonicalSourceLabel,
    this.incomingSourceLabel,
    this.status = ConflictStatus.pending,
    this.detectedAt,
    this.identityCheck,
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
      identityCheck:
          IdentityCheck.fromJson(j['identityCheck'] ?? j['identity_check']),
    );
  }
}
