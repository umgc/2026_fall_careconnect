import 'package:care_connect_app/features/dashboard/models/patient_model.dart';

import 'user_model.dart';

/// Extended user model for patients with detailed personal information.
///
/// This model extends UserModel to include patient-specific data such as
/// personal details, contact information, and address. It represents
/// individuals who receive care and use the health tracking features
/// of the application.
class PatientUserModel extends UserModel {
  /// Patient's first name
  final String firstName;

  /// Patient's last name
  final String lastName;

  /// Primary phone number for contact
  final String phone;

  /// Date of birth in string format
  final String dob;

  /// Gender identity
  final String gender;

  /// Physical address information
  final Address address;

  /// Creates a new PatientUserModel instance.
  ///
  /// Parameters:
  /// * [name] - Full name (inherited from UserModel)
  /// * [email] - Email address (inherited from UserModel)
  /// * [userId] - Unique user identifier (inherited from UserModel)
  /// * [role] - User role (inherited from UserModel)
  /// * [firstName] - Patient's first name
  /// * [lastName] - Patient's last name
  /// * [phone] - Primary phone number for contact
  /// * [dob] - Date of birth in string format
  /// * [gender] - Gender identity
  /// * [address] - Physical address information
  PatientUserModel({
    required super.name,
    required super.email,
    required super.userId,
    required super.role,
    required this.firstName,
    required this.lastName,
    required this.phone,
    required this.dob,
    required this.gender,
    required this.address,
  });

  /// Converts the PatientUserModel instance to a JSON map.
  ///
  /// Extends the parent UserModel toJson() method by adding patient-specific
  /// fields including personal information and address. Explicitly sets the
  /// role to 'PATIENT' to ensure consistency.
  ///
  /// Returns:
  /// * Map<String, dynamic> - Complete JSON representation of the patient
  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    json.addAll({
      'firstName': firstName,
      'lastName': lastName,
      'phone': phone,
      'dob': dob,
      'gender': gender,
      'address': address.toJson(),
      'role': 'PATIENT',
    });

    return json;
  }

  /// Creates a PatientUserModel instance from a JSON map.
  ///
  /// Factory constructor that handles comprehensive deserialization of patient
  /// data from API responses, including nested address information. Provides
  /// safe defaults for all missing fields and ensures role is set to 'PATIENT'.
  ///
  /// Parameters:
  /// * [json] - JSON map containing complete patient data
  ///
  /// Returns:
  /// * PatientUserModel - New instance populated from JSON data
  factory PatientUserModel.fromJson(Map<String, dynamic> json) {
    return PatientUserModel(
      name: json['name'] ?? '',
      email: json['email'] ?? '',
      userId: json['userId'] ?? '',
      role: json['role'] ?? 'PATIENT',
      firstName: json['firstName'] ?? '',
      lastName: json['lastName'] ?? '',
      phone: json['phone'] ?? '',
      dob: json['dob'] ?? '',
      gender: json['gender'] ?? '',
      address: Address.fromJson(json['address'] ?? {}),
    );
  }

  @override
  String toString() {
    return 'PatientUserModel{firstName: $firstName, lastName: $lastName, phone: $phone, dob: $dob, gender: $gender, address: $address}';
  }
}
