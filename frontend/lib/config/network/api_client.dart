import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../env_constant.dart';

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;
  ApiClient._internal();

  String get _baseUrl => getBackendBaseUrl();

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  Future<Map<String, dynamic>> get(String path) async {
    try {
      final url = Uri.parse('$_baseUrl$path');
      final response = await http.get(url, headers: _headers);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw ApiException(
          'GET request failed: ${response.statusCode}',
          response.statusCode,
        );
      }
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Network error: $e', 0);
    }
  }

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body,
  ) async {
    try {
      final url = Uri.parse('$_baseUrl$path');
      final response = await http.post(
        url,
        headers: _headers,
        body: json.encode(body),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return json.decode(response.body);
      } else {
        throw ApiException(
          'POST request failed: ${response.statusCode}',
          response.statusCode,
        );
      }
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Network error: $e', 0);
    }
  }

  Future<Map<String, dynamic>> put(
    String path,
    Map<String, dynamic> body,
  ) async {
    try {
      final url = Uri.parse('$_baseUrl$path');
      final response = await http.put(
        url,
        headers: _headers,
        body: json.encode(body),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw ApiException(
          'PUT request failed: ${response.statusCode}',
          response.statusCode,
        );
      }
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Network error: $e', 0);
    }
  }

  Future<Map<String, dynamic>> delete(String path) async {
    try {
      final url = Uri.parse('$_baseUrl$path');
      final response = await http.delete(url, headers: _headers);

      if (response.statusCode == 200 || response.statusCode == 204) {
        if (response.body.isEmpty) {
          return {'success': true};
        }
        return json.decode(response.body);
      } else {
        throw ApiException(
          'DELETE request failed: ${response.statusCode}',
          response.statusCode,
        );
      }
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Network error: $e', 0);
    }
  }
}

class ApiException implements Exception {
  final String message;
  final int statusCode;

  ApiException(this.message, this.statusCode);

  @override
  String toString() => 'ApiException: $message (Status: $statusCode)';
}
