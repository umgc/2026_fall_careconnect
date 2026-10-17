import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../config/env_constant.dart';
import '../../../services/api_service.dart';
import '../../../services/auth_service.dart';
import '../models/passport_view.dart';

enum PassportError {
  /// No answer from the server (no signal, timeout).
  network,

  /// 401 even after refreshing the sign-in.
  signedOut,

  /// 403: signed in, but not as a patient.
  notPatient,

  /// Anything else, including 409 from a double tap.
  server,
}

class PassportException implements Exception {
  final PassportError error;
  const PassportException(this.error);
  @override
  String toString() => 'PassportException($error)';
}

/// The signed-in patient's own passport endpoints (CC-12 Increment 2).
class PassportService {
  PassportService({
    http.Client? client,
    Future<Map<String, String>> Function()? headers,
    Future<Object?> Function()? refresh,
  })  : _client = client ?? http.Client(),
        _headers = headers ?? ApiService.getAuthHeaders,
        _refresh = refresh ?? AuthService.forceRefreshToken;

  final http.Client _client;
  final Future<Map<String, String>> Function() _headers;
  final Future<Object?> Function() _refresh;

  static const _timeout = Duration(seconds: 20);
  static String get _base => '${getBackendBaseUrl()}/v1/api/passport';

  Future<PassportView> getPassport() async {
    final resp = await _send((h) => _client.get(Uri.parse(_base), headers: h));
    return PassportView.fromJson(_json(resp, 200));
  }

  /// Makes a new code and turns the old one off. The answer is the only time
  /// the code is given, so the caller must keep it.
  Future<NewQrCode> makeNewCode() async {
    final resp =
        await _send((h) => _client.post(Uri.parse('$_base/token'), headers: h));
    final code = NewQrCode.fromJson(_json(resp, 201));
    if (code.token.isEmpty || code.url.isEmpty) {
      throw const PassportException(PassportError.server);
    }
    return code;
  }

  /// Turns the patient's code off. Anyone who scans it then sees "This code
  /// isn't active". Turning off a code that is already off is fine (204).
  Future<void> turnOffCode() async {
    final resp = await _send(
        (h) => _client.delete(Uri.parse('$_base/token'), headers: h));
    switch (resp.statusCode) {
      case 204:
      case 200:
        return;
      case 401:
        throw const PassportException(PassportError.signedOut);
      case 403:
        throw const PassportException(PassportError.notPatient);
      default:
        throw const PassportException(PassportError.server);
    }
  }

  /// Sends a request; on 401 refreshes the sign-in once and retries.
  Future<http.Response> _send(
      Future<http.Response> Function(Map<String, String> headers) request) async {
    try {
      final first = await request(await _headers()).timeout(_timeout);
      if (first.statusCode != 401) return first;
      try {
        if (await _refresh() == null) return first;
      } catch (_) {
        return first;
      }
      return await request(await _headers()).timeout(_timeout);
    } on PassportException {
      rethrow;
    } catch (_) {
      throw const PassportException(PassportError.network);
    }
  }

  Map<String, dynamic> _json(http.Response resp, int ok) {
    switch (resp.statusCode) {
      case 401:
        throw const PassportException(PassportError.signedOut);
      case 403:
        throw const PassportException(PassportError.notPatient);
    }
    if (resp.statusCode != ok) {
      throw const PassportException(PassportError.server);
    }
    try {
      final body = jsonDecode(utf8.decode(resp.bodyBytes));
      if (body is Map<String, dynamic>) return body;
    } catch (_) {}
    throw const PassportException(PassportError.server);
  }
}
