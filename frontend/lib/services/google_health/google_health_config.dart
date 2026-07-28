import 'package:flutter/foundation.dart';

/// Compile-time Google Health OAuth configuration.
///
/// Supply values via `--dart-define` (do not commit real secrets):
/// - `GOOGLE_HEALTH_CLIENT_ID`
/// - `GOOGLE_HEALTH_REDIRECT_URI`
/// - `GOOGLE_HEALTH_SCOPES` (space-separated; optional)
/// - `GOOGLE_HEALTH_CLIENT_SECRET` (optional; only if using a confidential
///   Web OAuth client — prefer a mobile/public client + PKCE)
class GoogleHealthConfig {
  GoogleHealthConfig({
    required this.clientId,
    required this.redirectUri,
    required this.scopes,
    this.clientSecret,
  });

  static const String authorizationEndpoint =
      'https://accounts.google.com/o/oauth2/v2/auth';
  static const String tokenEndpoint = 'https://oauth2.googleapis.com/token';
  static const String apiBaseUrl = 'https://health.googleapis.com/v4';

  /// Official Google Health readonly scopes for heart rate + sleep + activity.
  /// Override with `GOOGLE_HEALTH_SCOPES` when your Cloud project needs a
  /// different set.
  static const List<String> defaultScopes = [
    'https://www.googleapis.com/auth/googlehealth.activity_and_fitness.readonly',
    'https://www.googleapis.com/auth/googlehealth.health_metrics_and_measurements.readonly',
    'https://www.googleapis.com/auth/googlehealth.sleep.readonly',
  ];

  final String clientId;
  final String redirectUri;
  final List<String> scopes;
  final String? clientSecret;

  bool get isConfigured => clientId.isNotEmpty && redirectUri.isNotEmpty;

  /// Loads config from `--dart-define`. Throws a clear error when required
  /// values are missing so UI can prompt the developer/operator.
  factory GoogleHealthConfig.fromEnvironment() {
    const clientId = String.fromEnvironment('GOOGLE_HEALTH_CLIENT_ID');
    const redirectUri = String.fromEnvironment('GOOGLE_HEALTH_REDIRECT_URI');
    const clientSecret = String.fromEnvironment('GOOGLE_HEALTH_CLIENT_SECRET');
    const scopesRaw = String.fromEnvironment('GOOGLE_HEALTH_SCOPES');

    if (clientId.isEmpty || redirectUri.isEmpty) {
      throw StateError(
        'Google Health OAuth is not configured. Pass '
        '--dart-define=GOOGLE_HEALTH_CLIENT_ID=... and '
        '--dart-define=GOOGLE_HEALTH_REDIRECT_URI=... '
        '(and optionally GOOGLE_HEALTH_SCOPES / GOOGLE_HEALTH_CLIENT_SECRET).',
      );
    }

    final scopes = scopesRaw.trim().isEmpty
        ? defaultScopes
        : scopesRaw
            .split(RegExp(r'\s+'))
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList(growable: false);

    return GoogleHealthConfig(
      clientId: clientId,
      redirectUri: redirectUri,
      scopes: scopes,
      clientSecret: clientSecret.isEmpty ? null : clientSecret,
    );
  }

  /// Non-throwing check for UI gating.
  static bool get isEnvironmentConfigured {
    const clientId = String.fromEnvironment('GOOGLE_HEALTH_CLIENT_ID');
    const redirectUri = String.fromEnvironment('GOOGLE_HEALTH_REDIRECT_URI');
    return clientId.isNotEmpty && redirectUri.isNotEmpty;
  }

  static String missingConfigMessage() {
    if (kIsWeb) {
      return 'Google Health uses the backend OAuth flow on web. '
          'Ensure GOOGLE_CLIENT_ID is configured on the server.';
    }
    return 'Fitbit/Google Health is not configured for this build. '
        'Provide GOOGLE_HEALTH_CLIENT_ID and GOOGLE_HEALTH_REDIRECT_URI '
        'via --dart-define, then rebuild.';
  }
}
