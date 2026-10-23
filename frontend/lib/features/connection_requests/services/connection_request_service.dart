import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../services/api_service.dart';
import '../../../services/auth_token_manager.dart';
import '../models/connection_request_summary.dart';

/// Thrown when a connection request call fails; [message] is safe to show.
class ConnectionRequestException implements Exception {
  final String message;
  const ConnectionRequestException(this.message);

  @override
  String toString() => message;
}

/// The patient's side of caregiver connection requests: a caregiver asks, and
/// nothing is shared until the patient accepts here.
class ConnectionRequestService {
  /// Pending requests addressed to the signed-in patient.
  static Future<List<ConnectionRequestSummary>> incoming() async {
    final headers = await AuthTokenManager.getAuthHeaders();
    final http.Response response;
    try {
      response = await http.get(
        Uri.parse('${ApiConstants.connectionRequests}/incoming'),
        headers: headers,
      );
    } catch (_) {
      throw const ConnectionRequestException(
          'Could not reach the server. Check your connection and try again.');
    }
    if (response.statusCode != 200) {
      throw ConnectionRequestException(
          'Could not load connection requests (error ${response.statusCode}).');
    }
    final decoded = json.decode(response.body) as List<dynamic>;
    return decoded
        .map((e) => ConnectionRequestSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<void> accept(int requestId) => _respond(requestId, 'accept');

  static Future<void> decline(int requestId) => _respond(requestId, 'reject');

  static Future<void> _respond(int requestId, String action) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    final http.Response response;
    try {
      response = await http.post(
        Uri.parse('${ApiConstants.connectionRequests}/$requestId/$action'),
        headers: headers,
      );
    } catch (_) {
      throw const ConnectionRequestException(
          'Could not reach the server. Check your connection and try again.');
    }
    switch (response.statusCode) {
      case 200:
        return;
      case 404:
        throw const ConnectionRequestException(
            'This request no longer exists.');
      case 409:
        throw const ConnectionRequestException(
            'This request has already been answered.');
      default:
        throw ConnectionRequestException(
            'Could not update the request (error ${response.statusCode}).');
    }
  }
}
