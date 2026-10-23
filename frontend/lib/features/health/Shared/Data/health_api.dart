import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:care_connect_app/config/environment_config.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;
  ApiException(this.statusCode, this.message);
  @override
  String toString() => 'ApiException($statusCode): $message';
}

class HealthApi {
  HealthApi(this.jwt);
  final String jwt;

  // ---------- Base + headers ----------
  String get _base => EnvironmentConfig.baseUrl;

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $jwt',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  Duration get _timeout => const Duration(seconds: 20);

  Uri _uri(String path, {Map<String, String>? query}) {
    final normalizedBase =
        _base.endsWith('/') ? _base.substring(0, _base.length - 1) : _base;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$normalizedBase$normalizedPath')
        .replace(queryParameters: query);
  }

  // ---------- Low-level HTTP helpers (consistent timeouts) ----------
  Future<http.Response> _get(String path, {Map<String, String>? query}) =>
      http.get(_uri(path, query: query), headers: _headers).timeout(_timeout);

  Future<http.Response> _post(String path,
          {Object? body, Map<String, String>? query}) =>
      http
          .post(_uri(path, query: query),
              headers: _headers, body: _encodeBody(body))
          .timeout(_timeout);

  Future<http.Response> _put(String path,
          {Object? body, Map<String, String>? query}) =>
      http
          .put(_uri(path, query: query),
              headers: _headers, body: _encodeBody(body))
          .timeout(_timeout);

  Future<http.Response> _patch(String path,
          {Object? body, Map<String, String>? query}) =>
      http
          .patch(_uri(path, query: query),
              headers: _headers, body: _encodeBody(body))
          .timeout(_timeout);

  Future<http.Response> _delete(String path,
          {Object? body, Map<String, String>? query}) =>
      http
          .delete(_uri(path, query: query),
              headers: _headers, body: _encodeBody(body))
          .timeout(_timeout);

  String? _encodeBody(Object? body) {
    if (body == null) return null;
    if (body is String) return body; // already JSON
    return jsonEncode(body);
  }

  // =========================================================
  // Patients
  // =========================================================

  // GET /v1/api/patients/me → returns the Patient entity for the current user.
  // We extract the `id` from either { id: ... } or { data: { id: ... } }.
  Future<int> getMyPatientId() async {
    final res = await _get('/v1/api/patients/me');
    if (res.statusCode != 200) {
      throw ApiException(res.statusCode, 'getMyPatientId failed: ${res.body}');
    }
    final body = json.decode(res.body);
    final Map<String, dynamic> m =
        (body is Map<String, dynamic>) ? body : <String, dynamic>{};
    final id = m['id'] ?? (m['data'] is Map ? m['data']['id'] : null);
    if (id == null) {
      throw ApiException(500, 'patient id not found in response');
    }
    return (id as num).toInt();
  }

  // =========================================================
  // Allergies
  //
  // From your AllergyController:
  // POST    /v1/api/allergies
  // PUT     /v1/api/allergies/{id}
  // GET     /v1/api/allergies/patient/{patientId}
  // GET     /v1/api/allergies/patient/{patientId}/active
  // PATCH   /v1/api/allergies/{id}/deactivate
  // DELETE  /v1/api/allergies/{id}
  // =========================================================

  // GET all allergies for a patient (returns `data: [AllergyDTO,...]`).
  Future<List<Map<String, dynamic>>> getAllergiesForPatient(
      int patientId) async {
    final res = await _get('/v1/api/allergies/patient/$patientId');
    if (res.statusCode != 200) {
      throw ApiException(
          res.statusCode, 'getAllergiesForPatient failed: ${res.body}');
    }
    final body = json.decode(res.body);
    final list = (body is Map && body['data'] is List)
        ? (body['data'] as List)
        : const [];
    return list.whereType<Map<String, dynamic>>().toList();
  }

  // GET active allergies only.
  Future<List<Map<String, dynamic>>> getActiveAllergiesForPatient(
      int patientId) async {
    final res = await _get('/v1/api/allergies/patient/$patientId/active');
    if (res.statusCode != 200) {
      throw ApiException(
          res.statusCode, 'getActiveAllergiesForPatient failed: ${res.body}');
    }
    final body = json.decode(res.body);
    final list = (body is Map && body['data'] is List)
        ? (body['data'] as List)
        : const [];
    return list.whereType<Map<String, dynamic>>().toList();
  }

  Future<Map<String, dynamic>> createAllergy({
    required int patientId,
    required String allergen,
    required String allergyType, // "DRUG"
    required String severity, // "MILD" | "MODERATE" | "SEVERE"
    required String reaction,
    String? notes,
    String? diagnosedDate, // optional: "YYYY-MM-DD"
    bool isActive = true,
  }) async {
    final payload = {
      'patientId': patientId,
      'allergen': allergen,
      'allergyType': allergyType,
      'severity': severity,
      'reaction': reaction,
      if (notes != null) 'notes': notes,
      if (diagnosedDate != null) 'diagnosedDate': diagnosedDate,
      'isActive': isActive,
    };

    final res = await _post('/v1/api/allergies', body: payload);
    if (res.statusCode != 201 && res.statusCode != 200) {
      throw ApiException(res.statusCode, 'createAllergy failed: ${res.body}');
    }
    final body = json.decode(res.body);
    return (body is Map && body['data'] is Map)
        ? body['data'] as Map<String, dynamic>
        : <String, dynamic>{};
  }

  // PUT update an existing allergy by id.
  Future<Map<String, dynamic>> updateAllergy({
    required int id,
    String? allergen,
    String? allergyType, // "DRUG" | "FOOD" | "ENVIRONMENTAL" | ...
    String? severity, // "MILD" | "MODERATE" | "SEVERE"
    String? reaction,
    String? notes,
    String? diagnosedDate, // "YYYY-MM-DD"
    bool? isActive,
  }) async {
    final payload = <String, dynamic>{};
    if (allergen != null) payload['allergen'] = allergen;
    if (allergyType != null) payload['allergyType'] = allergyType;
    if (severity != null) payload['severity'] = severity;
    if (reaction != null) payload['reaction'] = reaction;
    if (notes != null) payload['notes'] = notes;
    if (diagnosedDate != null) payload['diagnosedDate'] = diagnosedDate;
    if (isActive != null) payload['isActive'] = isActive;

    final res = await _put('/v1/api/allergies/$id', body: payload);
    if (res.statusCode != 200) {
      throw ApiException(res.statusCode, 'updateAllergy failed: ${res.body}');
    }
    final body = json.decode(res.body);
    return (body is Map && body['data'] is Map)
        ? body['data'] as Map<String, dynamic>
        : <String, dynamic>{};
  }

  // PATCH soft-deactivate an allergy.
  Future<void> deactivateAllergy(int id) async {
    final res = await _patch('/v1/api/allergies/$id/deactivate');
    if (res.statusCode != 200) {
      throw ApiException(
          res.statusCode, 'deactivateAllergy failed: ${res.body}');
    }
  }

  // DELETE permanently remove an allergy.
  Future<void> deleteAllergy(int id) async {
    final res = await _delete('/v1/api/allergies/$id');
    if (res.statusCode != 200 && res.statusCode != 204) {
      throw ApiException(res.statusCode, 'deleteAllergy failed: ${res.body}');
    }
  }
}
