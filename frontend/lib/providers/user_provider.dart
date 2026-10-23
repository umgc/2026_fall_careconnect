import 'package:care_connect_app/features/dashboard/models/patient_model.dart';
import 'package:flutter/material.dart';
import '../features/emergency_passport/services/qr_code_store.dart';
import '../services/auth_token_manager.dart';
import '../services/auth_service.dart';
import '../services/user_role_storage_service.dart';
import '../models/user_model.dart';
import '../models/patient_model.dart';
import '../models/caregiver_model.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

import 'dart:async'; // Needed for the StreamSubscription
import 'package:connectivity_plus/connectivity_plus.dart';

/// Represents an authenticated user session with basic information.
///
/// This class contains the essential session data obtained during login,
/// including user identification, authentication tokens, and role information.
/// It serves as the foundation for user authentication and authorization.
class UserSession {
  /// Unique user identifier from the authentication system
  final int id;

  /// User's email address (login credential)
  final String email;

  /// User's role in the system (PATIENT, CAREGIVER, etc.)
  final String role;

  /// JWT authentication token for API requests
  final String token;

  /// Associated patient ID (if user has patient role)
  final int? patientId;

  /// Associated caregiver ID (if user has caregiver role)
  final int? caregiverId;

  /// User's display name
  final String? name;

  /// Whether the user's email has been verified
  final bool emailVerified;

  /// Creates a new UserSession instance.
  ///
  /// Parameters:
  /// * [id] - Unique user identifier from the authentication system
  /// * [email] - User's email address (login credential)
  /// * [role] - User's role in the system (PATIENT, CAREGIVER, etc.)
  /// * [token] - JWT authentication token for API requests
  /// * [patientId] - Associated patient ID (optional)
  /// * [caregiverId] - Associated caregiver ID (optional)
  /// * [name] - User's display name (optional)
  /// * [emailVerified] - Whether the user's email has been verified
  UserSession({
    required this.id,
    required this.email,
    required this.role,
    required this.token,
    this.patientId,
    this.caregiverId,
    this.name,
    this.emailVerified = false,
  });

  /// Creates a UserSession from JSON data.
  ///
  /// Factory constructor for deserializing session data from storage
  /// or API responses during authentication.
  ///
  /// Parameters:
  /// * [json] - JSON map containing session data
  ///
  /// Returns:
  /// * UserSession - New session instance from JSON data
  factory UserSession.fromJson(Map<String, dynamic> json) {
    return UserSession(
      id: json['id'],
      email: json['email'],
      role: json['role'],
      token: json['token'] ?? '',
      patientId: json['patientId'],
      caregiverId: json['caregiverId'],
      name: json['name'],
      emailVerified: json['emailVerified'] ?? false,
    );
  }

  /// Converts the UserSession to JSON format.
  ///
  /// Used for session persistence and data serialization.
  /// All session fields are included for complete state preservation.
  ///
  /// Returns:
  /// * Map<String, dynamic> - JSON representation of the session
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'role': role,
      'token': token,
      'patientId': patientId,
      'caregiverId': caregiverId,
      'name': name,
      'emailVerified': emailVerified,
    };
  }

  /// Checks if the user is a family member.
  ///
  /// Returns:
  /// * bool - True if user role is FAMILY_MEMBER
  bool get isFamilyMember => role == 'FAMILY_MEMBER';

  /// Checks if the user is a caregiver.
  ///
  /// Returns:
  /// * bool - True if user role is CAREGIVER
  bool get isCaregiver => role == 'CAREGIVER';

  /// Checks if the user is a patient.
  ///
  /// Returns:
  /// * bool - True if user role is PATIENT
  bool get isPatient => role == 'PATIENT';

  /// Checks if the user has write access permissions.
  ///
  /// Currently only caregivers have write access to modify patient data.
  ///
  /// Returns:
  /// * bool - True if user has write permissions
  bool get hasWriteAccess => role == 'CAREGIVER';
}

