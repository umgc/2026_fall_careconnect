import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../services/api_service.dart';
import '../models/admin_analytics_summary_model.dart';
import '../models/feature_trend_model.dart';

class AdminAnalyticsApiException implements Exception {
  AdminAnalyticsApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class AdminAnalyticsApi {
  const AdminAnalyticsApi();

  /// Loads analytics for an explicit [from, to) window (both required together).
  Future<AdminAnalyticsSummary> fetchSummary({
    required DateTime from,
    required DateTime to,
  }) async {
    final uri = Uri.parse('${ApiConstants.adminAnalytics}/summary').replace(
      queryParameters: {
        'from': _formatQueryDateTime(from),
        'to': _formatQueryDateTime(to),
      },
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

  /// Loads daily feature_use counts for one feature over [from, to).
  Future<FeatureTrend> fetchFeatureTrends({
    required DateTime from,
    required DateTime to,
    required String feature,
  }) async {
    final uri =
        Uri.parse('${ApiConstants.adminAnalytics}/feature-trends').replace(
      queryParameters: {
        'from': _formatQueryDateTime(from),
        'to': _formatQueryDateTime(to),
        'feature': feature,
      },
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
        throw AdminAnalyticsApiException('Invalid feature trend response format');
      }
      return FeatureTrend.fromJson(decoded);
    }

    String message = 'Failed to load feature trend';
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

  /// Formats a local calendar date/time as UTC ISO-8601 for the backend.
  String _formatQueryDateTime(DateTime value) {
    final utc = DateTime.utc(
      value.year,
      value.month,
      value.day,
      value.hour,
      value.minute,
      value.second,
      value.millisecond,
      value.microsecond,
    );
    return utc.toIso8601String();
  }
}
