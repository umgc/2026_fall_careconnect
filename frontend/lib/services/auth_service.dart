/// Centralized Auth Guard Service for page protection
// ignore_for_file: avoid_print

library;

import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:app_links/app_links.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../config/env_constant.dart';
import 'api_service.dart';
import 'oauth_service.dart';
import '../providers/user_provider.dart';
import 'messaging_service.dart';
import 'auth_token_manager.dart';
import 'user_role_storage_service.dart';
import 'dart:io';

class ApiConstants {
  static final String _host = getBackendBaseUrl();
  static final String auth = '$_host/v1/api/auth';
  static final String caregivers = '$_host/v1/api/caregivers';
  static final String users = '$_host/v1/api/users';
  static final String webBaseUrl = getWebBaseUrl();
  static String get baseUrl => _host;
}

class AuthService {
  // Stream for listening to deep links (OAuth callbacks)
  static StreamSubscription<Uri>? _linkSubscription;
  static late AppLinks _appLinks;

  // Singleton instance for the new UserRoleStorageService integration
  static AuthService? _instance;

  static AuthService get instance {
    _instance ??= AuthService._internal();
    return _instance!;
  }

  AuthService._internal();

  /// Initialize the auth service and storage
  static Future<void> initialize() async {
    await UserRoleStorageService.instance.initialize();
  }

  /// Handle OAuth callback from deep link
  static Future<void> handleOAuthCallback(String code, String state) async {
    try {
      // This method can be used for additional callback handling if needed
      // For now, the main logic is in loginWithGoogle()
      print('OAuth callback received: code=$code, state=$state');
    } catch (e) {
      print('Error handling OAuth callback: $e');
    }
  }

  /// GOOGLE OAUTH2 LOGIN - Backend-first OAuth2 flow
  static Future<UserSession> loginWithGoogle(AppLocalizations t) async {
    try {
      // Initialize app links if not already done
      _appLinks = AppLinks();

      // Clear any existing OAuth session
      OAuthService.clearSession();

      // Launch the OAuth2 flow (redirects to backend, then Google, then back)
      await OAuthService.launchGoogleOAuth();

      // Listen for the deep link callback from the backend
      final completer = Completer<UserSession>();

      _linkSubscription = _appLinks.uriLinkStream.listen(
        (Uri uri) async {
          try {
            // Check if this is our OAuth callback
            if (uri.scheme == 'careconnect' &&
                uri.host == 'oauth' &&
                uri.path == '/callback') {
              // Extract the JWT token and user data from the callback URL
              final token = uri.queryParameters['token'];
              final error = uri.queryParameters['error'];

              if (error != null) {
                completer.completeError(Exception('${t.authservice_oauthError}}: $error'));
                return;
              }

              if (token == null) {
                completer.completeError(
                  Exception(t.authservice_jwtTokenMissing),
                );
                return;
              }

              // The backend has already validated the Google token and generated JWT
              // Now we just need to parse the user session and save the token
              final userDataString = uri.queryParameters['user'];
              if (userDataString == null) {
                completer.completeError(
                  Exception(t.authservice_userDataMissing),
                );
                return;
              }

              // Decode the user data
              final userData = jsonDecode(Uri.decodeComponent(userDataString));

              // Create user session
              final userSession = UserSession.fromJson(userData);

              // Force update JWT token and session using the new token manager
              // This ensures fresh tokens are always used after OAuth login
              await AuthTokenManager.saveAuthData(
                jwtToken: token,
                userSession: userSession.toJson(),
              );

              // Update last activity time to track session freshness
              await AuthTokenManager.updateLastActivity();

              // Store user data in UserRoleStorageService for navigation
              await _storeUserDataFromSession(userSession);

              print('Google OAuth login successful: JWT token force-updated');

              // Create and return the user session
              completer.complete(userSession);
            }
          } catch (e) {
            completer.completeError(e);
          } finally {
            _linkSubscription?.cancel();
            _linkSubscription = null;
            OAuthService.clearSession();
          }
        },
        onError: (err) {
          completer.completeError(err);
          _linkSubscription?.cancel();
          _linkSubscription = null;
          OAuthService.clearSession();
        },
      );

      // Set a timeout for the OAuth flow
      Timer(const Duration(minutes: 5), () {
        if (!completer.isCompleted) {
          _linkSubscription?.cancel();
          _linkSubscription = null;
          OAuthService.clearSession();
          completer.completeError(Exception(t.authservice_oauthTimedOut));
        }
      });

      return await completer.future;
    } catch (e) {
      _linkSubscription?.cancel();
      _linkSubscription = null;
      OAuthService.clearSession();
      rethrow;
    }
  }

