import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../config/env_constant.dart';
import '../models/public_passport.dart';

/// The outcome of opening a scanned emergency QR code.
sealed class ScanResult {
  const ScanResult();
}

/// 200: the code is active. Design screen 3.
class ScanShown extends ScanResult {
  final PublicPassport passport;
  const ScanShown(this.passport);
}

/// 404: unknown, revoked or wrong code. They look the same on purpose. Screen 4.
class ScanNotActive extends ScanResult {
  const ScanNotActive();
}

/// 429: more than 30 scans a minute from this phone.
class ScanRateLimited extends ScanResult {
  const ScanRateLimited();
}

/// No answer from the server (no signal, timeout) or an unexpected answer.
class ScanFailed extends ScanResult {
  const ScanFailed();
}

/// Calls the public scan endpoint. No sign-in, no auth header: whoever
/// scans the code at a scene has no account.
class PassportScanService {
  PassportScanService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  static const _timeout = Duration(seconds: 15);

  Future<ScanResult> scan(String token) async {
    final code = token.trim();
    if (code.isEmpty) return const ScanNotActive();

    final uri = Uri.parse(
        '${getBackendBaseUrl()}/v1/api/passport/scan/${Uri.encodeComponent(code)}');
    final http.Response resp;
    try {
      resp = await _client.get(uri,
          headers: const {'Accept': 'application/json'}).timeout(_timeout);
    } catch (_) {
      return const ScanFailed();
    }

    switch (resp.statusCode) {
      case 200:
        try {
          final body = jsonDecode(utf8.decode(resp.bodyBytes));
          if (body is! Map<String, dynamic>) return const ScanFailed();
          return ScanShown(PublicPassport.fromJson(body));
        } catch (_) {
          return const ScanFailed();
        }
      case 404:
        return const ScanNotActive();
      case 429:
        return const ScanRateLimited();
      default:
        return const ScanFailed();
    }
  }
}
