import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists Google Health OAuth tokens in platform secure storage.
class GoogleHealthTokenStore {
  GoogleHealthTokenStore({
    FlutterSecureStorage storage = const FlutterSecureStorage(
      webOptions: WebOptions.defaultOptions,
    ),
  }) : _storage = storage;

  static const String accessTokenKey = 'google_health_access_token';
  static const String refreshTokenKey = 'google_health_refresh_token';
  static const String expiryKey = 'google_health_access_token_expiry';
  static const String scopesKey = 'google_health_scopes';

  final FlutterSecureStorage _storage;

  Future<void> saveTokens({
    required String accessToken,
    String? refreshToken,
    DateTime? accessTokenExpiry,
    List<String>? scopes,
  }) async {
    await _storage.write(key: accessTokenKey, value: accessToken);
    if (refreshToken != null && refreshToken.isNotEmpty) {
      await _storage.write(key: refreshTokenKey, value: refreshToken);
    }
    if (accessTokenExpiry != null) {
      await _storage.write(
        key: expiryKey,
        value: accessTokenExpiry.toUtc().toIso8601String(),
      );
    }
    if (scopes != null && scopes.isNotEmpty) {
      await _storage.write(key: scopesKey, value: scopes.join(' '));
    }
  }

  Future<String?> readAccessToken() => _storage.read(key: accessTokenKey);

  Future<String?> readRefreshToken() => _storage.read(key: refreshTokenKey);

  Future<DateTime?> readAccessTokenExpiry() async {
    final raw = await _storage.read(key: expiryKey);
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toUtc();
  }

  Future<List<String>> readScopes() async {
    final raw = await _storage.read(key: scopesKey);
    if (raw == null || raw.trim().isEmpty) return const [];
    return raw
        .split(RegExp(r'\s+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
  }

  Future<bool> hasSession() async {
    final access = await readAccessToken();
    return access != null && access.isNotEmpty;
  }

  /// True when expiry is unknown or within [skew] of now.
  Future<bool> isAccessTokenExpired({
    Duration skew = const Duration(minutes: 2),
  }) async {
    final expiry = await readAccessTokenExpiry();
    if (expiry == null) return false;
    return DateTime.now().toUtc().isAfter(expiry.subtract(skew));
  }

  Future<void> clear() async {
    await Future.wait([
      _storage.delete(key: accessTokenKey),
      _storage.delete(key: refreshTokenKey),
      _storage.delete(key: expiryKey),
      _storage.delete(key: scopesKey),
    ]);
  }
}
