import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_token_manager.dart';
import 'dart:convert';

/// Migration result status
enum MigrationStatus { success, alreadyMigrated, noDataFound, failed }

/// Migration result with status and optional error message
class MigrationResult {
  final MigrationStatus status;
  final String? errorMessage;

  const MigrationResult(this.status, [this.errorMessage]);

  bool get isSuccess =>
      status == MigrationStatus.success ||
      status == MigrationStatus.alreadyMigrated;
}

/// Utility to migrate from old token storage to new unified system
class AuthMigrationHelper {
  static const FlutterSecureStorage _storage =
      FlutterSecureStorage(webOptions: WebOptions.defaultOptions);

  static Future<String?> _read(String key) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(key);
    }
    return _storage.read(key: key);
  }

  static Future<void> _delete(String key) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
      return;
    }
    await _storage.delete(key: key);
  }

  /// Migrate from old token system to new unified system
  static Future<MigrationResult> migrateAuthData() async {
    try {
      // Check if we already have data in the new system
      final existingToken = await AuthTokenManager.getJwtToken();
      if (existingToken != null) {
        return const MigrationResult(MigrationStatus.alreadyMigrated);
      }

      // Try to migrate from old storage
      String? token;
      Map<String, dynamic>? userSession;

      // Check old JWT token storage
      final oldAuthCookie = await _read('authCookie');
      if (oldAuthCookie != null && oldAuthCookie.isNotEmpty) {
        token = oldAuthCookie;
      }

      // Check old session storage
      final oldSession = await _read('session');
      if (oldSession != null) {
        try {
          final sessionData = jsonDecode(oldSession);
          if (sessionData is Map<String, dynamic>) {
            userSession = sessionData;
          }
        } catch (e) {
          // Continue migration even if session data can't be parsed
          userSession = null;
        }
      }

      // If we have both token and session, migrate them
      if (token != null && userSession != null) {
        await AuthTokenManager.saveAuthData(
          jwtToken: token,
          userSession: userSession,
        );

        await AuthTokenManager.updateLastActivity();

        // Clean up old storage
        await _cleanupOldStorage();

        return const MigrationResult(MigrationStatus.success);
      } else {
        return const MigrationResult(MigrationStatus.noDataFound);
      }
    } catch (e) {
      return MigrationResult(
        MigrationStatus.failed,
        'Migration failed: ${e.toString()}',
      );
    }
  }

  /// Clean up old storage after successful migration
  static Future<bool> _cleanupOldStorage() async {
    try {
      await _delete('authCookie');
      await _delete('session');

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('session_cookie');

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Force clear all auth data (useful for debugging)
  static Future<bool> clearAllAuthData() async {
    try {
      await AuthTokenManager.clearAuthData();
      await _cleanupOldStorage();
      return true;
    } catch (e) {
      return false;
    }
  }
}
