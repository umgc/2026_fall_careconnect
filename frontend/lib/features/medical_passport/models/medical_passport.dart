/// The patient's Emergency Care Passport (CC-12), as `GET /v1/api/passport`
/// returns it.
///
/// Allergies and medications come from the patient's existing records and are
/// read-only here. Blood type, chronic conditions and the emergency contact are
/// entered on the passport itself ([PassportProfileUpdate]).
library;

/// A section the patient can share on their QR code. The names match the
/// backend's `PassportField` and are sent as-is in the visibility path.
enum PassportField {
  allergies('ALLERGIES'),
  medications('MEDICATIONS'),
  chronicConditions('CHRONIC_CONDITIONS'),
  bloodType('BLOOD_TYPE'),
  emergencyContact('EMERGENCY_CONTACT');

  const PassportField(this.apiName);

  final String apiName;

  static PassportField? fromApi(String name) {
    for (final field in values) {
      if (field.apiName == name) return field;
    }
    return null;
  }
}

/// The eight blood types the backend accepts, in its order.
enum BloodType {
  aPositive('A_POSITIVE', 'A+'),
  aNegative('A_NEGATIVE', 'A−'),
  bPositive('B_POSITIVE', 'B+'),
  bNegative('B_NEGATIVE', 'B−'),
  abPositive('AB_POSITIVE', 'AB+'),
  abNegative('AB_NEGATIVE', 'AB−'),
  oPositive('O_POSITIVE', 'O+'),
  oNegative('O_NEGATIVE', 'O−');

  const BloodType(this.apiName, this.label);

  final String apiName;

  /// How it reads on screen, e.g. "O+".
  final String label;

  static BloodType? fromApi(Object? name) {
    for (final type in values) {
      if (type.apiName == name) return type;
    }
    return null;
  }
}

class PassportAllergy {
  const PassportAllergy({required this.allergen, this.severity, this.reaction});

  factory PassportAllergy.fromJson(Map<String, dynamic> json) => PassportAllergy(
        allergen: json['allergen'] as String? ?? '',
        severity: json['severity'] as String?,
        reaction: json['reaction'] as String?,
      );

  final String allergen;

  /// The backend's `AllergySeverity` name: MILD, MODERATE, SEVERE or
  /// LIFE_THREATENING. Null when not recorded.
  final String? severity;
  final String? reaction;
}

class PassportMedication {
  const PassportMedication({required this.name, this.dosage, this.frequency});

  factory PassportMedication.fromJson(Map<String, dynamic> json) =>
      PassportMedication(
        name: json['name'] as String? ?? '',
        dosage: json['dosage'] as String?,
        frequency: json['frequency'] as String?,
      );

  final String name;
  final String? dosage;
  final String? frequency;
}

class PassportContact {
  const PassportContact({this.name, this.relationship, this.phone});

  factory PassportContact.fromJson(Map<String, dynamic> json) => PassportContact(
        name: json['name'] as String?,
        relationship: json['relationship'] as String?,
        phone: json['phone'] as String?,
      );

  final String? name;
  final String? relationship;
  final String? phone;
}

/// Whether the patient has a live QR code. The raw token is never here: it is
/// shown once, when the code is made ([NewPassportCode]).
class PassportCodeStatus {
  const PassportCodeStatus({this.createdAt, this.lastScannedAt});

  factory PassportCodeStatus.fromJson(Map<String, dynamic> json) =>
      PassportCodeStatus(
        createdAt: _instant(json['createdAt']),
        lastScannedAt: _instant(json['lastScannedAt']),
      );

  final DateTime? createdAt;
  final DateTime? lastScannedAt;
}

class MedicalPassport {
  const MedicalPassport({
    required this.name,
    this.age,
    this.bloodType,
    this.chronicConditions,
    this.emergencyContact,
    this.allergies = const [],
    this.medications = const [],
    this.sharing = const {},
    this.code,
    this.ready = false,
    this.lastUpdated,
    this.lastUpdatedBySection = const {},
  });

