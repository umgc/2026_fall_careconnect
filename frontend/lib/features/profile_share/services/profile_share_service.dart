import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../../config/env_constant.dart';
import '../../../services/auth_token_manager.dart';
import '../models/profile_share_result.dart';

class ProfileShareService {
  /// POST /v1/api/patients/me/profile-share
  static Future<ProfileShareResult> createShare({int? ttlHours}) async {
    final baseUrl = getBackendBaseUrl();
    final url = Uri.parse('$baseUrl/v1/api/patients/me/profile-share');
    final headers = await AuthTokenManager.getAuthHeaders();
    final body = <String, dynamic>{
      if (ttlHours != null) 'ttlHours': ttlHours,
    };

    http.Response response;
    try {
      response = await http.post(url, headers: headers, body: json.encode(body));
    } catch (_) {
      throw const ProfileShareException(
        'Could not reach the server. Check your connection and try again.',
      );
    }

    switch (response.statusCode) {
      case 200:
      case 201:
        final decoded = json.decode(response.body) as Map<String, dynamic>;
        return ProfileShareResult.fromJson(decoded);
      case 401:
        throw const ProfileShareException(
          'Your session has expired. Please sign in again.',
        );
      case 403:
        throw const ProfileShareException(
          'Only patients can create a profile share link.',
        );
      case 409:
        throw const ProfileShareException(
          'An active share link already exists. Revoke it before creating a new one.',
        );
      default:
        throw ProfileShareException(
          'Could not create a share link (error ${response.statusCode}). Please try again.',
        );
    }
  }

  /// DELETE /v1/api/patients/me/profile-share/{tokenId}
  static Future<void> revokeShare(int tokenId, {String? reason}) async {
    final baseUrl = getBackendBaseUrl();
    final url =
        Uri.parse('$baseUrl/v1/api/patients/me/profile-share/$tokenId');
    final headers = await AuthTokenManager.getAuthHeaders();
    final body = <String, dynamic>{
      if (reason != null && reason.isNotEmpty) 'reason': reason,
    };

    http.Response response;
    try {
      response = await http.delete(
        url,
        headers: headers,
        body: json.encode(body),
      );
    } catch (_) {
      throw const ProfileShareException(
        'Could not reach the server. Check your connection and try again.',
      );
    }

    if (response.statusCode != 204 && response.statusCode != 200) {
      throw ProfileShareException(
        'Could not revoke the share link (error ${response.statusCode}).',
      );
    }
  }

  /// GET /v1/api/profile-share/{token} (public)
  static Future<Map<String, dynamic>> resolveShare(String token) async {
    final baseUrl = getBackendBaseUrl();
    final url = Uri.parse('$baseUrl/v1/api/profile-share/$token');

    http.Response response;
    try {
      response = await http.get(url, headers: {'Content-Type': 'application/json'});
    } catch (_) {
      throw const ProfileShareException(
        'Could not reach the server. Check your connection and try again.',
      );
    }

    if (response.statusCode != 200) {
      throw ProfileShareException(
        'Could not open this share link (error ${response.statusCode}).',
      );
    }
    return json.decode(response.body) as Map<String, dynamic>;
  }
}

class ProfileShareException implements Exception {
  final String message;
  const ProfileShareException(this.message);

  @override
  String toString() => message;
}
