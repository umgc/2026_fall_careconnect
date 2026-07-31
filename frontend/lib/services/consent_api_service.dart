import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/env_constant.dart';
import 'api_service.dart';

/// Client for the patient-facing AI-retrieval consent grant/revoke API
/// (`/api/v3/consent/ai-retrieval`). The authenticated patient is always the
/// grantor; callers must be logged in as the patient to grant or revoke.
class ConsentApiService {
  static String get _baseUrl =>
      '${getBackendBaseUrl()}/api/v3/consent/ai-retrieval';

  /// Grants AI-retrieval consent from the authenticated patient to
  /// [granteeUserId]. Returns the decoded grant response on success.
  static Future<Map<String, dynamic>> grantAiRetrieval({
    required int granteeUserId,
    String? granteeRole,
    String? expiresAt,
  }) async {
    final headers = await ApiService.getAuthHeaders();
    headers['Content-Type'] = 'application/json';
    headers['Accept'] = 'application/json';

    final response = await http.post(
      Uri.parse(_baseUrl),
      headers: headers,
      body: jsonEncode({
        'granteeUserId': granteeUserId,
        if (granteeRole != null && granteeRole.trim().isNotEmpty)
          'granteeRole': granteeRole,
        if (expiresAt != null && expiresAt.trim().isNotEmpty)
          'expiresAt': expiresAt,
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Failed to grant AI retrieval consent: HTTP ${response.statusCode}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const FormatException(
        'AI retrieval consent grant response is not an object',
      );
    }
    return Map<String, dynamic>.from(decoded);
  }

  /// Revokes AI-retrieval consent previously granted to [granteeUserId].
  /// Uses a JSON body (not a query param) so grantee ids are not captured in
  /// URLs / access logs.
  static Future<Map<String, dynamic>> revokeAiRetrieval({
    required int granteeUserId,
  }) async {
    final headers = await ApiService.getAuthHeaders();
    headers['Content-Type'] = 'application/json';
    headers['Accept'] = 'application/json';

    final response = await http.delete(
      Uri.parse(_baseUrl),
      headers: headers,
      body: jsonEncode({'granteeUserId': granteeUserId}),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Failed to revoke AI retrieval consent: HTTP ${response.statusCode}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const FormatException(
        'AI retrieval consent revoke response is not an object',
      );
    }
    return Map<String, dynamic>.from(decoded);
  }

  /// Returns whether Ask AI retrieval consent from [patientUserId] to
  /// [granteeUserId] is effectively granted (explicit grant or care-circle
  /// grandfather when no grant history exists). Prefer `effectiveConsent`,
  /// falling back to `granted` for older backends.
  static Future<bool> isAiRetrievalGranted({
    required int patientUserId,
    required int granteeUserId,
  }) async {
    final headers = await ApiService.getAuthHeaders();
    final uri = Uri.parse(_baseUrl).replace(
      queryParameters: {
        'patientUserId': patientUserId.toString(),
        'granteeUserId': granteeUserId.toString(),
      },
    );

    final response = await http.get(uri, headers: headers);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Failed to check AI retrieval consent: HTTP ${response.statusCode}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const FormatException(
        'AI retrieval consent check response is not an object',
      );
    }
    if (decoded.containsKey('effectiveConsent')) {
      return decoded['effectiveConsent'] == true;
    }
    return decoded['granted'] == true;
  }
}