/// Provider class managing user authentication state and detailed user models.
///
/// This provider handles the complete user authentication lifecycle including:
/// - Session management and persistence
/// - Token validation and refresh
/// - Role-based user data fetching
/// - User model creation based on role (Patient or Caregiver)
/// - Activity tracking for session management
///
/// The provider follows a two-step authentication process:
/// 1. Initial login creates a UserSession with basic information
/// 2. Detailed user data is fetched based on role and stored in specific models
class UserProvider extends ChangeNotifier {
  /// Current user session containing authentication and basic user data
  UserSession? _user;

  /// Public getter for the current user session
  UserSession? get user => _user;

  /// Loading state indicator for async operations
  bool _isLoading = false;

  /// Public getter for loading state
  bool get isLoading => _isLoading;

  /// Base user model containing core user information
  UserModel? _userModel;

  /// Detailed patient model (populated only for patient users)
  PatientUserModel? _patientModel;

  /// Detailed caregiver model (populated only for caregiver users)
  CaregiverModel? _caregiverModel;

  // BNS 5: Offline Mode
  bool _offlineModeEnabled = true;
  // is the device currently online?
  bool _isDeviceOnline = true;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  // getters

  // get offline mode status (enabled/disabled by user)
  bool get offlineModeEnabled => _offlineModeEnabled;
  // get current hardware connectivity status
  bool get isDeviceOnline => _isDeviceOnline;
  // This returns true if EITHER condition is met
  bool get shouldShowOfflineWarning => !offlineModeEnabled || !_isDeviceOnline;

  var userSession;

  /// Public getter for base user model
  UserModel? get userModel => _userModel;

  /// Public getter for patient model
  PatientUserModel? get patientModel => _patientModel;

  /// Public getter for caregiver model
  CaregiverModel? get caregiverModel => _caregiverModel;

  UserProvider() {
    // The "Start" button for your listener
    _initConnectivity();
  } // end constructor

  /// Updates the offline persistence setting and notifies listeners.
  /// This will trigger the Dashboard banner to show/hide.
  void setOfflineMode(bool enabled) {
    if (_offlineModeEnabled == enabled) return;
    _offlineModeEnabled = enabled;

    notifyListeners();
  }

  /// Initializes the hardware connectivity listener to monitor internet status.
  ///
  /// This method performs two key actions:
  /// 1. **Initial Check**: Queries the current state of the network interface
  ///    immediately upon app/provider initialization.
  /// 2. **Real-time Subscription**: Sets up a [StreamSubscription] to listen
  ///    for hardware changes (e.g., toggling Airplane Mode or losing Wi-Fi).
  ///
  /// When a change is detected, [_updateConnectionStatus] is triggered, which:
  /// - Updates the global `isDeviceOnline` state.
  /// - Forces `offlinePersistenceEnabled` to true if the device goes offline.
  /// - Notifies UI listeners to show/hide the appropriate status banners.
  /// - Logs telemetry for Team B tracking.
  Future<void> _initConnectivity() async {
    final connectivity = Connectivity();
    // Check initial state
    List<ConnectivityResult> result = await connectivity.checkConnectivity();
    _updateConnectionStatus(result);
    // Subscribe to changes (This is the "Heartbeat")
    _connectivitySubscription =
        connectivity.onConnectivityChanged.listen(_updateConnectionStatus);
  }

