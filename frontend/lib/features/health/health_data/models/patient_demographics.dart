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

  bool get isEmpty => name == null && birthDate == null && gender == null;

  /// This record with [birthDate] replaced, e.g. by the date the patient
  /// confirmed when sources disagreed.
  PatientDemographics withBirthDate(DateTime birthDate) =>
      PatientDemographics(name: name, birthDate: birthDate, gender: gender);

  /// This record, with any missing field taken from [other]. A field this
  /// record has always wins, so the preferred source is the receiver.
  PatientDemographics fillFrom(PatientDemographics? other) {
    if (other == null) return this;
    return PatientDemographics(
      name: name ?? other.name,
      birthDate: birthDate ?? other.birthDate,
      gender: gender ?? other.gender,
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
