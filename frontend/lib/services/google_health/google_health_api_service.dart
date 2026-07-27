import 'dart:convert';

import 'package:http/http.dart' as http;

import 'google_health_auth_service.dart';
import 'google_health_config.dart';

/// Thin authenticated client for `https://health.googleapis.com/v4/...`.
class GoogleHealthApiService {
  GoogleHealthApiService({
    required GoogleHealthAuthService authService,
    http.Client? httpClient,
  })  : _auth = authService,
        _http = httpClient ?? http.Client();

  final GoogleHealthAuthService _auth;
  final http.Client _http;

  /// `GET .../users/me/dataTypes/heart-rate/dataPoints`
  Future<Map<String, dynamic>> fetchHeartRate({
    int? pageSize,
    String? pageToken,
    String? filter,
  }) {
    return listDataPoints(
      dataType: 'heart-rate',
      pageSize: pageSize,
      pageToken: pageToken,
      filter: filter,
    );
  }

  /// `GET .../users/me/dataTypes/sleep/dataPoints`
  Future<Map<String, dynamic>> fetchSleep({
    int? pageSize,
    String? pageToken,
    String? filter,
  }) {
    return listDataPoints(
      dataType: 'sleep',
      pageSize: pageSize,
      pageToken: pageToken,
      filter: filter,
    );
  }

  /// `GET .../users/me/dataTypes/steps/dataPoints` (easy extension point).
  Future<Map<String, dynamic>> fetchSteps({
    int? pageSize,
    String? pageToken,
    String? filter,
  }) {
    return listDataPoints(
      dataType: 'steps',
      pageSize: pageSize,
      pageToken: pageToken,
      filter: filter,
    );
  }

  Future<Map<String, dynamic>> listDataPoints({
    required String dataType,
    int? pageSize,
    String? pageToken,
    String? filter,
  }) async {
    final uri = _buildDataPointsUri(
      dataType: dataType,
      pageSize: pageSize,
      pageToken: pageToken,
      filter: filter,
    );

    final first = await _authorizedGet(uri);
    if (first.statusCode != 401) {
      return _decodeOrThrow(first, dataType);
    }

    // One retry after refresh on 401.
    await _auth.refreshAccessToken();
    final retry = await _authorizedGet(uri);
    return _decodeOrThrow(retry, dataType);
  }

  Uri _buildDataPointsUri({
    required String dataType,
    int? pageSize,
    String? pageToken,
    String? filter,
  }) {
    final query = <String, String>{};
    if (pageSize != null && pageSize > 0) {
      query['pageSize'] = '$pageSize';
    }
    if (pageToken != null && pageToken.isNotEmpty) {
      query['pageToken'] = pageToken;
    }
    if (filter != null && filter.isNotEmpty) {
      query['filter'] = filter;
    }

    return Uri.parse(
      '${GoogleHealthConfig.apiBaseUrl}/users/me/dataTypes/$dataType/dataPoints',
    ).replace(queryParameters: query.isEmpty ? null : query);
  }

  Future<http.Response> _authorizedGet(Uri uri) async {
    final token = await _auth.requireAccessToken();
    try {
      return await _http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );
    } catch (e) {
      throw GoogleHealthApiException(
        'Network error talking to Google Health: $e',
      );
    }
  }

  Map<String, dynamic> _decodeOrThrow(http.Response response, String dataType) {
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const GoogleHealthApiException(
        'Google Health access was denied or revoked. Please reconnect Fitbit.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw GoogleHealthApiException(
        'Google Health $dataType request failed '
        '(${response.statusCode}): ${response.body}',
      );
    }
    if (response.body.isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
    throw GoogleHealthApiException(
      'Unexpected Google Health response for $dataType.',
    );
  }

  void close() => _http.close();
}

class GoogleHealthApiException implements Exception {
  const GoogleHealthApiException(this.message);
  final String message;

  @override
  String toString() => message;
}
