// Tests for env_constant.dart configuration helpers
// (lib/config/env_constant.dart).
//
// These are pure functions that read from --dart-define constants.
// In the test environment no --dart-define values are set, so the functions
// either return their hard-coded defaults or throw expected exceptions.
// All tests run without any platform channels or network I/O.

import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/config/env_constant.dart';

void main() {
  // ---------------------------------------------------------------
  // getBackendBaseUrl
  // ---------------------------------------------------------------
  group('getBackendBaseUrl', () {
    test('returns a non-empty string', () {
      expect(getBackendBaseUrl(), isNotEmpty);
    });

    test('returns a string starting with http', () {
      expect(getBackendBaseUrl(), startsWith('http'));
    });

    test('does not throw', () {
      expect(() => getBackendBaseUrl(), returnsNormally);
    });

    test('returns URL containing localhost or 10.0.2.2', () {
      final url = getBackendBaseUrl();
      expect(url, anyOf(contains('localhost'), contains('10.0.2.2')));
    });

    test('returns URL with port 8080', () {
      final url = getBackendBaseUrl();
      expect(url, contains('8080'));
    });

    test('result is consistent across multiple calls', () {
      expect(getBackendBaseUrl(), equals(getBackendBaseUrl()));
    });

    test('result does not end with a trailing slash', () {
      final url = getBackendBaseUrl();
      expect(url.endsWith('/'), isFalse);
    });

    test('returns a valid URI', () {
      final url = getBackendBaseUrl();
      final uri = Uri.tryParse(url);
      expect(uri, isNotNull);
      expect(uri!.hasScheme, isTrue);
    });
  });

  // ---------------------------------------------------------------
  // getAppDomain
  // ---------------------------------------------------------------
  group('getAppDomain', () {
    test('returns "localhost" when APP_DOMAIN is not set', () {
      expect(getAppDomain(), 'localhost');
    });

    test('returns a non-empty string', () {
      expect(getAppDomain(), isNotEmpty);
    });
  });

  // ---------------------------------------------------------------
  // getAppPort
  // ---------------------------------------------------------------
  group('getAppPort', () {
    test('returns "50030" when APP_PORT is not set', () {
      expect(getAppPort(), '50030');
    });

    test('returns a numeric string', () {
      expect(int.tryParse(getAppPort()), isNotNull);
    });
  });

  // ---------------------------------------------------------------
  // getOAuthRedirectUri
  // ---------------------------------------------------------------
  group('getOAuthRedirectUri', () {
    test('returns a non-empty string', () {
      expect(getOAuthRedirectUri(), isNotEmpty);
    });

    test('contains "/oauth2/callback/google"', () {
      expect(getOAuthRedirectUri(), contains('/oauth2/callback/google'));
    });

    test('uses http for localhost domain', () {
      expect(getOAuthRedirectUri(), startsWith('http://localhost'));
    });

    test('contains port for localhost', () {
      expect(getOAuthRedirectUri(), contains(':50030'));
    });

    test('full format is http://localhost:50030/oauth2/callback/google', () {
      expect(
        getOAuthRedirectUri(),
        'http://localhost:50030/oauth2/callback/google',
      );
    });

    test('is a valid URI', () {
      final uri = Uri.tryParse(getOAuthRedirectUri());
      expect(uri, isNotNull);
      expect(uri!.scheme, 'http');
      expect(uri.host, 'localhost');
      expect(uri.port, 50030);
      expect(uri.path, '/oauth2/callback/google');
    });
  });

  // ---------------------------------------------------------------
  // getWebBaseUrl
  // ---------------------------------------------------------------
  group('getWebBaseUrl', () {
    test('returns a non-empty string', () {
      expect(getWebBaseUrl(), isNotEmpty);
    });

    test('uses http for localhost domain', () {
      expect(getWebBaseUrl(), startsWith('http://localhost'));
    });

    test('contains the app port', () {
      expect(getWebBaseUrl(), contains(getAppPort()));
    });

    test('contains port for localhost', () {
      expect(getWebBaseUrl(), contains(':50030'));
    });

    test('equals http://localhost:50030', () {
      expect(getWebBaseUrl(), 'http://localhost:50030');
    });

    test('is a valid URI', () {
      final uri = Uri.tryParse(getWebBaseUrl());
      expect(uri, isNotNull);
      expect(uri!.scheme, 'http');
      expect(uri.host, 'localhost');
      expect(uri.port, 50030);
    });
  });

  // ---------------------------------------------------------------
  // getWebSocketNotificationUrl
  // ---------------------------------------------------------------
  group('getWebSocketNotificationUrl', () {
    test('returns a non-empty string', () {
      expect(getWebSocketNotificationUrl(), isNotEmpty);
    });

    test('ends with /ws/notifications', () {
      expect(getWebSocketNotificationUrl(), endsWith('/ws/notifications'));
    });

    test('starts with ws:// or wss://', () {
      final url = getWebSocketNotificationUrl();
      expect(url, anyOf(startsWith('ws://'), startsWith('wss://')));
    });

    test('uses ws:// scheme for http backend', () {
      // Default backend is http, so WebSocket should use ws://
      final url = getWebSocketNotificationUrl();
      expect(url, startsWith('ws://'));
    });

    test('is a valid URI', () {
      final uri = Uri.tryParse(getWebSocketNotificationUrl());
      expect(uri, isNotNull);
      expect(uri!.path, '/ws/notifications');
    });
  });

  // ---------------------------------------------------------------
  // getWebRTCSignalingServerUrl
  // ---------------------------------------------------------------
  group('getWebRTCSignalingServerUrl', () {
    test('returns a non-empty string', () {
      expect(getWebRTCSignalingServerUrl(), isNotEmpty);
    });

    test('ends with /ws/notifications', () {
      expect(getWebRTCSignalingServerUrl(), endsWith('/ws/notifications'));
    });

    test('starts with ws:// or wss://', () {
      final url = getWebRTCSignalingServerUrl();
      expect(url, anyOf(startsWith('ws://'), startsWith('wss://')));
    });

    test('uses ws:// scheme for http backend', () {
      final url = getWebRTCSignalingServerUrl();
      expect(url, startsWith('ws://'));
    });
  });

  // ---------------------------------------------------------------
  // WebSocket URL consistency
  // ---------------------------------------------------------------
  group('WebSocket URLs consistency', () {
    test('notification and signaling URLs are equal', () {
      expect(getWebSocketNotificationUrl(), getWebRTCSignalingServerUrl());
    });

    test('both WebSocket URLs derive from backend base URL', () {
      final backendUrl = getBackendBaseUrl();
      final wsUrl = getWebSocketNotificationUrl();
      // Both should reference the same host
      final backendUri = Uri.parse(backendUrl);
      final wsUri = Uri.parse(wsUrl);
      expect(wsUri.host, backendUri.host);
      expect(wsUri.port, backendUri.port);
    });
  });

  // getAgoraAppCertificate — removed from API (no public getter exists).

  // ---------------------------------------------------------------
  // getEnableUSPSDigest
  // ---------------------------------------------------------------
  group('getEnableUSPSDigest', () {
    test('returns "false" by default', () {
      expect(getEnableUSPSDigest(), 'false');
    });

    test('returns a String type', () {
      expect(getEnableUSPSDigest(), isA<String>());
    });

    test('returns either "true" or "false"', () {
      expect(getEnableUSPSDigest(), anyOf('true', 'false'));
    });
  });

  // ---------------------------------------------------------------
  // getEnableMockUSPSDigest
  // ---------------------------------------------------------------
  group('getEnableMockUSPSDigest', () {
    test('returns "false" by default', () {
      expect(getEnableMockUSPSDigest(), 'false');
    });

    test('returns a String type', () {
      expect(getEnableMockUSPSDigest(), isA<String>());
    });

    test('returns either "true" or "false"', () {
      expect(getEnableMockUSPSDigest(), anyOf('true', 'false'));
    });
  });

  // getAgoraAppId — removed from API (no public getter exists).

  // ---------------------------------------------------------------
  // getFitbitClientId – throws when not set
  // ---------------------------------------------------------------
  group('getFitbitClientId', () {
    test('throws Exception when FITBIT_CLIENT_ID is not defined', () {
      expect(() => getFitbitClientId(), throwsException);
    });

    test('throws with descriptive message about FITBIT_CLIENT_ID', () {
      expect(
        () => getFitbitClientId(),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('FITBIT_CLIENT_ID'),
          ),
        ),
      );
    });

    test('throws with message mentioning --dart-define', () {
      expect(
        () => getFitbitClientId(),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('--dart-define'),
          ),
        ),
      );
    });
  });

  // ---------------------------------------------------------------
  // getFitbitClientSecret – throws when not set
  // ---------------------------------------------------------------
  group('getFitbitClientSecret', () {
    test('throws Exception when FITBIT_CLIENT_SECRET is not defined', () {
      expect(() => getFitbitClientSecret(), throwsException);
    });

    test('throws with descriptive message about FITBIT_CLIENT_SECRET', () {
      expect(
        () => getFitbitClientSecret(),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('FITBIT_CLIENT_SECRET'),
          ),
        ),
      );
    });

    test('throws with message mentioning --dart-define', () {
      expect(
        () => getFitbitClientSecret(),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('--dart-define'),
          ),
        ),
      );
    });
  });

  // ---------------------------------------------------------------
  // getDeepSeekUri – throws when not set
  // ---------------------------------------------------------------
  group('getDeepSeekUri', () {
    test('throws Exception when DEEPSEEK_URI is not defined', () {
      expect(() => getDeepSeekUri(), throwsException);
    });

    test('throws with descriptive message about DEEPSEEK_URI', () {
      expect(
        () => getDeepSeekUri(),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('DEEPSEEK_URI'),
          ),
        ),
      );
    });

    test('throws with message mentioning --dart-define', () {
      expect(
        () => getDeepSeekUri(),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('--dart-define'),
          ),
        ),
      );
    });
  });

  // ---------------------------------------------------------------
  // getGoogleClientId – throws when not set
  // ---------------------------------------------------------------
  group('getGoogleClientId', () {
    test('throws Exception when GOOGLE_CLIENT_ID is not defined', () {
      expect(() => getGoogleClientId(), throwsException);
    });

    test('throws with descriptive message about GOOGLE_CLIENT_ID', () {
      expect(
        () => getGoogleClientId(),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('GOOGLE_CLIENT_ID'),
          ),
        ),
      );
    });

    test('throws with message mentioning --dart-define', () {
      expect(
        () => getGoogleClientId(),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('--dart-define'),
          ),
        ),
      );
    });
  });

  // ---------------------------------------------------------------
  // getBackendToken – debug mode
  // ---------------------------------------------------------------
  group('getBackendToken', () {
    test('returns empty string in debug mode when not configured', () {
      // In debug mode (kDebugMode == true in tests), returns '' instead of throwing.
      final token = getBackendToken();
      expect(token, isEmpty);
    });

    test('does not throw in debug mode', () {
      expect(() => getBackendToken(), returnsNormally);
    });

    test('returns a String type', () {
      expect(getBackendToken(), isA<String>());
    });

    test('returns empty string (not null) when unconfigured', () {
      expect(getBackendToken(), equals(''));
    });
  });

  // ---------------------------------------------------------------
  // getJWTSecret – debug mode
  // ---------------------------------------------------------------
  group('getJWTSecret', () {
    test('returns empty string in debug mode when not configured', () {
      final secret = getJWTSecret();
      expect(secret, isEmpty);
    });

    test('does not throw in debug mode', () {
      expect(() => getJWTSecret(), returnsNormally);
    });

    test('returns a String type', () {
      expect(getJWTSecret(), isA<String>());
    });

    test('returns empty string (not null) when unconfigured', () {
      expect(getJWTSecret(), equals(''));
    });
  });

  // ---------------------------------------------------------------
  // getOpenAIKey – debug mode
  // ---------------------------------------------------------------
  group('getOpenAIKey', () {
    test('returns empty string in debug mode when not configured', () {
      final key = getOpenAIKey();
      expect(key, isEmpty);
    });

    test('does not throw in debug mode', () {
      expect(() => getOpenAIKey(), returnsNormally);
    });

    test('returns a String type', () {
      expect(getOpenAIKey(), isA<String>());
    });

    test('returns empty string (not null) when unconfigured', () {
      expect(getOpenAIKey(), equals(''));
    });
  });

  // ---------------------------------------------------------------
  // getDeepSeekKey – debug mode
  // ---------------------------------------------------------------
  group('getDeepSeekKey', () {
    test('returns empty string in debug mode when not configured', () {
      final key = getDeepSeekKey();
      expect(key, isEmpty);
    });

    test('does not throw in debug mode', () {
      expect(() => getDeepSeekKey(), returnsNormally);
    });

    test('returns a String type', () {
      expect(getDeepSeekKey(), isA<String>());
    });

    test('returns empty string (not null) when unconfigured', () {
      expect(getDeepSeekKey(), equals(''));
    });
  });

  // ---------------------------------------------------------------
  // Cross-function consistency checks
  // ---------------------------------------------------------------
  group('Cross-function consistency', () {
    test('getWebBaseUrl uses getAppDomain and getAppPort', () {
      final domain = getAppDomain();
      final port = getAppPort();
      final webUrl = getWebBaseUrl();
      expect(webUrl, contains(domain));
      expect(webUrl, contains(port));
    });

    test('getOAuthRedirectUri uses getAppDomain and getAppPort', () {
      final domain = getAppDomain();
      final port = getAppPort();
      final oauthUri = getOAuthRedirectUri();
      expect(oauthUri, contains(domain));
      expect(oauthUri, contains(port));
    });

    test('WebSocket URLs derive from getBackendBaseUrl host and port', () {
      final backendUrl = getBackendBaseUrl();
      final notificationUrl = getWebSocketNotificationUrl();
      final signalingUrl = getWebRTCSignalingServerUrl();

      // Parse to compare host/port
      final backendUri = Uri.parse(backendUrl);
      final notifUri = Uri.parse(notificationUrl);
      final signalUri = Uri.parse(signalingUrl);

      expect(notifUri.host, backendUri.host);
      expect(notifUri.port, backendUri.port);
      expect(signalUri.host, backendUri.host);
      expect(signalUri.port, backendUri.port);
    });

    test('all getter functions return consistently on repeated calls', () {
      // Verify idempotency of all non-throwing functions
      expect(getBackendBaseUrl(), getBackendBaseUrl());
      expect(getAppDomain(), getAppDomain());
      expect(getAppPort(), getAppPort());
      expect(getWebBaseUrl(), getWebBaseUrl());
      expect(getOAuthRedirectUri(), getOAuthRedirectUri());
      expect(getWebSocketNotificationUrl(), getWebSocketNotificationUrl());
      expect(getWebRTCSignalingServerUrl(), getWebRTCSignalingServerUrl());
      expect(getEnableUSPSDigest(), getEnableUSPSDigest());
      expect(getEnableMockUSPSDigest(), getEnableMockUSPSDigest());
      expect(getBackendToken(), getBackendToken());
      expect(getJWTSecret(), getJWTSecret());
      expect(getOpenAIKey(), getOpenAIKey());
      expect(getDeepSeekKey(), getDeepSeekKey());
    });
  });

  // ---------------------------------------------------------------
  // URL format validation
  // ---------------------------------------------------------------
  group('URL format validation', () {
    test('getBackendBaseUrl returns parseable URL', () {
      final uri = Uri.parse(getBackendBaseUrl());
      expect(uri.scheme, anyOf('http', 'https'));
      expect(uri.host, isNotEmpty);
    });

    test('getWebBaseUrl returns parseable URL', () {
      final uri = Uri.parse(getWebBaseUrl());
      expect(uri.scheme, anyOf('http', 'https'));
      expect(uri.host, isNotEmpty);
    });

    test('getOAuthRedirectUri returns parseable URL', () {
      final uri = Uri.parse(getOAuthRedirectUri());
      expect(uri.scheme, anyOf('http', 'https'));
      expect(uri.host, isNotEmpty);
      expect(uri.path, isNotEmpty);
    });

    test('getWebSocketNotificationUrl returns parseable URL', () {
      final uri = Uri.parse(getWebSocketNotificationUrl());
      expect(uri.scheme, anyOf('ws', 'wss'));
      expect(uri.host, isNotEmpty);
      expect(uri.path, isNotEmpty);
    });

    test('getWebRTCSignalingServerUrl returns parseable URL', () {
      final uri = Uri.parse(getWebRTCSignalingServerUrl());
      expect(uri.scheme, anyOf('ws', 'wss'));
      expect(uri.host, isNotEmpty);
      expect(uri.path, isNotEmpty);
    });
  });
}
