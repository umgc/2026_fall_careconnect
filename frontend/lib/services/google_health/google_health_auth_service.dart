import 'package:flutter/services.dart';
import 'package:flutter_appauth/flutter_appauth.dart';

import 'google_health_config.dart';
import 'google_health_token_store.dart';

/// Google OAuth 2.0 Authorization Code + PKCE for the Google Health API.
class GoogleHealthAuthService {
  GoogleHealthAuthService({
    GoogleHealthConfig? config,
    GoogleHealthTokenStore? tokenStore,
    FlutterAppAuth? appAuth,
  })  : _config = config ?? GoogleHealthConfig.fromEnvironment(),
        _tokenStore = tokenStore ?? GoogleHealthTokenStore(),
        _appAuth = appAuth ?? const FlutterAppAuth();

  final GoogleHealthConfig _config;
  final GoogleHealthTokenStore _tokenStore;
  final FlutterAppAuth _appAuth;

  GoogleHealthTokenStore get tokenStore => _tokenStore;

  Future<bool> isConnected() => _tokenStore.hasSession();

  /// Launches the system browser / ASWebAuthenticationSession and exchanges
  /// the auth code for tokens (PKCE handled by flutter_appauth).
  Future<GoogleHealthAuthResult> connect() async {
    try {
      final request = AuthorizationTokenRequest(
        _config.clientId,
        _config.redirectUri,
        clientSecret: _config.clientSecret,
        scopes: _config.scopes,
        serviceConfiguration: const AuthorizationServiceConfiguration(
          authorizationEndpoint: GoogleHealthConfig.authorizationEndpoint,
          tokenEndpoint: GoogleHealthConfig.tokenEndpoint,
        ),
        promptValues: const ['consent'],
        additionalParameters: const {
          'access_type': 'offline',
        },
      );

      final result = await _appAuth.authorizeAndExchangeCode(request);
      if (result == null ||
          result.accessToken == null ||
          result.accessToken!.isEmpty) {
        return const GoogleHealthAuthResult.failure(
          'Authorization was cancelled or did not return an access token.',
        );
      }

      await _tokenStore.saveTokens(
        accessToken: result.accessToken!,
        refreshToken: result.refreshToken,
        accessTokenExpiry: result.accessTokenExpirationDateTime?.toUtc(),
        scopes: result.scopes ?? _config.scopes,
      );

      return GoogleHealthAuthResult.success(
        accessToken: result.accessToken!,
        refreshToken: result.refreshToken,
      );
    } on PlatformException catch (e) {
      final details = '${e.code} ${e.message ?? ''} ${e.details ?? ''}'.toLowerCase();
      if (details.contains('cancel') || details.contains('user_canceled')) {
        return const GoogleHealthAuthResult.failure(
          'Google Health sign-in was cancelled.',
        );
      }
      return GoogleHealthAuthResult.failure(
        _friendlyAuthError(e.message ?? e.toString()),
      );
    } catch (e) {
      return GoogleHealthAuthResult.failure(_friendlyAuthError(e.toString()));
    }
  }

  /// Refreshes the access token using the stored refresh token.
  Future<String?> refreshAccessToken() async {
    final refreshToken = await _tokenStore.readRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      return null;
    }

    final result = await _appAuth.token(
      TokenRequest(
        _config.clientId,
        _config.redirectUri,
        clientSecret: _config.clientSecret,
        refreshToken: refreshToken,
        scopes: _config.scopes,
        serviceConfiguration: const AuthorizationServiceConfiguration(
          authorizationEndpoint: GoogleHealthConfig.authorizationEndpoint,
          tokenEndpoint: GoogleHealthConfig.tokenEndpoint,
        ),
      ),
    );

    if (result == null ||
        result.accessToken == null ||
        result.accessToken!.isEmpty) {
      return null;
    }

    await _tokenStore.saveTokens(
      accessToken: result.accessToken!,
      refreshToken: result.refreshToken ?? refreshToken,
      accessTokenExpiry: result.accessTokenExpirationDateTime?.toUtc(),
      scopes: result.scopes ?? _config.scopes,
    );
    return result.accessToken;
  }

  /// Returns a valid access token, refreshing when expired.
  Future<String> requireAccessToken() async {
    final existing = await _tokenStore.readAccessToken();
    if (existing == null || existing.isEmpty) {
      throw const GoogleHealthAuthException(
        'Google Health is not connected. Please connect Fitbit again.',
      );
    }

    final expired = await _tokenStore.isAccessTokenExpired();
    if (!expired) return existing;

    try {
      final refreshed = await refreshAccessToken();
      if (refreshed != null && refreshed.isNotEmpty) return refreshed;
    } catch (_) {
      // Fall through to revoke-style message.
    }

    await disconnect();
    throw const GoogleHealthAuthException(
      'Your Google Health session expired. Please reconnect Fitbit.',
    );
  }

  Future<void> disconnect() => _tokenStore.clear();

  String _friendlyAuthError(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('network') || lower.contains('socket')) {
      return 'Network error while connecting to Google. Check your connection and try again.';
    }
    if (lower.contains('invalid_grant') || lower.contains('revoked')) {
      return 'Google Health access was revoked. Please reconnect Fitbit.';
    }
    if (lower.contains('access_denied')) {
      return 'Google Health permission was denied. Grant access to continue.';
    }
    return 'Failed to connect to Google Health: $raw';
  }
}

class GoogleHealthAuthResult {
  const GoogleHealthAuthResult._({
    required this.ok,
    this.accessToken,
    this.refreshToken,
    this.errorMessage,
  });

  const GoogleHealthAuthResult.success({
    required String accessToken,
    String? refreshToken,
  }) : this._(ok: true, accessToken: accessToken, refreshToken: refreshToken);

  const GoogleHealthAuthResult.failure(String message)
      : this._(ok: false, errorMessage: message);

  final bool ok;
  final String? accessToken;
  final String? refreshToken;
  final String? errorMessage;
}

class GoogleHealthAuthException implements Exception {
  const GoogleHealthAuthException(this.message);
  final String message;

  @override
  String toString() => message;
}
