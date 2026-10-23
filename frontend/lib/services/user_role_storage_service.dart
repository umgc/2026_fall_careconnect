import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

/// Service for storing and retrieving user role and related data
/// Uses SharedPreferences which automatically handles platform differences:
/// - Web: localStorage/sessionStorage
/// - Mobile: Native platform storage (UserDefaults on iOS, SharedPreferences on Android)
class UserRoleStorageService {
  static const String _userRoleKey = 'user_role';
  static const String _userIdKey = 'user_id';
  static const String _patientIdKey = 'patient_id';
  static const String _caregiverIdKey = 'caregiver_id';
  static const String _isLoggedInKey = 'is_logged_in';
  static const String _patientModelKey = 'patient_model';
  static const String _caregiverModelKey = 'caregiver_model';

  static UserRoleStorageService? _instance;
  SharedPreferences? _prefs;

  // Singleton pattern
  static UserRoleStorageService get instance {
    _instance ??= UserRoleStorageService._internal();
    return _instance!;
  }

  UserRoleStorageService._internal();

  /// Initialize the service - must be called before using other methods
  Future<void> initialize() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  /// Store user role and related data
  Future<void> setUserData({
    required String role,
    required int userId,
    int? patientId,
    int? caregiverId,
  }) async {
    await _ensureInitialized();

    await Future.wait([
      _prefs!.setString(_userRoleKey, role),
      _prefs!.setInt(_userIdKey, userId),
      _prefs!.setBool(_isLoggedInKey, true),
      if (patientId != null) _prefs!.setInt(_patientIdKey, patientId),
      if (caregiverId != null) _prefs!.setInt(_caregiverIdKey, caregiverId),
    ]);

    if (kDebugMode) {
      print(
          'UserRoleStorageService: Stored user data - Role: $role, UserID: $userId');
    }
  }

  /// Get the stored user role
  Future<String?> getUserRole() async {
    await _ensureInitialized();
    return _prefs!.getString(_userRoleKey);
  }

  /// Get the stored user ID
  Future<int?> getUserId() async {
    await _ensureInitialized();
    return _prefs!.getInt(_userIdKey);
  }

  /// Get the stored patient ID
  Future<int?> getPatientId() async {
    await _ensureInitialized();
    return _prefs!.getInt(_patientIdKey);
  }

  /// Get the stored caregiver ID
  Future<int?> getCaregiverId() async {
    await _ensureInitialized();
    return _prefs!.getInt(_caregiverIdKey);
  }

  /// Check if user is logged in
  Future<bool> isLoggedIn() async {
    await _ensureInitialized();
    return _prefs!.getBool(_isLoggedInKey) ?? false;
  }

  /// Get all user data at once
  Future<UserData?> getUserData() async {
    await _ensureInitialized();

    final role = _prefs!.getString(_userRoleKey);
    final userId = _prefs!.getInt(_userIdKey);
    final isLoggedIn = _prefs!.getBool(_isLoggedInKey) ?? false;

    if (!isLoggedIn || role == null || userId == null) {
      return null;
    }

    return UserData(
      role: role,
      userId: userId,
      patientId: _prefs!.getInt(_patientIdKey),
      caregiverId: _prefs!.getInt(_caregiverIdKey),
      isLoggedIn: isLoggedIn,
    );
  }

  /// Clear all stored user data (logout)
  Future<void> clearUserData() async {
    await _ensureInitialized();

    await Future.wait([
      _prefs!.remove(_userRoleKey),
      _prefs!.remove(_userIdKey),
      _prefs!.remove(_patientIdKey),
      _prefs!.remove(_caregiverIdKey),
      _prefs!.remove(_patientModelKey),
      _prefs!.remove(_caregiverModelKey),
      _prefs!.setBool(_isLoggedInKey, false),
    ]);

    if (kDebugMode) {
      print('UserRoleStorageService: Cleared all user data');
    }
  }

  /// Update only the user role (useful for role changes)
  Future<void> updateUserRole(String newRole) async {
    await _ensureInitialized();
    await _prefs!.setString(_userRoleKey, newRole);

    if (kDebugMode) {
      print('UserRoleStorageService: Updated user role to: $newRole');
    }
  }

  /// Update patient ID (useful for caregiver switching patients)
  Future<void> updatePatientId(int? patientId) async {
    await _ensureInitialized();

    if (patientId != null) {
      await _prefs!.setInt(_patientIdKey, patientId);
    } else {
      await _prefs!.remove(_patientIdKey);
    }

    if (kDebugMode) {
      print('UserRoleStorageService: Updated patient ID to: $patientId');
    }
  }

  /// Store patient model as JSON string
  Future<void> storePatientModel(String patientModelJson) async {
    await _ensureInitialized();
    await _prefs!.setString(_patientModelKey, patientModelJson);

    if (kDebugMode) {
      print('UserRoleStorageService: Stored patient model');
    }
  }

  /// Retrieve patient model JSON string
  Future<String?> getPatientModel() async {
    await _ensureInitialized();
    return _prefs!.getString(_patientModelKey);
  }

  /// Store caregiver model as JSON string
  Future<void> storeCaregiverModel(String caregiverModelJson) async {
    await _ensureInitialized();
    await _prefs!.setString(_caregiverModelKey, caregiverModelJson);

    if (kDebugMode) {
      print('UserRoleStorageService: Stored caregiver model');
    }
  }

  /// Retrieve caregiver model JSON string
  Future<String?> getCaregiverModel() async {
    await _ensureInitialized();
    return _prefs!.getString(_caregiverModelKey);
  }

  /// Helper method to ensure service is initialized
  Future<void> _ensureInitialized() async {
    if (_prefs == null) {
      await initialize();
    }
  }

  /// Check if the service has been initialized
  bool get isInitialized => _prefs != null;
}

/// Data class to hold user information
class UserData {
  final String role;
  final int userId;
  final int? patientId;
  final int? caregiverId;
  final bool isLoggedIn;

  const UserData({
    required this.role,
    required this.userId,
    this.patientId,
    this.caregiverId,
    required this.isLoggedIn,
  });

  @override
  String toString() {
    return 'UserData(role: $role, userId: $userId, patientId: $patientId, caregiverId: $caregiverId, isLoggedIn: $isLoggedIn)';
  }

  /// Create a copy with updated values
  UserData copyWith({
    String? role,
    int? userId,
    int? patientId,
    int? caregiverId,
    bool? isLoggedIn,
  }) {
    return UserData(
      role: role ?? this.role,
      userId: userId ?? this.userId,
      patientId: patientId ?? this.patientId,
      caregiverId: caregiverId ?? this.caregiverId,
      isLoggedIn: isLoggedIn ?? this.isLoggedIn,
    );
  }
}