  /// LOGIN - Updated to return UserSession and handle JWT
  static Future<UserSession> login(String email, String password, AppLocalizations t) async {
    final response = await ApiService.login(email, password);
    final data = jsonDecode(response.body);

    if (response.statusCode == 200) {
      final userSession = UserSession.fromJson(data);

      // Force update JWT token and session using the new token manager
      // This ensures fresh tokens are always used after login
      await AuthTokenManager.saveAuthData(
        jwtToken: userSession.token,
        userSession: userSession.toJson(),
      );

      // Update last activity time to track session freshness
      await AuthTokenManager.updateLastActivity();

      // Store user data in UserRoleStorageService for navigation
      await _storeUserDataFromSession(userSession);

      // Register user to WebSocket for notifications
      try {
        await MessagingService.registerUser(userId: userSession.id.toString());
      } catch (e) {
        print('Warning: Failed to register user to WebSocket: $e');
      }

      print('Login successful: JWT token force-updated');

      return userSession;
    } else {
      throw Exception(data['error'] ?? t.authservice_loginFailedError);
    }
  }

  static Future<String> register({
    required String name,
    required String email,
    required String password,
    String role = 'PATIENT',
    required String verificationBaseUrl,
    required AppLocalizations t
  }) async {
    final headers = {'Content-Type': 'application/json'};

    final response = await http.post(
      Uri.parse('${ApiConstants.auth}/register'),
      headers: headers,
      body: jsonEncode({
        'name': name,
        'email': email,
        'password': password,
        'role': role.toUpperCase(),
        'verificationBaseUrl': verificationBaseUrl,
      }),
    );

    final data = jsonDecode(response.body);

    if (response.statusCode == 201 || response.statusCode == 200) {
      print("Registration: $data");
      // If backend returns a string: just return it
      if (data is String) return data;
      // If backend returns JSON: extract a message
      return data['message'] ??
          t.authservice_emailRegistrationSuccess;
    } else {
      print("Registration Error: $data");
      throw Exception(data['error'] ?? t.authservice_emailRegistrationFailed);
    }
  }

