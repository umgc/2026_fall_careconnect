import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../config/env_constant.dart';
import '../../../services/api_service.dart';
import '../models/medical_passport.dart';

/// Thrown for any non-2xx answer. [message] is the backend's `error` text when
/// it sent one, which is safe to show to the patient.
class MedicalPassportException implements Exception {
  const MedicalPassportException(this.statusCode, [this.message]);

  final int statusCode;
  final String? message;

  /// Signed in, but not as a patient: only patients have a passport.
  bool get notAPatient => statusCode == 403;
  bool get signedOut => statusCode == 401;

  @override
  String toString() => 'MedicalPassportException($statusCode, $message)';
}

/// Client for the patient's own passport (`/v1/api/passport`, CC-12). Every
/// call is made as the signed-in patient; nobody manages a passport for them.
class MedicalPassportService {
  static String get _baseUrl => '${getBackendBaseUrl()}/v1/api/passport';

  /// DEF-EMG-16: without a limit, a server that never answers leaves the page
  /// on its spinner. 20 s, as the QR screen's PassportService.
  static const _timeout = Duration(seconds: 20);

  static Future<MedicalPassport> fetch() async {
    final response =
        await http.get(Uri.parse(_baseUrl), headers: await _headers()).timeout(_timeout);
    return MedicalPassport.fromJson(_decode(response));
  }

  /// Replaces blood type, conditions and the emergency contact. Returns the
  /// passport as saved.
  static Future<MedicalPassport> updateProfile(
      PassportProfileUpdate update) async {
    final response = await http.put(
      Uri.parse('$_baseUrl/profile'),
      headers: await _headers(json: true),
      body: jsonEncode(update.toJson()),
    ).timeout(_timeout);
    return MedicalPassport.fromJson(_decode(response));
  }

  /// Shows or hides one section on a scan. Returns the passport as saved.
  static Future<MedicalPassport> setShared(
      PassportField field, bool shared) async {
    final response = await http.put(
      Uri.parse('$_baseUrl/visibility/${field.apiName}'),
      headers: await _headers(json: true),
      body: jsonEncode({'isPublic': shared}),
    ).timeout(_timeout);
    return MedicalPassport.fromJson(_decode(response));
  }

  /// Makes a new QR code and revokes any current one at once. The result is
  /// the only time the code's link is available.
  static Future<NewPassportCode> createCode() async {
    final response = await http
        .post(Uri.parse('$_baseUrl/token'), headers: await _headers())
        .timeout(_timeout);
    return NewPassportCode.fromJson(_decode(response));
  }

  /// Stops the current QR code working, without making a new one.
  static Future<void> revokeCode() async {
    final response = await http
        .delete(Uri.parse('$_baseUrl/token'), headers: await _headers())
        .timeout(_timeout);
    _check(response);
  }

  static Future<Map<String, String>> _headers({bool json = false}) async {
    final headers = await ApiService.getAuthHeaders();
    headers['Accept'] = 'application/json';
    if (json) headers['Content-Type'] = 'application/json';
    return headers;
  }

  static Map<String, dynamic> _decode(http.Response response) {
    _check(response);
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Passport response is not an object');
    }
    return decoded;
  }

  static void _check(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    throw MedicalPassportException(response.statusCode, _errorText(response));
  }

  static String? _errorText(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      return decoded is Map && decoded['error'] is String
          ? decoded['error'] as String
          : null;
    } on FormatException {
      return null;
    }
  }
}
