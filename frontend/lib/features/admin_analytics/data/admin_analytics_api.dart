import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../services/api_service.dart';
import '../models/admin_analytics_summary_model.dart';

class AdminAnalyticsApiException implements Exception {
  AdminAnalyticsApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class AdminAnalyticsApi {
  const AdminAnalyticsApi();

  Future<AdminAnalyticsSummary> fetchSummary({required int days}) async {
    final uri = Uri.parse(
      '${ApiConstants.adminAnalytics}/summary?days=$days',
    );
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
      if (decoded is! Map<String, dynamic>) {
        throw AdminAnalyticsApiException('Invalid analytics response format');
      }
      return AdminAnalyticsSummary.fromJson(decoded);
    }

    String message = 'Failed to load analytics summary';
    if (response.statusCode == 403) {
      message = 'Admin access required';
    } else if (response.body.isNotEmpty) {
      try {
        final body = json.decode(response.body);
        if (body is Map<String, dynamic>) {
          message = body['message'] as String? ??
              body['error'] as String? ??
              message;
        }
      } catch (_) {
        // Keep default message when body is not JSON.
      }
    }

    throw AdminAnalyticsApiException(
      message,
      statusCode: response.statusCode,
    );
  }
}