  factory MedicalPassport.fromJson(Map<String, dynamic> json) {
    final contact = json['emergencyContact'];
    final code = json['token'];
    return MedicalPassport(
      name: json['name'] as String? ?? '',
      age: (json['age'] as num?)?.toInt(),
      bloodType: BloodType.fromApi(json['bloodType']),
      chronicConditions: json['chronicConditions'] as String?,
      emergencyContact: contact is Map<String, dynamic>
          ? PassportContact.fromJson(contact)
          : null,
      allergies: [
        for (final a in json['allergies'] as List? ?? const [])
          PassportAllergy.fromJson(a as Map<String, dynamic>),
      ],
      medications: [
        for (final m in json['medications'] as List? ?? const [])
          PassportMedication.fromJson(m as Map<String, dynamic>),
      ],
      sharing: {
        for (final e in (json['sharing'] as Map? ?? const {}).entries)
          if (PassportField.fromApi(e.key as String) case final field?)
            field: e.value == true,
      },
      code: code is Map<String, dynamic> && code['active'] == true
          ? PassportCodeStatus.fromJson(code)
          : null,
      ready: json['ready'] == true,
      lastUpdated: _instant(json['lastUpdated']),
      lastUpdatedBySection: {
        for (final e in (json['lastUpdatedBySection'] as Map? ?? const {}).entries)
          if (PassportField.fromApi(e.key as String) case final field?)
            if (_instant(e.value) case final changed?) field: changed,
      },
    );
  }

  final String name;
  final int? age;
  final BloodType? bloodType;
  final String? chronicConditions;
  final PassportContact? emergencyContact;
  final List<PassportAllergy> allergies;
  final List<PassportMedication> medications;

  /// Whether each section is shown on a scan. A field missing from the
  /// response counts as not shared.
  final Map<PassportField, bool> sharing;

  /// The active QR code, or null when the patient has none.
  final PassportCodeStatus? code;

  /// An active code and at least one shared section.
  final bool ready;

  /// The latest change to any section with content; null when all are empty.
  final DateTime? lastUpdated;
  final Map<PassportField, DateTime> lastUpdatedBySection;

  bool isShared(PassportField field) => sharing[field] ?? false;

  bool get hasCode => code != null;

  /// Two letters for the avatar, e.g. "JM" for "Jordan Miller".
  String get initials => initialsOf(name);
}

/// Returned once, when a code is made. [url] is what the QR encodes; neither
/// it nor [token] can be fetched again.
class NewPassportCode {
  const NewPassportCode({required this.token, required this.url, this.createdAt});

  factory NewPassportCode.fromJson(Map<String, dynamic> json) => NewPassportCode(
        token: json['token'] as String? ?? '',
        url: json['url'] as String? ?? '',
        createdAt: _instant(json['createdAt']),
      );

  final String token;
  final String url;
  final DateTime? createdAt;
}

/// The body of `PUT /v1/api/passport/profile`. The PUT replaces every field,
/// so build it from the current values plus the change ([PassportProfileUpdate.from]).
class PassportProfileUpdate {
  const PassportProfileUpdate({
    this.bloodType,
    this.chronicConditions,
    this.contactName,
    this.contactRelationship,
    this.contactPhone,
  });

  factory PassportProfileUpdate.from(MedicalPassport passport) =>
      PassportProfileUpdate(
        bloodType: passport.bloodType,
        chronicConditions: passport.chronicConditions,
        contactName: passport.emergencyContact?.name,
        contactRelationship: passport.emergencyContact?.relationship,
        contactPhone: passport.emergencyContact?.phone,
      );

  /// The backend's limits, so the form can stop long input before sending.
  static const maxChronicConditions = 2000;
  static const maxContactName = 255;
  static const maxContactRelationship = 64;
  static const maxContactPhone = 32;

  final BloodType? bloodType;
  final String? chronicConditions;
  final String? contactName;
  final String? contactRelationship;
  final String? contactPhone;

  Map<String, dynamic> toJson() => {
        'bloodType': bloodType?.apiName,
        'chronicConditions': chronicConditions,
        'emergencyContactName': contactName,
        'emergencyContactRelationship': contactRelationship,
        'emergencyContactPhone': contactPhone,
      };
}

/// Two letters from the first and last words of [name], upper-cased.
String initialsOf(String? name) {
  final words = (name ?? '').trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '?';
  if (words.length == 1) return words.first.substring(0, 1).toUpperCase();
  return (words.first.substring(0, 1) + words.last.substring(0, 1)).toUpperCase();
}

DateTime? _instant(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toLocal() : null;
