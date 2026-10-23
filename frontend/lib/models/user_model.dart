/// Base model class representing a user in the system.
///
/// This is the foundational user model that contains core user information
/// shared across all user types. It serves as the parent class for more
/// specific user models like PatientUserModel and CaregiverModel.
class UserModel {
  /// The user's full name
  final String name;

  /// The user's email address (used for authentication)
  final String email;

  /// Unique identifier for the user
  final String userId;

  /// The user's role in the system (PATIENT, CAREGIVER, etc.)
  final String role;

  /// Creates a new UserModel instance.
  ///
  /// Parameters:
  /// * [name] - The user's full name
  /// * [email] - The user's email address (used for authentication)
  /// * [userId] - Unique identifier for the user
  /// * [role] - The user's role in the system (PATIENT, CAREGIVER, etc.)
  UserModel({
    required this.name,
    required this.email,
    required this.userId,
    required this.role,
  });

  /// Converts the UserModel instance to a JSON map.
  ///
  /// Used for API requests, data serialization, and storage operations.
  /// All core user fields are included in the JSON output.
  ///
  /// Returns:
  /// * Map<String, dynamic> - JSON representation of the user model
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'email': email,
      'userId': userId,
      'role': role,
    };
  }

  /// Creates a UserModel instance from a JSON map.
  ///
  /// Factory constructor that handles JSON deserialization from API responses
  /// and stored data. Provides default empty strings for missing fields to
  /// ensure the model remains stable.
  ///
  /// Parameters:
  /// * [json] - JSON map containing user data
  ///
  /// Returns:
  /// * UserModel - New UserModel instance populated from JSON data
  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      name: json['name'] ?? '',
      email: json['email'] ?? '',
      userId: json['userId'] ?? '',
      role: json['role'] ?? '',
    );
  }
}
