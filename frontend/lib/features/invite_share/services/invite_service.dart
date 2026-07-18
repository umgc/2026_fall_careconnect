import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../../config/env_constant.dart';
import '../../../services/auth_token_manager.dart';
import '../models/invite_result.dart';

/// Talks to the care-circle invite endpoints (issue #53) for the QR share UI
/// (issue #69).
///
/// Follows the app's existing conventions: base URL from getBackendBaseUrl(),
/// JWT auth headers from AuthTokenManager.getAuthHeaders(), and the `http`
/// package for requests.
class InviteService {
  /// Generate a new invite token + URL for [linkId].
  ///
  /// POST /v1/api/care-circle/{linkId}/invite
  /// Optional [invitedEmail], [inviteReason], and [ttlHours] mirror the
  /// backend CreateInviteRequest.
  ///
  /// Throws [InviteException] with an actionable message on failure so the UI
  /// can surface it (acceptance criterion: "Generation failures display
  /// actionable error messages").
  static Future<InviteResult> generateInvite({
    required int linkId,
    String? invitedEmail,
    String? inviteReason,
    int? ttlHours,
  }) async {
    final baseUrl = getBackendBaseUrl();
    final url = Uri.parse('$baseUrl/v1/api/care-circle/$linkId/invite');

    final headers = await AuthTokenManager.getAuthHeaders();

    final body = <String, dynamic>{
      if (invitedEmail != null && invitedEmail.isNotEmpty) 'invitedEmail': invitedEmail,
      if (inviteReason != null && inviteReason.isNotEmpty) 'inviteReason': inviteReason,
      if (ttlHours != null) 'ttlHours': ttlHours,
    };

    http.Response response;
    try {
      response = await http.post(url, headers: headers, body: json.encode(body));
    } catch (e) {
      throw const InviteException(
        'Could not reach the server. Check your connection and try again.',
      );
    }

    switch (response.statusCode) {
      case 200:
      case 201:
        final decoded = json.decode(response.body) as Map<String, dynamic>;
        return InviteResult.fromJson(decoded);
      case 401:
        throw const InviteException('Your session has expired. Please sign in again.');
      case 403:
        throw const InviteException(
          'You do not have permission to create an invite for this care circle.',
        );
      case 404:
        throw const InviteException('That care-circle link could not be found.');
      case 409:
        throw const InviteException(
          'An active invite already exists for this link. Revoke it before creating a new one.',
        );
      default:
        throw InviteException(
          'Could not generate an invite (error ${response.statusCode}). Please try again.',
        );
    }
  }
}

/// Carries a user-facing, actionable message for invite failures.
class InviteException implements Exception {
  final String message;
  const InviteException(this.message);

  @override
  String toString() => message;
}
