import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../services/api_service.dart';
import '../models/admin_user_model.dart';

class AdminUsersApiException implements Exception {
  AdminUsersApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class AdminUsersApi {
  const AdminUsersApi();

  Future<List<AdminUser>> fetchUsers() async {
    final uri = Uri.parse(ApiConstants.adminUsers);
    final headers = await ApiService.getAuthHeaders();

    final response = await http
        .get(uri, headers: headers)
        .timeout(
          const Duration(seconds: 60),
          onTimeout: () =>
              http.Response('{"error": "Request timeout"}', 408),
        );

    if (response.statusCode == 200) {
      final decoded = json.decode(response.body);
      if (decoded is! List) {
        throw AdminUsersApiException('Invalid users response format');
      }
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(AdminUser.fromJson)
          .toList();
    }

    throw AdminUsersApiException(
      _parseErrorMessage(response, 'Failed to load users'),
      statusCode: response.statusCode,
    );
  }

  Future<AdminUser> promoteToAdmin(int userId) async {
    final uri = Uri.parse('${ApiConstants.adminUsers}/$userId/role');
    final headers = await ApiService.getAuthHeaders();
    headers['Content-Type'] = 'application/json';

    final response = await http
        .post(
          uri,
          headers: headers,
          body: json.encode({'role': 'ADMIN'}),
        )
        .timeout(
          const Duration(seconds: 60),
          onTimeout: () =>
              http.Response('{"error": "Request timeout"}', 408),
        );

    if (response.statusCode == 200) {
      final decoded = json.decode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw AdminUsersApiException('Invalid role update response format');
      }
      return AdminUser.fromJson(decoded);
    }

    throw AdminUsersApiException(
      _parseErrorMessage(response, 'Failed to update user role'),
      statusCode: response.statusCode,
    );
  }

  String _parseErrorMessage(http.Response response, String fallback) {
    if (response.statusCode == 403) {
      return 'Admin access required';
    }
    if (response.body.isEmpty) {
      return fallback;
    }
    try {
      final body = json.decode(response.body);
      if (body is Map<String, dynamic>) {
        return body['message'] as String? ??
            body['error'] as String? ??
            fallback;
      }
    } catch (_) {
      // Keep fallback when body is not JSON.
    }
    return fallback;
  }
}
