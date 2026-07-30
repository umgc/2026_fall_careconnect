import 'dart:async';
import 'dart:convert';

import 'package:care_connect_app/config/env_constant.dart';
import 'package:care_connect_app/features/ai_hitl/models/hitl_models.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:http/http.dart' as http;

/// Clinician client for Tier-2 HITL queue / release / reject.
class HitlApiService {
  HitlApiService._();
  static final HitlApiService instance = HitlApiService._();

  static String get _base => '${getBackendBaseUrl()}/v1/api/ai/hitl';

  Future<List<HitlQueueItem>> fetchQueue({
    Duration timeout = const Duration(seconds: 20),
    http.Client? client,
  }) async {
    final http.Client httpClient = client ?? http.Client();
    final owned = client == null;
    try {
      final headers = await ApiService.getAuthHeaders();
      headers['Accept'] = 'application/json';
      final response = await httpClient
          .get(Uri.parse('$_base/queue'), headers: headers)
          .timeout(timeout);
      _throwIfFailed(response, 'queue');
      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        throw const FormatException('HITL queue response must be a list');
      }
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(HitlQueueItem.fromJson)
          .toList();
    } on HitlApiException {
      rethrow;
    } on FormatException {
      rethrow;
    } on TimeoutException {
      rethrow;
    } finally {
      if (owned) httpClient.close();
    }
  }

  Future<HitlDetail> fetchDetail(
    String heldItemId, {
    Duration timeout = const Duration(seconds: 20),
    http.Client? client,
  }) async {
    _requireUuid(heldItemId);
    final http.Client httpClient = client ?? http.Client();
    final owned = client == null;
    try {
      final headers = await ApiService.getAuthHeaders();
      headers['Accept'] = 'application/json';
      final response = await httpClient
          .get(Uri.parse('$_base/$heldItemId'), headers: headers)
          .timeout(timeout);
      _throwIfFailed(response, 'detail');
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('HITL detail response must be an object');
      }
      return HitlDetail.fromJson(decoded);
    } on HitlApiException {
      rethrow;
    } on FormatException {
      rethrow;
    } on TimeoutException {
      rethrow;
    } finally {
      if (owned) httpClient.close();
    }
  }

  Future<HitlDetail> release(
    String heldItemId, {
    String? editedAnswer,
    String? notes,
    Duration timeout = const Duration(seconds: 30),
    http.Client? client,
  }) async {
    _requireUuid(heldItemId);
    final http.Client httpClient = client ?? http.Client();
    final owned = client == null;
    try {
      final headers = await ApiService.getAuthHeaders();
      headers['Accept'] = 'application/json';
      headers['Content-Type'] = 'application/json';
      final body = <String, dynamic>{
        if (editedAnswer != null) 'editedAnswer': editedAnswer,
        if (notes != null) 'notes': notes,
      };
      final response = await httpClient
          .post(
            Uri.parse('$_base/$heldItemId/release'),
            headers: headers,
            body: jsonEncode(body),
          )
          .timeout(timeout);
      _throwIfFailed(response, 'release');
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('HITL release response must be an object');
      }
      return HitlDetail.fromJson(decoded);
    } on HitlApiException {
      rethrow;
    } on FormatException {
      rethrow;
    } on TimeoutException {
      rethrow;
    } finally {
      if (owned) httpClient.close();
    }
  }

  Future<HitlDetail> reject(
    String heldItemId, {
    String? reason,
    Duration timeout = const Duration(seconds: 30),
    http.Client? client,
  }) async {
    _requireUuid(heldItemId);
    final http.Client httpClient = client ?? http.Client();
    final owned = client == null;
    try {
      final headers = await ApiService.getAuthHeaders();
      headers['Accept'] = 'application/json';
      headers['Content-Type'] = 'application/json';
      final body = <String, dynamic>{
        if (reason != null) 'reason': reason,
      };
      final response = await httpClient
          .post(
            Uri.parse('$_base/$heldItemId/reject'),
            headers: headers,
            body: jsonEncode(body),
          )
          .timeout(timeout);
      _throwIfFailed(response, 'reject');
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('HITL reject response must be an object');
      }
      return HitlDetail.fromJson(decoded);
    } on HitlApiException {
      rethrow;
    } on FormatException {
      rethrow;
    } on TimeoutException {
      rethrow;
    } finally {
      if (owned) httpClient.close();
    }
  }

  static void _requireUuid(String heldItemId) {
    final ok = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(heldItemId);
    if (!ok) {
      throw const FormatException('HITL heldItemId must be a UUID');
    }
  }

  static void _throwIfFailed(http.Response response, String action) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }
    String message = 'HITL $action failed with HTTP ${response.statusCode}';
    String? errorCode;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final msg = decoded['message'];
        final err = decoded['error'];
        if (msg is String && msg.trim().isNotEmpty) {
          message = msg.trim();
        }
        if (err is String && err.trim().isNotEmpty) {
          errorCode = err.trim();
        }
      }
    } catch (_) {
      // keep default message
    }
    throw HitlApiException(response.statusCode, message, errorCode: errorCode);
  }
}
