import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_service.dart';
import '../config/env_constant.dart';

/// HTTP client for the Confirmation Service backend (WBS 3.15.1 / 3.15.2).
///
/// Calls `/v1/api/confirmations` endpoints. Follows the same static-method
/// pattern as [AIChatService].
class ConfirmationApiService {
  static String get _baseUrl =>
      '${getBackendBaseUrl()}/v1/api/confirmations';

  /// Fetch all PENDING items, optionally filtered by [sourceType].
  static Future<Map<String, dynamic>> fetchPendingItems({
    String? sourceType,
  }) async {
    try {
      final headers = await ApiService.getAuthHeaders();
      var uri = Uri.parse('$_baseUrl/pending');
      if (sourceType != null) {
        uri = uri.replace(queryParameters: {'sourceType': sourceType});
      }

      final response = await http.get(uri, headers: headers);

      if (response.statusCode == 200) {
        final items = jsonDecode(response.body) as List;
        return {'success': true, 'items': items};
      }
      return {
        'success': false,
        'error': 'HTTP ${response.statusCode}',
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Fetch a single confirmation item by [id].
  static Future<Map<String, dynamic>> fetchItem(int id) async {
    try {
      final headers = await ApiService.getAuthHeaders();
      final response = await http.get(
        Uri.parse('$_baseUrl/$id'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        return {
          'success': true,
          'item': jsonDecode(response.body),
        };
      }
      return {
        'success': false,
        'error': 'HTTP ${response.statusCode}',
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Confirm a PENDING item. Optional [note] for audit trail.
  static Future<Map<String, dynamic>> confirmItem(
    int id, {
    String? note,
  }) async {
    try {
      final headers = await ApiService.getAuthHeaders();
      headers['Content-Type'] = 'application/json';

      final response = await http.post(
        Uri.parse('$_baseUrl/$id/confirm'),
        headers: headers,
        body: jsonEncode({'note': note}),
      );

      if (response.statusCode == 200) {
        return {
          'success': true,
          'item': jsonDecode(response.body),
        };
      }
      return {
        'success': false,
        'error': 'HTTP ${response.statusCode}',
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Dismiss a PENDING item. Optional [note] for audit trail.
  static Future<Map<String, dynamic>> dismissItem(
    int id, {
    String? note,
  }) async {
    try {
      final headers = await ApiService.getAuthHeaders();
      headers['Content-Type'] = 'application/json';

      final response = await http.post(
        Uri.parse('$_baseUrl/$id/dismiss'),
        headers: headers,
        body: jsonEncode({'note': note}),
      );

      if (response.statusCode == 200) {
        return {
          'success': true,
          'item': jsonDecode(response.body),
        };
      }
      return {
        'success': false,
        'error': 'HTTP ${response.statusCode}',
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Fetch all confirmation items for a specific user.
  static Future<Map<String, dynamic>> fetchItemsByUser(int userId) async {
    try {
      final headers = await ApiService.getAuthHeaders();
      final response = await http.get(
        Uri.parse('$_baseUrl/user/$userId'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final items = jsonDecode(response.body) as List;
        return {'success': true, 'items': items};
      }
      return {
        'success': false,
        'error': 'HTTP ${response.statusCode}',
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }
}