  static Future<Map<String, dynamic>> registerCaregiver({
    required String firstName,
    required String lastName,
    required String email,
    required String password,
    required AppLocalizations t,
    String? dob,
    String? phone,
    String? gender,
    String? licenseNumber,
    String? issuingState,
    int? yearsExperience,
    String? addressLine1,
    String? addressLine2,
    String? city,
    String? state,
    String? zip,
  }) async {
    final headers = {'Content-Type': 'application/json'};

    // Build registration data with null safety
    final Map<String, dynamic> registrationData = {
      'firstName': firstName,
      'lastName': lastName,
      'dob': dob ?? "01/01/1990",
      'email': email,
      'phone': phone ?? "000-000-0000",
      'gender': (gender ?? "").toUpperCase(),
    };

    print('Debug: Basic data added successfully');

    // Only add professional info if at least license number is provided
    if (licenseNumber != null && licenseNumber.isNotEmpty) {
      print('🔍 Debug: Adding professional info...');
      registrationData['professional'] = {
        'licenseNumber': licenseNumber,
        'issuingState': issuingState ?? "VA",
        'yearsExperience': yearsExperience ?? 1,
      };
      print('Debug: Professional info added successfully');
    }

    // Only add address if at least line1 is provided
    if (addressLine1 != null && addressLine1.isNotEmpty) {
      print('🔍 Debug: Adding address info...');
      registrationData['address'] = {
        'line1': addressLine1,
        'line2': addressLine2 ?? "",
        'city': city ?? "City",
        'state': state ?? "VA",
        'zip': zip ?? "00000",
        'phone': phone ?? "000-000-0000",
      };
      print('Debug: Address info added successfully');
    }

    // Always add credentials
    registrationData['credentials'] = {'email': email, 'password': password};

    print('Debug: About to encode registration data...');
    print('Registration data keys: ${registrationData.keys}');

    try {
      final jsonString = jsonEncode(registrationData);
      print('Registering caregiver with data: $jsonString');
    } catch (jsonError) {
      print('JSON encoding failed: $jsonError');
      throw Exception('${t.authservice_dataSerialError}: $jsonError');
    }

    try {
      print('Debug: About to make HTTP POST request...');
      print('Debug: getBackendBaseUrl(): ${getBackendBaseUrl()}');
      print('Debug: ApiConstants.caregivers: ${ApiConstants.caregivers}');
      print('Debug: URL: ${ApiConstants.caregivers}');
      print('Debug: Headers: $headers');

      final response = await http.post(
        Uri.parse(ApiConstants.caregivers),
        headers: headers,
        body: jsonEncode(registrationData),
      );

      print('Debug: HTTP request completed successfully');
      print('Response status: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print("Caregiver Registration: $data");

        // Extract user ID and paymentCustomerId from the nested user object
        String userId = '0';
        String paymentCustomerId = '';
        if (data.containsKey('user') && data['user'] is Map<String, dynamic>) {
          final userObj = data['user'] as Map<String, dynamic>;
          userId = userObj['id']?.toString() ?? '0';
          paymentCustomerId = userObj['paymentCustomerId'] ?? '';
          print("Extracted User ID: $userId from nested user object");
          print(
            "Extracted Payment Customer ID: $paymentCustomerId from nested user object",
          );
        } else {
          print(" Warning: User object not found in registration response");
        }

        // Return both the success message and the user info
        return {
          'message': t.authservice_caregiverRegistrationSuccessMessage,
          'userId': userId, // Use the user ID from the nested user object
          'caregiverId':
              data['id']?.toString() ?? '0', // Also store the caregiver ID
          'paymentCustomerId': paymentCustomerId, // Include Payment customer ID
        };
      } else {
        final data = jsonDecode(response.body);
        print(
          "Caregiver Registration failed: ${response.statusCode} - ${response.body}",
        );
        throw Exception(data['error'] ?? t.authservice_caregiverRegistrationFailedMessage);
      }
    } catch (e) {
      print('Exception during caregiver registration: $e');
      rethrow;
    }
  }

  static Future<String> verifyEmail(String token, AppLocalizations t) async {
    final headers = {'Content-Type': 'application/json'};

    final response = await http.post(
      Uri.parse('${ApiConstants.auth}/verify'),
      headers: headers,
      body: jsonEncode({'token': token}),
    );

    final data = jsonDecode(response.body);

    if (response.statusCode == 200) {
      print("Email verification: $data");
      return data['message'] ?? t.authservice_emailVerifiedSuccess;
    } else {
      print("Email verification error: $data");
      throw Exception(data['error'] ?? t.authservice_emailVerifiedFailed);
    }
  }

