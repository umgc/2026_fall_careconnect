import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import '../config/env_constant.dart';

/// Platform-aware key-value storage.
///
/// On native platforms, delegates to [FlutterSecureStorage].
/// On web, delegates to [SharedPreferences] because FlutterSecureStorage
/// requires HTTPS and fails on plain HTTP hosts (e.g. S3 static sites).
class _StorageAdapter {
  static const FlutterSecureStorage _secure = FlutterSecureStorage(
    webOptions: WebOptions.defaultOptions,
  );

  static Future<String?> read(String key) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(key);
    }
    return _secure.read(key: key);
  }

  static Future<void> write(String key, String value) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
      return;
    }
    await _secure.write(key: key, value: value);
  }

  static Future<void> delete(String key) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
      return;
    }
    await _secure.delete(key: key);
  }
}

class AuthTokenManager {
  static const String _jwtTokenKey = 'jwt_token';
  static const String _userSessionKey = 'user_session';
  static const String _tokenExpiryKey = 'token_expiry';

  // Store JWT token and user session
  static Future<void> saveAuthData({
    required String jwtToken,
    required Map<String, dynamic> userSession,
  }) async {
    try {
      await _StorageAdapter.write(_jwtTokenKey, jwtToken);
      await _StorageAdapter.write(
        _userSessionKey,
        jsonEncode(userSession),
      );

      // Extract expiry from JWT if possible (optional)
      final tokenParts = jwtToken.split('.');
      if (tokenParts.length == 3) {
        try {
          final payload = jsonDecode(
            utf8.decode(base64Url.decode(base64Url.normalize(tokenParts[1]))),
          );
          if (payload['exp'] != null) {
            await _StorageAdapter.write(
              _tokenExpiryKey,
              payload['exp'].toString(),
            );
          }
        } catch (e) {
          // JWT parsing failed, continue without expiry tracking
        }
      }
    } catch (e) {
      throw Exception('Failed to save authentication data: ${e.toString()}');
    }
  }

  // Get JWT token
  static Future<String?> getJwtToken() async {
    try {
      final token = await _StorageAdapter.read(_jwtTokenKey);
      if (token != null && await _isTokenValid(token)) {
        return token;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // Get user session data
  static Future<Map<String, dynamic>?> getUserSession() async {
    try {
      final sessionData = await _StorageAdapter.read(_userSessionKey);
      if (sessionData != null) {
        return jsonDecode(sessionData);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // Check if token is valid (not expired)
  static Future<bool> _isTokenValid(String token) async {
    try {
      final expiryStr = await _StorageAdapter.read(_tokenExpiryKey);
      if (expiryStr != null) {
        final expiry = int.parse(expiryStr);
        final currentTime = DateTime.now().millisecondsSinceEpoch ~/ 1000;

        const bufferTime = 5 * 60;
        return currentTime < (expiry - bufferTime);
      }

      return await _validateTokenWithBackend(token);
    } catch (e) {
      return false;
    }
  }

  // Validate token with backend (for cases where we don't have expiry info)
  static Future<bool> _validateTokenWithBackend(String token) async {
    try {
      // Make a lightweight API call to validate token
      final headers = {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };
      final response = await http
          .get(
            Uri.parse('${getBackendBaseUrl()}/v1/api/auth/validate-token'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 10));

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // Get authorization headers
  static Future<Map<String, String>> getAuthHeaders() async {
    final headers = <String, String>{'Content-Type': 'application/json'};

    final token = await getJwtToken();
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }

    return headers;
  } // Clear all auth data

  static Future<void> clearAuthData() async {
    try {
      await _StorageAdapter.delete(_jwtTokenKey);
      await _StorageAdapter.delete(_userSessionKey);
      await _StorageAdapter.delete(_tokenExpiryKey);
      await _StorageAdapter.delete('last_activity');

      // Also clear old session data for migration
      await _StorageAdapter.delete('session');
      await _StorageAdapter.delete('authCookie');

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('session_cookie');
    } catch (e) {
      print('Error clearing auth data: $e');
    }
  }

  // Check if user is authenticated
  static Future<bool> isAuthenticated() async {
    final token = await getJwtToken();
    return token != null;
  }

  // Validate current session and clean up if invalid
  static Future<bool> validateCurrentSession() async {
    try {
      final token = await _StorageAdapter.read(_jwtTokenKey);
      if (token == null) {
        return false;
      }

      final isValid = await _isTokenValid(token);
      if (!isValid) {
        // Token is invalid/expired, clear all auth data
        await clearAuthData();
        return false;
      }

      return true;
    } catch (e) {
      print('Error validating current session: $e');
      await clearAuthData(); // Clear on error for security
      return false;
    }
  }

  // Handle app startup - validate existing session
  static Future<Map<String, dynamic>?> restoreSession() async {
    try {
      final isValidSession = await validateCurrentSession();
      if (!isValidSession) {
        return null;
      }

      return await getUserSession();
    } catch (e) {
      print('Error restoring session: $e');
      return null;
    }
  }

  // Mark last activity time (for session tracking)
  static Future<void> updateLastActivity() async {
    try {
      final currentTime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await _StorageAdapter.write('last_activity', currentTime.toString());
    } catch (e) {
      print('Error updating last activity: $e');
    }
  }

  // Check if session has been inactive for too long
  static Future<bool> isSessionStale({int maxInactiveMinutes = 60}) async {
    try {
      final lastActivityStr = await _StorageAdapter.read('last_activity');
      if (lastActivityStr == null) {
        return false; // No activity recorded yet
      }

      final lastActivity = int.parse(lastActivityStr);
      final currentTime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final inactiveSeconds = currentTime - lastActivity;
      final maxInactiveSeconds = maxInactiveMinutes * 60;

      return inactiveSeconds > maxInactiveSeconds;
    } catch (e) {
      print('Error checking session staleness: $e');
      return false;
    }
  }
}