  /// Processes connectivity changes and manages the "Offline Mode" business logic.
  ///
  /// [results] is a list of [ConnectivityResult] (e.g., wifi, mobile, none).
  ///
  /// Logic Rules:
  /// 1. Determines 'online' status if the list contains anything other than 'none'.
  /// 2. If the device transitions to 'offline':
  ///    - Forces [_offlineModeEnabled] to true (Auto-Reset) to ensure data
  ///      safety during local-only operation.
  ///    - Logs the event for Team B via Telemetry.
  /// 3. Triggers [notifyListeners] only when a state change occurs to avoid
  ///    unnecessary UI repaints.
  void _updateConnectionStatus(List<ConnectivityResult> results) {
    // connectivity_plus 6.0+ returns a list.
    // We are "online" if any result is NOT 'none'
    bool currentlyOnline = !results.contains(ConnectivityResult.none);

    if (_isDeviceOnline != currentlyOnline) {
      _isDeviceOnline = currentlyOnline;
      // If we just lost internet, force the setting back to 'Enabled'
      if (!_isDeviceOnline) {
        _offlineModeEnabled = true;
        // If you are saving this to SharedPreferences, call that save method here too!
        print(
            'DEBUG: Internet lost. Auto-resetting persistence setting to Enabled.');
      }

      print('DEBUG: Hardware Online Status = $_isDeviceOnline');
      notifyListeners(); // This triggers the banner to show/hide in MainScreen
    }
  }