  static Future<String> requestPasswordReset({required String email, required AppLocalizations t}) async {
    try {
      // Fix: Use ApiConstants.auth which includes the full path
      final fullUrl = '${ApiConstants.auth}/password/forgot';
      print('Request password reset URL: $fullUrl');

      final response = await http.post(
        Uri.parse(fullUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        return responseData['message'] ??
            t.authservice_passwordResetLinkSent;
      } else {
        final errorData = jsonDecode(response.body);
        throw Exception(errorData['message'] ?? t.authservice_passwordResetLinkFailed);
      }
    } catch (e) {
      throw Exception('${t.authservice_networkError}: ${e.toString()}');
    }
  }

  static Future<String> resetPassword({
    required String email,
    required String resetToken,
    required String newPassword,
    required AppLocalizations t,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConstants.users}/reset-password'), // Correct endpoint
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'username': email, // Use email as username
          'resetToken': resetToken, // 48-character token from email
          'newPassword': newPassword,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        print("Password reset successful: $data");
        return data['message'] ?? t.authservice_passwordResetSuccess;
      } else {
        print(
          "Password reset error: ${response.statusCode} - ${response.body}",
        );
        final errorMessage =
            data['error'] ?? data['message'] ?? t.authservice_passwordResetFailed;

        // Handle specific error cases
        if (errorMessage.toLowerCase().contains('expired')) {
          throw Exception(
            t.authservice_passwordResetLinkExpired,
          );
        } else if (errorMessage.toLowerCase().contains('invalid')) {
          throw Exception(
            t.authservice_passwordResetTokenInvalid,
          );
        }

        throw Exception(errorMessage);
      }
    } catch (e) {
      print("Password reset exception: $e");
      rethrow;
    }
  }

  static Future<void> logout() async {
    final headers = await AuthTokenManager.getAuthHeaders();

    final response = await http.post(
      Uri.parse('${ApiConstants.auth}/logout'),
      headers: headers,
    );

    // Clear all auth data using the new token manager
    await AuthTokenManager.clearAuthData();

    // Clear user data from UserRoleStorageService
    await UserRoleStorageService.instance.clearUserData();

    if (response.statusCode == 200) {
      print("Logout successful");
    } else {
      print("Logout failed: ${response.statusCode} - ${response.body}");
    }
  }

  /// PROCESS OAUTH CALLBACK - For web-based callbacks
  static Future<UserSession> processOAuthCallback({
    required String token,
    required String userDataString,
    required AppLocalizations t,
  }) async {
    try {
      // Parse user data (it's URL encoded)
      final userData = jsonDecode(Uri.decodeComponent(userDataString));

      // Create user session
      final userSession = UserSession.fromJson(userData);

      // Force update JWT token and session using the new token manager
      // This ensures fresh tokens are always used after OAuth callback
      await AuthTokenManager.saveAuthData(
        jwtToken: token,
        userSession: userSession.toJson(),
      );

      // Update last activity time to track session freshness
      await AuthTokenManager.updateLastActivity();

      // Store user data in UserRoleStorageService for navigation
      await _storeUserDataFromSession(userSession);

      print('OAuth callback processed: JWT token force-updated');

      // Create and return the user session
      return userSession;
    } catch (e) {
      throw Exception('${t.authservice_failedToProcessOAuthCall}: $e');
    }
  }

  /// FORCE REFRESH JWT TOKEN - For scenarios where token needs to be refreshed
  static Future<UserSession?> forceRefreshToken() async {
    try {
      final currentToken = await AuthTokenManager.getJwtToken();
      if (currentToken == null) {
        print('No existing token to refresh');
        return null;
      }

      // Make a call to backend to refresh the token
      final headers = await AuthTokenManager.getAuthHeaders();
      final response = await http.post(
        Uri.parse('${ApiConstants.auth}/refresh-token'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final userSession = UserSession.fromJson(data);

        // Force update with new JWT token
        await AuthTokenManager.saveAuthData(
          jwtToken: userSession.token,
          userSession: userSession.toJson(),
        );

        // Update last activity time
        await AuthTokenManager.updateLastActivity();

        // Update user data in UserRoleStorageService
        await _storeUserDataFromSession(userSession);

        print('JWT token force-refreshed successfully');
        return userSession;
      } else {
        print('Token refresh failed: ${response.statusCode}');
        // If refresh fails, clear auth data to force re-login
        await AuthTokenManager.clearAuthData();
        await UserRoleStorageService.instance.clearUserData();
        return null;
      }
    } catch (e) {
      print('Error during token refresh: $e');
      // Clear auth data on error to force re-login
      await AuthTokenManager.clearAuthData();
      await UserRoleStorageService.instance.clearUserData();
      return null;
    }
  }

  /// UPDATE USER ACTIVITY - For tracking session activity
  static Future<void> updateUserActivity() async {
    await AuthTokenManager.updateLastActivity();
  }

  static Future<bool> checkAndRedirectIfUnauthenticated(
    BuildContext context, {
    String loginRoute = '/login',
  }) async {
    final isAuth = await AuthTokenManager.isAuthenticated();
    if (!isAuth && context.mounted) {
      context.go(loginRoute);
      return false;
    }
    return true;
  }

  /// Store user data from UserSession to UserRoleStorageService
  static Future<void> _storeUserDataFromSession(UserSession userSession) async {
    try {
      await UserRoleStorageService.instance.setUserData(
        role: userSession.role,
        userId: userSession.id,
        patientId: userSession.patientId,
        caregiverId: userSession.caregiverId,
      );

      if (kDebugMode) {
        print(
          'User data stored in UserRoleStorageService: Role=${userSession.role}, UserID=${userSession.id}',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error storing user data in UserRoleStorageService: $e');
      }
    }
  }

  /// Get current user data from UserRoleStorageService
  static Future<UserData?> getCurrentUserData() async {
    return await UserRoleStorageService.instance.getUserData();
  }

  /// Check if user is authenticated using UserRoleStorageService
  static Future<bool> isUserAuthenticated() async {
    return await UserRoleStorageService.instance.isLoggedIn();
  }

  /// Get user role from storage
  static Future<String?> getUserRole() async {
    return await UserRoleStorageService.instance.getUserRole();
  }

  /// Update user role in storage
  static Future<void> updateUserRole(String newRole) async {
    await UserRoleStorageService.instance.updateUserRole(newRole);

    if (kDebugMode) {
      print('User role updated in UserRoleStorageService: $newRole');
    }
  }

  /// Update patient ID in storage (useful for caregiver switching patients)
  static Future<void> updatePatientId(int? patientId) async {
    await UserRoleStorageService.instance.updatePatientId(patientId);

    if (kDebugMode) {
      print('Patient ID updated in UserRoleStorageService: $patientId');
    }
  }

  /// Get Alexa authorization code for OAuth flow
  ///
  /// Calls the backend endpoint: POST /v1/api/auth/sso/alexa/code
  /// Requires Bearer token in Authorization header
  /// Returns the temporary authorization code to redirect to Alexa
  static Future<Map<String, dynamic>> getAlexaAuthorizationCode({
    required String token,
    required AppLocalizations t,
  }) async {
    try {
      final endpoint = '${ApiConstants.auth}/sso/alexa/code';

      final response = await http
          .post(
            Uri.parse(endpoint),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw SocketException(t.authservice_socketTimeout),
          );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        // Success: {"code": "temp-code-123"}
        return {
          'isSuccess': true,
          'code': data['code'],
          'message': t.authservice_authCodeGeneratedSuccess,
        };
      } else if (response.statusCode == 401) {
        // Unauthorized: {"error": "missing_token"} or {"error": "invalid_token"}
        return {
          'isSuccess': false,
          'code': null,
          'message': data['error'] ?? t.authservice_authInvalidToken,
        };
      } else {
        // Other errors
        return {
          'isSuccess': false,
          'code': null,
          'message': data['error'] ?? t.authservice_authFailedToGenCode,
        };
      }
    } on SocketException catch (e) {
      return {
        'isSuccess': false,
        'code': null,
        'message': '${t.authservice_networkError}: ${e.message}',
      };
    } catch (e) {
      return {
        'isSuccess': false,
        'code': null,
        'message': '${t.voicecommand_phaseLabelError}: ${e.toString()}',
      };
    }
  }

  static Future<Map<String, dynamic>> unlinkAlexaAccount(AppLocalizations t) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    headers['Content-Type'] = 'application/json';

    final host = getBackendBaseUrl(); // ✅ pulls from your env config
    final uri = Uri.parse('$host/v1/api/auth/sso/alexa/unlink');

    try {
      print("🧩 PATCH $uri");
      final response = await http
          .post(uri, headers: headers, body: jsonEncode({}))
          .timeout(const Duration(seconds: 15));

      print(
        "🔌 Alexa unlink response: ${response.statusCode} - ${response.body}",
      );

      if (response.statusCode == 200) {
        return {
          'isSuccess': true,
          'message': t.authservice_alexaUnlinkedSuccess,
        };
      } else {
        final body = jsonDecode(response.body);
        return {
          'isSuccess': false,
          'message': body['error'] ?? t.authservice_alexaUnlinkedSuccess,
        };
      }
    } catch (e) {
      print('❌ Exception during unlinkAlexaAccount: $e');
      return {
        'isSuccess': false,
        'message': '${t.authservice_unexpectedError}: $e',
      };
    }
  }

  /// Get current user session from storage
  static Future<UserSession?> getCurrentUser() async {
    try {
      final userData = await AuthTokenManager.getUserSession();
      if (userData == null) return null;
      return UserSession.fromJson(userData);
    } catch (e) {
      print('Error getting current user: $e');
      return null;
    }
  }
}
