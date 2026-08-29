import 'package:url_launcher/url_launcher.dart';
import '../config/env_constant.dart';

class OAuthService {
  // OAuth2 configuration - Use backend endpoints for OAuth flow
  // Frontend only needs to redirect to backend, which handles Google OAuth

  // Validate that backend is configured
  static bool get isConfigured {
    try {
      final backendUrl = getBackendBaseUrl();
      return backendUrl.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  // Build the backend OAuth initiation URL
  static String buildAuthorizationUrl() {
    final backendUrl = getBackendBaseUrl();
    // Use the backend endpoint: /v1/api/auth/sso/google
    return '$backendUrl/v1/api/auth/sso/google';
  }

  // Launch the OAuth2 flow via backend
  static Future<void> launchGoogleOAuth() async {
    if (!isConfigured) {
      throw Exception('Backend URL not configured. Check the BACKEND_URL --dart-define.');
    }

    final authUrl = buildAuthorizationUrl();
    print('🔗 Launching OAuth2 flow: $authUrl');

    if (await canLaunchUrl(Uri.parse(authUrl))) {
      await launchUrl(
        Uri.parse(authUrl),
        mode: LaunchMode.externalApplication, // Open in browser
      );
    } else {
      throw Exception('Could not launch OAuth URL: $authUrl');
    }
  }

  // Handle the OAuth callback - simplified since backend handles most logic
  static Future<String?> handleCallback(Uri callbackUri) async {
    final token = callbackUri.queryParameters['token'];
    final error = callbackUri.queryParameters['error'];

    if (error != null) {
      throw Exception('OAuth error: $error');
    }

    if (token == null) {
      throw Exception('No JWT token received from backend');
    }

    return token;
  }

  // Clear OAuth session data
  static void clearSession() {
    // No session data to clear since backend handles everything
    print('OAuth session cleared');
  }
}
