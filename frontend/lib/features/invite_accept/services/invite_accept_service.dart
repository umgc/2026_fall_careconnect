import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../../config/env_constant.dart';
import '../../../services/auth_token_manager.dart';
import '../models/invite_preview.dart';

/// Invite acceptance handoff (issue #75).
///
/// Wraps the public preview (#59) and authenticated accept (#53) endpoints.
/// Follows the app conventions: base URL from getBackendBaseUrl(), JWT headers
/// from AuthTokenManager.getAuthHeaders(), and the `http` package.
class InviteAcceptService {
  /// Public, non-enumerating preview. Never throws for token state — an
  /// invalid/expired/revoked token comes back as a preview with valid=false.
  /// Throws [InviteAcceptException] only on a network/transport failure.
  static Future<InvitePreview> preview(String token) async {
    final baseUrl = getBackendBaseUrl();
    final url = Uri.parse('$baseUrl/v1/api/invite/$token');

    http.Response response;
    try {
      response = await http.get(url);
    } catch (e) {
      throw const InviteAcceptException(
        'Could not reach the server. Check your connection and try again.',
      );
    }

    if (response.statusCode == 200) {
      return InvitePreview.fromJson(json.decode(response.body) as Map<String, dynamic>);
    }
    // The preview endpoint is designed to always return 200; anything else is
    // an unexpected server problem.
    throw InviteAcceptException(
      'Could not load this invitation (error ${response.statusCode}).',
    );
  }

  /// Accept the invite as the currently authenticated user.
  ///
  /// Returns the linkId of the care circle the user joined. Requires a valid
  /// JWT (the caller must ensure the user is signed in first). Maps backend
  /// status codes to actionable [InviteAcceptException] messages.
  static Future<int> accept(String token) async {
    final baseUrl = getBackendBaseUrl();
    final url = Uri.parse('$baseUrl/v1/api/invite/$token/accept');
    final headers = await AuthTokenManager.getAuthHeaders();

    http.Response response;
    try {
      response = await http.post(url, headers: headers);
    } catch (e) {
      throw const InviteAcceptException(
        'Could not reach the server. Check your connection and try again.',
      );
    }

    switch (response.statusCode) {
      case 200:
      case 201:
        final decoded = json.decode(response.body) as Map<String, dynamic>;
        return (decoded['linkId'] as num?)?.toInt() ?? -1;
      case 401:
        throw const InviteAcceptException(
          'Please sign in to accept this invitation.',
        );
      case 403:
        throw const InviteAcceptException(
          'This invitation was addressed to a different account. '
          'Sign in with the invited email to accept it.',
        );
      case 409:
        throw const InviteAcceptException(
          'This invitation has already been accepted.',
        );
      case 410:
        throw const InviteAcceptException(
          'This invitation has expired or been revoked. Ask for a new one.',
        );
      default:
        throw InviteAcceptException(
          'Could not accept the invitation (error ${response.statusCode}). Please try again.',
        );
    }
  }
}

/// Carries a user-facing, actionable message for invite-acceptance failures.
class InviteAcceptException implements Exception {
  final String message;
  const InviteAcceptException(this.message);

  @override
  String toString() => message;
}
