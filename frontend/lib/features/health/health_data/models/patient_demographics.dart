class PatientDemographics {
  final String? name;
  final DateTime? birthDate;
  final String? gender;

  const PatientDemographics({
    this.name,
    this.birthDate,
    this.gender,
  });

  factory PatientDemographics.fromJson(Map<String, dynamic> json) {
    return PatientDemographics(
      name: _stringOrNull(json['name']),
      birthDate: _parseDate(json['birthDate']),
      gender: _stringOrNull(json['gender']),
    );
  }

  static String? _stringOrNull(dynamic value) {
    if (value == null) return null;

    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static DateTime? _parseDate(dynamic value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }
}
