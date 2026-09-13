import 'dart:developer' show log;
import 'package:flutter/foundation.dart';
// import 'package:flutter_dotenv/flutter_dotenv.dart'; // <-- REMOVED

// --- Raw values from --dart-define ---
// We define all the compile-time variables here

const String _agoraAppId = String.fromEnvironment('AGORA_APP_ID');
const String _agoraAppCertificate = String.fromEnvironment(
  'AGORA_APP_CERTIFICATE',
);

const String _backendBaseUrl = String.fromEnvironment(
  'BACKEND_URL',
  defaultValue: '',
);

const String _wsOverrideUrl = String.fromEnvironment('WEBSOCKET_SERVER_URL');
const String _backendToken = String.fromEnvironment('CC_BACKEND_TOKEN');
const String _jwtSecret = String.fromEnvironment('JWT_SECRET');
const String _deepSeekUri = String.fromEnvironment('DEEPSEEK_URI');
const String _openAIKey = String.fromEnvironment('OPENAI_API_KEY');
const String _deepSeekKey = String.fromEnvironment('DEEPSEEK_API_KEY');
const String _googleClientId = String.fromEnvironment('GOOGLE_CLIENT_ID');
const String _appDomain = String.fromEnvironment(
  'APP_DOMAIN',
  defaultValue: 'localhost',
);
const String _appPort = String.fromEnvironment(
  'APP_PORT',
  defaultValue: '50030',
);
const String _fitbitClientId = String.fromEnvironment('FITBIT_CLIENT_ID');
const String _fitbitClientSecret = String.fromEnvironment(
  'FITBIT_CLIENT_SECRET',
);

String getFitbitClientId() {
  final clientId = _fitbitClientId;
  if (clientId.isEmpty) {
    throw Exception('FITBIT_CLIENT_ID is not defined via --dart-define');
  }
  return clientId;
}

String getFitbitClientSecret() {
  final secret = _fitbitClientSecret;
  if (secret.isEmpty) {
    throw Exception('FITBIT_CLIENT_SECRET is not defined via --dart-define');
  }
  return secret;
}

/// Returns the unified WebSocket server base URL for both signaling and notifications
///
/// Set WEBSOCKET_SERVER_URL via --dart-define to override.
String _getUnifiedWebSocketBaseUrl() {
  // Prefer explicit environment variable
  if (_wsOverrideUrl.isNotEmpty) {
    if (!kDebugMode && !_wsOverrideUrl.startsWith('wss://')) {
      throw Exception(
        'WEBSOCKET_SERVER_URL must use wss:// in release builds.',
      );
    }
    return _wsOverrideUrl;
  }

  final base = getBackendBaseUrl();
  if (base.startsWith('https://')) {
    return base.replaceFirst('https://', 'wss://');
  } else if (base.startsWith('http://')) {
    if (!kDebugMode) {
      throw Exception(
        'In release builds, BACKEND_URL must use https:// and WebSocket must use wss://.',
      );
    }
    return base.replaceFirst('http://', 'ws://');
  }
  // Fallback
  if (!kDebugMode) {
    throw Exception('Unable to derive secure WebSocket URL for release build.');
  }
  return 'ws://localhost:8080';
}

/// Returns the WebRTC signaling server URL (points to /ws/notifications)
String getWebRTCSignalingServerUrl() {
  return '${_getUnifiedWebSocketBaseUrl()}/ws/notifications';
}

/// Returns the WebSocket notification URL (points to /ws/notifications)
String getWebSocketNotificationUrl() {
  return '${_getUnifiedWebSocketBaseUrl()}/ws/notifications';
}

/// Returns the WebSocket URL for call invitation/accept/decline events
String getCallNotificationWebSocketUrl() {
  return '${_getUnifiedWebSocketBaseUrl()}/ws/calls-ws';
}

/// Returns the WebSocket URL for the real-time P2P chat service
String getChatWebSocketUrl() {
  return '${_getUnifiedWebSocketBaseUrl()}/ws/chat';
}

