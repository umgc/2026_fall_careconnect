import 'package:care_connect_app/features/dashboard/models/patient_model.dart';

import 'user_model.dart';

/// Model class for professional caregiver credentials and information.
///
/// Contains licensing and experience information for professional caregivers
/// who require verification of their credentials to provide care services.
class ProfessionalInfo {
  /// Professional license number
  final String licenseNumber;

  /// State that issued the professional license
  final String issuingState;

  /// Number of years of professional experience
  final int yearsExperience;

  /// Creates a new ProfessionalInfo instance.
  ///
  /// Parameters:
  /// * [licenseNumber] - Professional license number
  /// * [issuingState] - State that issued the professional license
  /// * [yearsExperience] - Number of years of professional experience
  ProfessionalInfo({
    required this.licenseNumber,
    required this.issuingState,
    required this.yearsExperience,
  });

  /// Converts the ProfessionalInfo instance to a JSON map.
  ///
  /// Used for API requests and data serialization when storing or
  /// transmitting professional credential information.
  ///
  /// Returns:
  /// * Map<String, dynamic> - JSON representation of professional info
  Map<String, dynamic> toJson() {
    return {
      'licenseNumber': licenseNumber,
      'issuingState': issuingState,
      'yearsExperience': yearsExperience,
    };
  }

  /// Creates a ProfessionalInfo instance from a JSON map.
  ///
  /// Factory constructor for deserializing professional credential data
  /// from API responses. Provides safe defaults for missing data.
  ///
  /// Parameters:
  /// * [json] - JSON map containing professional info data
  ///
  /// Returns:
  /// * ProfessionalInfo - New instance populated from JSON data
  factory ProfessionalInfo.fromJson(Map<String, dynamic> json) {
    return ProfessionalInfo(
      licenseNumber: json['licenseNumber'] ?? '',
      issuingState: json['issuingState'] ?? '',
      yearsExperience: json['yearsExperience'] ?? 0,
    );
  }
}

/// Extended user model for caregivers with detailed personal and professional information.
///
/// This model extends UserModel to include caregiver-specific data such as
/// personal details, contact information, address, and optional professional
/// credentials for licensed healthcare providers.
class CaregiverModel extends UserModel {
  /// Caregiver's first name
  final String firstName;

  /// Caregiver's last name
  final String lastName;

  /// Primary phone number
  final String phone;

  /// Date of birth in string format
  final String dob;

  /// Gender identity
  final String gender;

  /// Type of caregiver (Professional, Family Member, Friend, etc.)
  final String caregiverType;

  /// Physical address information
  final Address address;

  /// Professional credentials (only for professional caregivers)
  final ProfessionalInfo? professionalInfo;

  /// Creates a new CaregiverModel instance.
  ///
  /// Parameters:
  /// * [name] - Full name (inherited from UserModel)
  /// * [email] - Email address (inherited from UserModel)
  /// * [userId] - Unique user identifier (inherited from UserModel)
  /// * [role] - User role (inherited from UserModel)
  /// * [firstName] - Caregiver's first name
  /// * [lastName] - Caregiver's last name
  /// * [phone] - Primary phone number
  /// * [dob] - Date of birth in string format
  /// * [gender] - Gender identity
  /// * [caregiverType] - Type of caregiver (Professional, Family Member, etc.)
  /// * [address] - Physical address information
  /// * [professionalInfo] - Optional professional credentials for licensed providers
  CaregiverModel({
    required super.name,
    required super.email,
    required super.userId,
    required super.role,
    required this.firstName,
    required this.lastName,
    required this.phone,
    required this.dob,
    required this.gender,
    required this.caregiverType,
    required this.address,
    this.professionalInfo,
  });

  /// Converts the CaregiverModel instance to a JSON map.
  ///
  /// Extends the parent UserModel toJson() method by adding caregiver-specific
  /// fields including personal information, address, and optional professional
  /// credentials.
  ///
  /// Returns:
  /// * Map<String, dynamic> - Complete JSON representation of the caregiver
  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    json.addAll({
      'firstName': firstName,
      'lastName': lastName,
      'phone': phone,
      'dob': dob,
      'gender': gender,
      'caregiverType': caregiverType,
      'address': address.toJson(),
    });

    if (professionalInfo != null) {
      json['professional'] = professionalInfo!.toJson();
    }

    return json;
  }

  /// Creates a CaregiverModel instance from a JSON map.
  ///
  /// Factory constructor that handles comprehensive deserialization of caregiver
  /// data from API responses, including nested address and professional info.
  /// Provides safe defaults for all missing fields.
  ///
  /// Parameters:
  /// * [json] - JSON map containing complete caregiver data
  ///
  /// Returns:
  /// * CaregiverModel - New instance populated from JSON data
  factory CaregiverModel.fromJson(Map<String, dynamic> json) {
    return CaregiverModel(
      name: json['name'] ?? '',
      email: json['email'] ?? '',
      userId: json['userId'] ?? '',
      role: json['role'] ?? 'CAREGIVER',
      firstName: json['firstName'] ?? '',
      lastName: json['lastName'] ?? '',
      phone: json['phone'] ?? '',
      dob: json['dob'] ?? '',
      gender: json['gender'] ?? '',
      caregiverType: json['caregiverType'] ?? '',
      address: Address.fromJson(json['address'] ?? {}),
      professionalInfo: json['professional'] != null
          ? ProfessionalInfo.fromJson(json['professional'])
          : null,
    );
  }
}
