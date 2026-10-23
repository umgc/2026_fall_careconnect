class UserProfile {
  final int id;
  final String name;
  String? email;
  String? phoneNumber;
  String? address;
  String? city;
  String? state;
  String? zipCode;
  String? country;
  String? profilePictureUrl;

  UserProfile({
    required this.id,
    required this.name,
    this.email,
    this.phoneNumber,
    this.address,
    this.city,
    this.state,
    this.zipCode,
    this.country,
    this.profilePictureUrl,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'email': email,
      'phoneNumber': phoneNumber,
      'address': address,
      'city': city,
      'state': state,
      'zipCode': zipCode,
      'country': country,
    };
  }

  UserProfile copyWith({
    String? name,
    String? email,
    String? phoneNumber,
    String? address,
    String? city,
    String? state,
    String? zipCode,
    String? country,
    String? profilePictureUrl,
  }) {
    return UserProfile(
      id: id,
      name: name ?? this.name,
      email: email ?? this.email,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      address: address ?? this.address,
      city: city ?? this.city,
      state: state ?? this.state,
      zipCode: zipCode ?? this.zipCode,
      country: country ?? this.country,
      profilePictureUrl: profilePictureUrl ?? this.profilePictureUrl,
    );
  }
}

class CaregiverProfile extends UserProfile {
  String? specialization;
  String? organization;
  String? license;
  String? dateOfBirth; // Added date of birth field

  CaregiverProfile({
    required super.id,
    required super.name,
    super.email,
    super.phoneNumber,
    super.address,
    super.city,
    super.state,
    super.zipCode,
    super.country,
    super.profilePictureUrl,
    this.specialization,
    this.organization,
    this.license,
    this.dateOfBirth, // Added parameter
  });

  factory CaregiverProfile.fromJson(Map<String, dynamic> json) {
    return CaregiverProfile(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      email: json['email'],
      phoneNumber: json['phoneNumber'],
      address: json['address'],
      city: json['city'],
      state: json['state'],
      zipCode: json['zipCode'],
      country: json['country'],
      profilePictureUrl: json['profilePictureUrl'],
      specialization: json['specialization'],
      organization: json['organization'],
      license: json['license'],
      dateOfBirth: json['dateOfBirth'], // Added dateOfBirth
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final baseJson = super.toJson();
    return {
      ...baseJson,
      'specialization': specialization,
      'organization': organization,
      'license': license,
      'dateOfBirth': dateOfBirth, // Added dateOfBirth
    };
  }

  @override
  CaregiverProfile copyWith({
    String? name,
    String? email,
    String? phoneNumber,
    String? address,
    String? city,
    String? state,
    String? zipCode,
    String? country,
    String? profilePictureUrl,
    String? specialization,
    String? organization,
    String? license,
    String? dateOfBirth, // Added parameter
  }) {
    return CaregiverProfile(
      id: id,
      name: name ?? this.name,
      email: email ?? this.email,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      address: address ?? this.address,
      city: city ?? this.city,
      state: state ?? this.state,
      zipCode: zipCode ?? this.zipCode,
      country: country ?? this.country,
      profilePictureUrl: profilePictureUrl ?? this.profilePictureUrl,
      specialization: specialization ?? this.specialization,
      organization: organization ?? this.organization,
      license: license ?? this.license,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth, // Added parameter
    );
  }
}

class PatientProfile extends UserProfile {
  String? dateOfBirth;
  String? gender;
  String? emergencyContact;
  String? medicalConditions;
  String? allergies;
  String? medications;

  PatientProfile({
    required super.id,
    required super.name,
    super.email,
    super.phoneNumber,
    super.address,
    super.city,
    super.state,
    super.zipCode,
    super.country,
    super.profilePictureUrl,
    this.dateOfBirth,
    this.gender,
    this.emergencyContact,
    this.medicalConditions,
    this.allergies,
    this.medications,
  });

  factory PatientProfile.fromJson(Map<String, dynamic> json) {
    return PatientProfile(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      email: json['email'],
      phoneNumber: json['phoneNumber'],
      address: json['address'],
      city: json['city'],
      state: json['state'],
      zipCode: json['zipCode'],
      country: json['country'],
      profilePictureUrl: json['profilePictureUrl'],
      dateOfBirth: json['dateOfBirth'],
      gender: json['gender'],
      emergencyContact: json['emergencyContact'],
      medicalConditions: json['medicalConditions'],
      allergies: json['allergies'],
      medications: json['medications'],
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final baseJson = super.toJson();
    return {
      ...baseJson,
      'dateOfBirth': dateOfBirth,
      'gender': gender,
      'emergencyContact': emergencyContact,
      'medicalConditions': medicalConditions,
      'allergies': allergies,
      'medications': medications,
    };
  }

  @override
  PatientProfile copyWith({
    String? name,
    String? email,
    String? phoneNumber,
    String? address,
    String? city,
    String? state,
    String? zipCode,
    String? country,
    String? profilePictureUrl,
    String? dateOfBirth,
    String? gender,
    String? emergencyContact,
    String? medicalConditions,
    String? allergies,
    String? medications,
  }) {
    return PatientProfile(
      id: id,
      name: name ?? this.name,
      email: email ?? this.email,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      address: address ?? this.address,
      city: city ?? this.city,
      state: state ?? this.state,
      zipCode: zipCode ?? this.zipCode,
      country: country ?? this.country,
      profilePictureUrl: profilePictureUrl ?? this.profilePictureUrl,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      gender: gender ?? this.gender,
      emergencyContact: emergencyContact ?? this.emergencyContact,
      medicalConditions: medicalConditions ?? this.medicalConditions,
      allergies: allergies ?? this.allergies,
      medications: medications ?? this.medications,
    );
  }
}
