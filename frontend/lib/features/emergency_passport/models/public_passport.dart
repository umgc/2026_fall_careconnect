// What a scan of a patient's emergency QR code shows (CC-12, design screen 3).
//
// Matches PublicPassport from GET /v1/api/passport/scan/{token}. Hidden or
// empty sections are left out of the response, so they are null here.

class PassportAllergy {
  final String allergen;
  final String? severity; // MILD, MODERATE, SEVERE, LIFE_THREATENING or null
  final String? reaction;

  const PassportAllergy({required this.allergen, this.severity, this.reaction});

  factory PassportAllergy.fromJson(Map<String, dynamic> json) => PassportAllergy(
        allergen: (json['allergen'] ?? '').toString(),
        severity: json['severity'] as String?,
        reaction: _text(json['reaction']),
      );
}

class PassportMedication {
  final String name;
  final String? dosage;
  final String? frequency;

  const PassportMedication({required this.name, this.dosage, this.frequency});

  factory PassportMedication.fromJson(Map<String, dynamic> json) =>
      PassportMedication(
        name: (json['name'] ?? '').toString(),
        dosage: _text(json['dosage']),
        frequency: _text(json['frequency']),
      );
}

class PassportContact {
  final String? name;
  final String? relationship;
  final String? phone;

  const PassportContact({this.name, this.relationship, this.phone});

  factory PassportContact.fromJson(Map<String, dynamic> json) => PassportContact(
        name: _text(json['name']),
        relationship: _text(json['relationship']),
        phone: _text(json['phone']),
      );
}

class PublicPassport {
  final String name;
  final int? age;
  final String? bloodType;
  final List<PassportAllergy>? allergies;
  final List<PassportMedication>? medications;
  final String? chronicConditions;
  final PassportContact? emergencyContact;
  final DateTime? lastUpdated;

  const PublicPassport({
    required this.name,
    this.age,
    this.bloodType,
    this.allergies,
    this.medications,
    this.chronicConditions,
    this.emergencyContact,
    this.lastUpdated,
  });

  /// True when the patient shared nothing beyond name and age.
  bool get sharesNothing =>
      bloodType == null &&
      (allergies == null || allergies!.isEmpty) &&
      (medications == null || medications!.isEmpty) &&
      chronicConditions == null &&
      emergencyContact == null;

  factory PublicPassport.fromJson(Map<String, dynamic> json) {
    List<T>? list<T>(String key, T Function(Map<String, dynamic>) read) {
      final raw = json[key];
      if (raw is! List) return null;
      return raw.whereType<Map<String, dynamic>>().map(read).toList();
    }

    final contact = json['emergencyContact'];
    final updated = json['lastUpdated'];
    return PublicPassport(
      name: (json['name'] ?? '').toString(),
      age: (json['age'] as num?)?.toInt(),
      bloodType: json['bloodType'] as String?,
      allergies: list('allergies', PassportAllergy.fromJson),
      medications: list('medications', PassportMedication.fromJson),
      chronicConditions: _text(json['chronicConditions']),
      emergencyContact:
          contact is Map<String, dynamic> ? PassportContact.fromJson(contact) : null,
      lastUpdated: updated is String ? DateTime.tryParse(updated) : null,
    );
  }
}

/// O_POSITIVE -> O+. Unknown values are shown as sent.
String bloodTypeLabel(String code) {
  final parts = code.split('_');
  if (parts.length != 2) return code;
  final sign = switch (parts[1]) {
    'POSITIVE' => '+',
    'NEGATIVE' => '−',
    _ => parts[1],
  };
  return '${parts[0]}$sign';
}

/// O_POSITIVE -> "O positive", for screen readers.
String bloodTypeSpoken(String code) {
  final parts = code.split('_');
  if (parts.length != 2) return code;
  return '${parts[0]} ${parts[1].toLowerCase()}';
}

/// LIFE_THREATENING -> Life-threatening. Null or unknown -> null.
String? severityLabel(String? severity) => switch (severity) {
      'MILD' => 'Mild',
      'MODERATE' => 'Moderate',
      'SEVERE' => 'Severe',
      'LIFE_THREATENING' => 'Life-threatening',
      _ => null,
    };

String? _text(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}