  /// Standard lifecycle method to clean up resources.
  ///
  /// Critically, this cancels the [_connectivitySubscription] to prevent
  /// memory leaks. Without this, the listener would continue to run
  /// in the background even after the Provider is destroyed.
  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  /// Initializes user authentication state from stored data on app start.
  ///
  /// This method is called when the app starts to restore any existing
  /// user session from local storage. It performs the following operations:
  /// - Initializes storage services
  /// - Attempts to restore user session from stored tokens
  /// - Validates session freshness and handles stale sessions
  /// - Fetches detailed user data if session is valid
  ///
  /// Returns:
  /// * Future<void> - Completes when initialization is finished
  Future<void> initializeUser() async {
    _isLoading = true;
    notifyListeners();

    try {
      // Initialize UserRoleStorageService
      await UserRoleStorageService.instance.initialize();

      // Use new JWT authentication system to restore session
      final userSession = await AuthTokenManager.restoreSession();
      if (userSession == null) {
        // No valid session (none, expired or refused): the patient's emergency
        // QR code must not outlive it (DEF-EMG-29).
        await QrCodeStore.clearAll();
      } else {
        _user = UserSession.fromJson(userSession);

        // Update last activity time
        await AuthTokenManager.updateLastActivity();

        // Check if session is stale due to inactivity
        final isStale = await AuthTokenManager.isSessionStale();
        if (isStale) {
          // Session is stale, clear it and force re-login
          await AuthTokenManager.clearAuthData();
          await UserRoleStorageService.instance.clearUserData();
          await QrCodeStore.clearAll(); // DEF-EMG-29
          _user = null;
        } else {
          // Sync user data with UserRoleStorageService
          await _syncUserDataToStorage();
          // Fetch detailed user data based on role
          await fetchUserDetails();
        }
      }
    } catch (e) {
      // If there's an error, clear any stored auth data
      await AuthTokenManager.clearAuthData();
      await UserRoleStorageService.instance.clearUserData();
      await QrCodeStore.clearAll(); // DEF-EMG-29
      _user = null;
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Sets the current user session and updates related state.
  ///
  /// This method is called after successful login to establish the user session.
  /// It performs several important operations:
  /// - Updates the user session
  /// - Records user activity for session tracking
  /// - Synchronizes user data to persistent storage
  /// - Notifies listeners of state changes
  ///
  /// Parameters:
  /// * [user] - The authenticated user session to set
  void setUser(UserSession user) {
    _user = user;
    // Update activity when user is set (e.g., after login)
    AuthTokenManager.updateLastActivity();
    // Sync user data to storage
    _syncUserDataToStorage();
    notifyListeners();
  }

  /// Fetches detailed user information based on the user's role.
  ///
  /// This method is the second step in the authentication process. After
  /// login establishes a basic user session, this method fetches complete
  /// user information including:
  /// - Creates a base UserModel from session data
  /// - Fetches role-specific details (Patient or Caregiver)
  /// - Populates appropriate detailed models
  ///
  /// The method makes API calls to retrieve comprehensive user data
  /// and handles errors gracefully.
  ///
  /// Returns:
  /// * Future<void> - Completes when user details are fetched and models created
  Future<void> fetchUserDetails() async {
    if (_user == null) {
      return;
    }

    _isLoading = true;
    notifyListeners();

    try {
      // Create base UserModel from session data
      _userModel = UserModel(
        name: _user!.name ?? '',
        email: _user!.email,
        userId: _user!.id.toString(),
        role: _user!.role,
      );

      // Fetch detailed data based on role
      if (_user!.role.toUpperCase() == 'PATIENT') {
        await _fetchPatientDetails();
      } else if (_user!.role.toUpperCase() == 'CAREGIVER') {
        await _fetchCaregiverDetails();
      }
    } catch (e) {
      print('Error fetching user details: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Fetch patient-specific details
  Future<void> _fetchPatientDetails() async {
    if (_user == null || _user!.patientId == null) {
      return;
    }

    try {
      final response = await http.get(
        Uri.parse(
          '${ApiConstants.baseUrl}/v1/api/patients/${_user!.patientId}',
        ),
        headers: {
          'Authorization': 'Bearer ${_user!.token}',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final patientData = json.decode(response.body);
        // Create PatientModel with combined data
        _patientModel = PatientUserModel(
          name: '${patientData['firstName']} ${patientData['lastName']}',
          email: _userModel!.email,
          userId: _userModel!.userId,
          role: _userModel!.role,
          firstName: patientData['firstName'] ?? '',
          lastName: patientData['lastName'] ?? '',
          phone: patientData['phone'] ?? '',
          dob: patientData['dob'] ?? '',
          gender: patientData['gender'] ?? '',
          address: Address.fromJson(patientData['address'] ?? {}),
        );

        print(_patientModel.toString());

        // Store patient model to disk
        await UserRoleStorageService.instance.storePatientModel(
          jsonEncode(_patientModel!.toJson()),
        );
      } else {
        // TODO - what to do when user data can't be loaded?
      }
    } catch (e) {
      // TODO - what to do when user data can't be loaded?
    }
  }

  /// Fetch caregiver-specific details
  Future<void> _fetchCaregiverDetails() async {
    if (_user == null || _user!.caregiverId == null) return;

    try {
      final response = await http.get(
        Uri.parse(
            '${ApiConstants.baseUrl}/v1/api/caregivers/${_user!.caregiverId}'),
        headers: {
          'Authorization': 'Bearer ${_user!.token}',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final caregiverData = json.decode(response.body);

        // Create CaregiverModel with combined data
        _caregiverModel = CaregiverModel(
          name: '${caregiverData['firstName']} ${caregiverData['lastname']}',
          email: _userModel!.email,
          userId: _userModel!.userId,
          role: _userModel!.role,
          firstName: caregiverData['first_name'] ?? '',
          lastName: caregiverData['last_name'] ?? '',
          phone: caregiverData['phone'] ?? '',
          dob: caregiverData['dob'] ?? '',
          gender: caregiverData['gender'] ?? '',
          caregiverType: caregiverData['caregiverType'] ?? '',
          address: Address.fromJson(caregiverData['address'] ?? {}),
          professionalInfo: caregiverData['professional'] != null
              ? ProfessionalInfo.fromJson(caregiverData['professional'])
              : null,
        );

        // Store caregiver model to disk
        await UserRoleStorageService.instance.storeCaregiverModel(
          jsonEncode(_caregiverModel!.toJson()),
        );
      }
    } catch (e) {
      print('Error fetching caregiver details: $e');
    }
  }

  /// Clears all user data and authentication state.
  ///
  /// This method performs a complete logout by:
  /// - Clearing the user session
  /// - Removing all user models (base, patient, caregiver)
  /// - Clearing stored authentication tokens
  /// - Clearing cached user data from storage
  /// - Notifying listeners of the state change
  ///
  /// Called during logout or when authentication becomes invalid.
  ///
  /// Returns:
  /// * Future<void> - Completes when all user data is cleared
  Future<void> clearUser() async {
    _user = null;
    _userModel = null;
    _patientModel = null;
    _caregiverModel = null;
    await AuthTokenManager.clearAuthData();
    await UserRoleStorageService.instance.clearUserData();
    await QrCodeStore.clearAll(); // DEF-EMG-11
    notifyListeners();
  }

  // Update user activity for session tracking
  Future<void> updateActivity() async {
    if (_user != null) {
      await AuthTokenManager.updateLastActivity();
    }
  }

  // Check if current session is still valid
  Future<bool> validateSession() async {
    if (_user == null) return false;

    final isValid = await AuthTokenManager.validateCurrentSession();
    if (!isValid) {
      _user = null;
      _userModel = null;
      _patientModel = null;
      _caregiverModel = null;
      await UserRoleStorageService.instance.clearUserData();
      notifyListeners();
    }
    return isValid;
  }

  // Force refresh the JWT token
  Future<bool> refreshToken() async {
    if (_user == null) return false;

    try {
      final refreshedUser = await AuthService.forceRefreshToken();

      if (refreshedUser != null) {
        _user = refreshedUser;
        notifyListeners();
        return true;
      } else {
        // Refresh failed, clear user
        _user = null;
        _userModel = null;
        _patientModel = null;
        _caregiverModel = null;
        await UserRoleStorageService.instance.clearUserData();
        notifyListeners();
        return false;
      }
    } catch (e) {
      _user = null;
      _userModel = null;
      _patientModel = null;
      _caregiverModel = null;
      await UserRoleStorageService.instance.clearUserData();
      notifyListeners();
      return false;
    }
  }

  /// Sync current user data to UserRoleStorageService
  Future<void> _syncUserDataToStorage() async {
    if (_user != null) {
      try {
        await UserRoleStorageService.instance.setUserData(
          role: _user!.role,
          userId: _user!.id,
          patientId: _user!.patientId,
          caregiverId: _user!.caregiverId,
        );
      } catch (e) {
        print('Error syncing user data to storage: $e');
      }
    }
  }

  /// Get user data from storage (useful for navigation)
  Future<UserData?> getUserDataFromStorage() async {
    return await UserRoleStorageService.instance.getUserData();
  }

  /// Update user role in both provider and storage
  Future<void> updateUserRole(String newRole) async {
    if (_user != null) {
      _user = UserSession(
        id: _user!.id,
        email: _user!.email,
        role: newRole,
        token: _user!.token,
        patientId: _user!.patientId,
        caregiverId: _user!.caregiverId,
        name: _user!.name,
        emailVerified: _user!.emailVerified,
      );
      await UserRoleStorageService.instance.updateUserRole(newRole);
      notifyListeners();
    }
  }

  /// Update patient ID in both provider and storage
  Future<void> updatePatientId(int? patientId) async {
    if (_user != null) {
      _user = UserSession(
        id: _user!.id,
        email: _user!.email,
        role: _user!.role,
        token: _user!.token,
        patientId: patientId,
        caregiverId: _user!.caregiverId,
        name: _user!.name,
        emailVerified: _user!.emailVerified,
      );
      await UserRoleStorageService.instance.updatePatientId(patientId);
      notifyListeners();
    }
  }

  bool get isLoggedIn => _user != null;

  bool get isCaregiver => _user?.role.toUpperCase() == 'CAREGIVER';

  // Update user name
  void updateUserName(String newName) {
    if (_user != null) {
      _user = UserSession(
        id: _user!.id,
        email: _user!.email,
        role: _user!.role,
        token: _user!.token,
        patientId: _user!.patientId,
        caregiverId: _user!.caregiverId,
        name: newName,
        emailVerified: _user!.emailVerified,
      );
      notifyListeners();
    }
  }

  bool get isPatient => _user?.role.toUpperCase() == 'PATIENT';

  Future<void> logout() async {}
}
