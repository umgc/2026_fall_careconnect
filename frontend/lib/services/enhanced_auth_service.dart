import 'package:care_connect_app/l10n/app_localizations.dart';

import '../services/auth_service.dart';
import '../services/role_validator.dart';
import '../providers/user_provider.dart';

/// Enhanced authentication service with role validation
class EnhancedAuthService {
  /// Login with role validation
  /// This method performs login and validates that the user's actual role matches the expected role
  static Future<AuthResult> loginWithRoleValidation({
    required String email,
    required String password,
    required AppLocalizations t
  }) async {
    try {
      // Perform the actual login
      final userSession = await AuthService.login(
        email,
        password,
        t,
      );

      // Validate the role after successful login
      // final validationResult = RoleValidator.validateUserRole(
      //   userSession: userSession,
      //   expectedRole: expectedRole
      // );

      // if (!validationResult.isValid) {
      //   // Role mismatch - clear any stored tokens and return error
      //   await _clearAuthenticationData();
      //
      //   return AuthResult.roleValidationFailure(
      //     message: validationResult.errorMessage!,
      //     actualRole: validationResult.actualRole!,
      //     expectedRole: validationResult.expectedRole!,
      //     correctLoginRoute: RoleValidator.getCorrectLoginRoute(
      //       validationResult.actualRole!,
      //     ),
      //   );
      // }

      // Role validation successful
      return AuthResult.success(userSession: userSession);
    } catch (e) {
      // Handle authentication errors
      return AuthResult.authenticationFailure(
        message: 'Login failed: ${e.toString()}',
      );
    }
  }

  /// Google OAuth login with role validation
  static Future<AuthResult> loginWithGoogleAndRoleValidation({
    required String expectedRole,
    required AppLocalizations loc
  }) async {
    try {
      // Perform Google OAuth login
      final userSession = await AuthService.loginWithGoogle(loc);

      // Validate the role after successful login
      final validationResult = RoleValidator.validateUserRole(
        expectedRole: expectedRole,
        userSession: userSession,
      );

      if (!validationResult.isValid) {
        // Role mismatch - clear any stored tokens and return error
        await _clearAuthenticationData();

        return AuthResult.roleValidationFailure(
          message: validationResult.errorMessage!,
          actualRole: validationResult.actualRole!,
          expectedRole: validationResult.expectedRole!,
          correctLoginRoute: RoleValidator.getCorrectLoginRoute(
            validationResult.actualRole!,
          ),
        );
      }

      // Role validation successful
      return AuthResult.success(userSession: userSession);
    } catch (e) {
      // Handle authentication errors
      return AuthResult.authenticationFailure(
        message: 'Google Sign-In failed: ${e.toString()}',
      );
    }
  }

  /// Clear authentication data when role validation fails
  static Future<void> _clearAuthenticationData() async {
    try {
      // Clear stored tokens and user session
      await AuthService.logout();
    } catch (e) {
      print('Error clearing authentication data: $e');
    }
  }
}

/// Result of authentication with role validation
class AuthResult {
  final bool isSuccess;
  final UserSession? userSession;
  final String? errorMessage;
  final AuthErrorType? errorType;
  final String? actualRole;
  final String? expectedRole;
  final String? correctLoginRoute;

  AuthResult._({
    required this.isSuccess,
    this.userSession,
    this.errorMessage,
    this.errorType,
    this.actualRole,
    this.expectedRole,
    this.correctLoginRoute,
  });

  factory AuthResult.success({required UserSession userSession}) {
    return AuthResult._(isSuccess: true, userSession: userSession);
  }

  factory AuthResult.authenticationFailure({required String message}) {
    return AuthResult._(
      isSuccess: false,
      errorMessage: message,
      errorType: AuthErrorType.authentication,
    );
  }

  factory AuthResult.roleValidationFailure({
    required String message,
    required String actualRole,
    required String expectedRole,
    required String correctLoginRoute,
  }) {
    return AuthResult._(
      isSuccess: false,
      errorMessage: message,
      errorType: AuthErrorType.roleValidation,
      actualRole: actualRole,
      expectedRole: expectedRole,
      correctLoginRoute: correctLoginRoute,
    );
  }
}

/// Types of authentication errors
enum AuthErrorType { authentication, roleValidation }
