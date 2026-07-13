// lib/features/health/virtual_check_in/models/services/checkin_api.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

import 'package:care_connect_app/features/health/virtual_check_in/models/virtual_check_in_backend_question_model.dart';
import 'package:care_connect_app/features/health/virtual_check_in/models/virtual_check_in_backend_model.dart'
    show SubmitAnswersRequest;
import 'package:care_connect_app/services/auth_token_manager.dart';

class CheckInApi {
  final String _base;
  final http.Client _client;
  final Duration _timeout;
  final String? _jwt; // optional bearer token

  CheckInApi(
      String baseUrl, {
        http.Client? client,
        Duration timeout = const Duration(seconds: 15),
        String? jwt,
      })  : _base = _normalizeBase(baseUrl),
        _client = client ?? http.Client(),
        _timeout = timeout,
        _jwt = jwt;

  static String _normalizeBase(String v) {
    v = v.trim();
    if (v.endsWith('/')) v = v.substring(0, v.length - 1);
    return v;
  }

  Future<Map<String, String>> _headers() async {
    final h = <String, String>{'Content-Type': 'application/json'};
    final jwt = _jwt;
    final t = (jwt != null && jwt.isNotEmpty)
        ? jwt
        : await AuthTokenManager.getJwtToken();
    if (t != null && t.isNotEmpty) {
      h['Authorization'] = 'Bearer $t';
    }
    return h;
  }

  /// GET /api/checkins/{checkInId}/questions
  /// Return typed DTOs for mapping to UI.
  Future<List<BackendQuestionDto>> getQuestions(String checkInId) async {
    final uri = Uri.parse('$_base/api/checkins/$checkInId/questions');
    final headers = await _headers();
    headers['Accept'] = 'application/json';
    final res = await _client.get(uri, headers: headers).timeout(_timeout);

    if (res.statusCode != 200) {
      throw Exception('Failed to load questions: ${res.statusCode} ${res.body}');
    }
    final raw = jsonDecode(res.body) as List;
    return raw
        .map((e) => BackendQuestionDto.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// POST /api/checkins/{checkInId}/answers
  Future<void> submitAnswers(String checkInId, SubmitAnswersRequest req) async {
    final uri = Uri.parse('$_base/api/checkins/$checkInId/answers');
    final headers = await _headers();
    final res = await _client
        .post(uri, headers: headers, body: jsonEncode(req.toJson()))
        .timeout(_timeout);

    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception('Failed to submit answers: ${res.statusCode} ${res.body}');
    }
  }

  /// POST /api/questions - Create new question
  Future<BackendQuestionDto> createQuestion(BackendQuestionDto question) async {
    final uri = Uri.parse('$_base/api/questions');
    final headers = await _headers();
    final res = await _client
        .post(uri, headers: headers, body: jsonEncode(question.toJson()))
        .timeout(_timeout);

    if (res.statusCode != 200) {
      throw Exception('Failed to create question: ${res.statusCode} ${res.body}');
    }
    return BackendQuestionDto.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// PUT /api/questions/{id} - Update existing question
  Future<BackendQuestionDto> updateQuestion(int id, BackendQuestionDto question) async {
    final uri = Uri.parse('$_base/api/questions/$id');
    final headers = await _headers();
    final res = await _client
        .put(uri, headers: headers, body: jsonEncode(question.toJson()))
        .timeout(_timeout);

    if (res.statusCode != 200) {
      throw Exception('Failed to update question: ${res.statusCode} ${res.body}');
    }
    return BackendQuestionDto.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// PATCH /api/questions/{id}/active - Deactivate a question
  Future<void> deactivateQuestion(int id) async {
    final uri = Uri.parse('$_base/api/questions/$id/active?active=false');
    final headers = await _headers();
    final res = await _client.patch(uri, headers: headers).timeout(_timeout);

    if (res.statusCode != 200) {
      throw Exception('Failed to deactivate question: ${res.statusCode} ${res.body}');
    }
  }

  void close() => _client.close();
}
