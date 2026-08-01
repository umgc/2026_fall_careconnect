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
  /// Resolve the current patient's default care-circle link ID so callers can
  /// start the invite flow without manual URL construction.
  ///
  /// GET /v1/api/patients/family-members
  /// (Returns active family-member links for the authenticated patient.)
  static Future<int> resolveDefaultLinkIdForCurrentPatient() async {
    final baseUrl = getBackendBaseUrl();
    final url = Uri.parse('$baseUrl/v1/api/patients/family-members');
    final headers = await AuthTokenManager.getAuthHeaders();

    http.Response response;
    try {
      response = await http.get(url, headers: headers);
    } catch (_) {
      throw const InviteException(
        'Could not load your care-circle link. Check your connection and try again.',
      );
    }

    if (response.statusCode == 401) {
      throw const InviteException(
          'Your session has expired. Please sign in again.');
    }
    if (response.statusCode == 403) {
      throw const InviteException(
        'This flow is available for patient accounts. Sign in as a patient to continue.',
      );
    }
    if (response.statusCode != 200) {
      throw InviteException(
        'Could not load your care-circle link (error ${response.statusCode}). Please try again.',
      );
    }

    final decoded = json.decode(response.body);
    if (decoded is! List) {
      throw const InviteException(
          'Care-circle links could not be read from the server.');
    }

    final links = decoded.whereType<Map<String, dynamic>>().toList();
    if (links.isEmpty) {
      throw const InviteException(
        'No family-member link is available yet for this patient account.',
      );
    }

    final activeLinks = links.where((link) {
      final status = (link['status'] ?? 'ACTIVE').toString().toUpperCase();
      return status == 'ACTIVE';
    }).toList();

    final candidates = activeLinks.isNotEmpty ? activeLinks : links;
    final ids = candidates
        .map((link) => _parseInt(link['id']))
        .whereType<int>()
        .toList();

    if (ids.isEmpty) {
      throw const InviteException('No usable care-circle link ID was found.');
    }

    return ids.first;
  }

  static int? _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return int.tryParse('$value');
  }

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
      if (invitedEmail != null && invitedEmail.isNotEmpty)
        'invitedEmail': invitedEmail,
      if (inviteReason != null && inviteReason.isNotEmpty)
        'inviteReason': inviteReason,
      if (ttlHours != null) 'ttlHours': ttlHours,
    };

    http.Response response;
    try {
      response =
          await http.post(url, headers: headers, body: json.encode(body));
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
        throw const InviteException(
            'Your session has expired. Please sign in again.');
      case 403:
        throw const InviteException(
          'You do not have permission to create an invite for this care circle.',
        );
      case 404:
        throw const InviteException(
            'That care-circle link could not be found.');
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