/// Returns the Backend Base URL
///
/// This is now controlled by a single --dart-define=BACKEND_URL variable.
String getBackendBaseUrl() {
  final configured = _backendBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
  String resolved = configured;

  if (resolved.isEmpty) {
    if (kIsWeb) {
      resolved = 'http://localhost:8080';
    } else {
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          resolved = 'http://10.0.2.2:8080';
          break;
        default:
          resolved = 'http://localhost:8080';
      }
    }
  }

  // https enforcement disabled for local testing
  // TODO: re-enable before production release
  //if (!kDebugMode && !resolved.startsWith('https://')) {
    //throw Exception('BACKEND_URL must use https:// in release builds.');
  //}

  return resolved;
}

String getBackendToken() {
  // Replaced dotenv.env and Platform.environment
  final token = _backendToken;

  if (token.isEmpty || token == 'your_backend_token_here') {
    if (kDebugMode) {
      print('⚠️ Backend token not configured. Some API calls may fail.');
      return '';
    }
    throw Exception(
      'CC_BACKEND_TOKEN is not configured. Please set it via --dart-define.',
    );
  }

  if (kDebugMode) {
    print('✅ Backend token loaded successfully');
  }
  return token;
}

String getJWTSecret() {
  final secret = _jwtSecret;

  if (secret.isEmpty || secret == 'your_jwt_secret_key_here') {
    if (kDebugMode) {
      print('⚠️ JWT secret not configured. Token validation may fail.');
      return '';
    }
    throw Exception(
      'JWT_SECRET is not configured. Please set it via --dart-define.',
    );
  }

  // Validate JWT secret length
  if (secret.length < 32) {
    throw Exception(
      'JWT_SECRET must be at least 32 characters long for security.',
    );
  }

  if (kDebugMode) {
    print('✅ JWT secret loaded successfully');
  }
  return secret;
}

String getDeepSeekUri() {
  final uri = _deepSeekUri;
  if (uri.isEmpty) {
    throw Exception('DEEPSEEK_URI is not defined via --dart-define');
  }
  return uri;
}

String getOpenAIKey() {
  final key = _openAIKey;

  if (key.isEmpty || key == 'your_openai_api_key_here') {
    if (kDebugMode) {
      print('⚠️ OpenAI API key not configured. AI features will be disabled.');
      return '';
    }
    throw Exception(
      'OPENAI_API_KEY is not configured. Please set it via --dart-define.',
    );
  }

  if (!key.startsWith('sk-')) {
    throw Exception(
      'Invalid OpenAI API key format. Key should start with "sk-".',
    );
  }

  if (kDebugMode) {
    print('✅ OpenAI API key loaded successfully');
  }
  return key;
}

String getDeepSeekKey() {
  final key = _deepSeekKey;

  if (key.isEmpty || key == 'your_deepseek_api_key_here') {
    if (kDebugMode) {
      log(
        '⚠️ DeepSeek API key not configured. DeepSeek AI features will be disabled.',
      );
      return '';
    }
    throw Exception(
      'DEEPSEEK_API_KEY is not configured. Please set it via --dart-define.',
    );
  }

  if (!key.startsWith('sk-')) {
    throw Exception(
      'Invalid DeepSeek API key format. Key should start with "sk-".',
    );
  }

  if (kDebugMode) {
    log('✅ DeepSeek API key loaded successfully');
  }
  return key;
}

String getGoogleClientId() {
  final clientId = _googleClientId;
  if (clientId.isEmpty) {
    throw Exception('GOOGLE_CLIENT_ID is not defined via --dart-define');
  }
  return clientId;
}

String getAppDomain() {
  // Now uses the const _appDomain (which has its own defaultValue)
  return _appDomain;
}

String getEnableUSPSDigest() {
  return String.fromEnvironment('ENABLE_USPS_DIGEST', defaultValue: 'false');
}

String getEnableMockUSPSDigest() {
  return String.fromEnvironment(
    'ENABLE_MOCK_USPS_DIGEST',
    defaultValue: 'false',
  );
}

String getAppPort() {
  // Now uses the const _appPort (which has its own defaultValue)
  return _appPort;
}

String getOAuthRedirectUri() {
  final domain = getAppDomain();
  final port = getAppPort();

  if (domain == 'localhost' || domain.startsWith('127.0.0.1')) {
    return 'http://$domain:$port/oauth2/callback/google';
  } else {
    return 'https://$domain/oauth2/callback/google';
  }
}

String getWebBaseUrl() {
  final domain = getAppDomain();
  final port = getAppPort();

  if (domain == 'localhost' || domain.startsWith('127.0.0.1')) {
    return 'http://$domain:$port';
  }

  return 'https://$domain';
}
