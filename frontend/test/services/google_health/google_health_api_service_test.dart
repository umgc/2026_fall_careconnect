import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:care_connect_app/services/google_health/google_health_api_service.dart';
import 'package:care_connect_app/services/google_health/google_health_auth_service.dart';
import 'package:care_connect_app/services/google_health/google_health_config.dart';
import 'package:care_connect_app/services/google_health/google_health_token_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class _MemorySecureStorage extends FlutterSecureStorage {
  _MemorySecureStorage() : super();

  final Map<String, String> _data = {};

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      _data.remove(key);
    } else {
      _data[key] = value;
    }
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      _data[key];

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _data.remove(key);
  }
}

class _FakeAuth extends GoogleHealthAuthService {
  _FakeAuth(GoogleHealthTokenStore store)
      : super(
          config: GoogleHealthConfig(
            clientId: 'test-client',
            redirectUri: 'edu.umgc.careconnect:/oauth2redirect',
            scopes: GoogleHealthConfig.defaultScopes,
          ),
          tokenStore: store,
        );

  int refreshCalls = 0;

  @override
  Future<String> requireAccessToken() async {
    final token = await tokenStore.readAccessToken();
    if (token == null || token.isEmpty) {
      throw const GoogleHealthAuthException('missing');
    }
    return token;
  }

  @override
  Future<String?> refreshAccessToken() async {
    refreshCalls++;
    await tokenStore.saveTokens(
      accessToken: 'refreshed-token',
      refreshToken: 'refresh',
      accessTokenExpiry: DateTime.now().toUtc().add(const Duration(hours: 1)),
    );
    return 'refreshed-token';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GoogleHealthTokenStore', () {
    test('saves, reads, and clears tokens', () async {
      final store = GoogleHealthTokenStore(storage: _MemorySecureStorage());
      await store.saveTokens(
        accessToken: 'access',
        refreshToken: 'refresh',
        accessTokenExpiry: DateTime.utc(2030, 1, 1),
        scopes: const ['scope.a'],
      );

      expect(await store.hasSession(), isTrue);
      expect(await store.readAccessToken(), 'access');
      expect(await store.readRefreshToken(), 'refresh');
      expect(await store.readScopes(), ['scope.a']);
      expect(await store.isAccessTokenExpired(), isFalse);

      await store.clear();
      expect(await store.hasSession(), isFalse);
    });
  });

  group('GoogleHealthApiService', () {
    test('retries once after 401 by refreshing token', () async {
      final store = GoogleHealthTokenStore(storage: _MemorySecureStorage());
      await store.saveTokens(accessToken: 'stale-token', refreshToken: 'refresh');
      final auth = _FakeAuth(store);

      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        expect(request.url.path, contains('/dataTypes/heart-rate/dataPoints'));
        if (calls == 1) {
          expect(request.headers['Authorization'], 'Bearer stale-token');
          return http.Response('unauthorized', 401);
        }
        expect(request.headers['Authorization'], 'Bearer refreshed-token');
        return http.Response(
          '{"dataPoints":[{"heartRate":{"bpm":72}}]}',
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final api = GoogleHealthApiService(authService: auth, httpClient: client);
      final payload = await api.fetchHeartRate();
      expect(calls, 2);
      expect(auth.refreshCalls, 1);
      expect(payload['dataPoints'], isA<List>());
    });

    test('surfaces clear error on revoked access', () async {
      final store = GoogleHealthTokenStore(storage: _MemorySecureStorage());
      await store.saveTokens(accessToken: 'token', refreshToken: 'refresh');
      final auth = _FakeAuth(store);
      final client = MockClient((request) async => http.Response('denied', 403));
      final api = GoogleHealthApiService(authService: auth, httpClient: client);

      expect(
        () => api.fetchSleep(),
        throwsA(isA<GoogleHealthApiException>()),
      );
    });
  });

  group('GoogleHealthConfig', () {
    test('default scopes include heart-rate and sleep categories', () {
      expect(
        GoogleHealthConfig.defaultScopes,
        contains(
          'https://www.googleapis.com/auth/googlehealth.health_metrics_and_measurements.readonly',
        ),
      );
      expect(
        GoogleHealthConfig.defaultScopes,
        contains('https://www.googleapis.com/auth/googlehealth.sleep.readonly'),
      );
    });
  });
}
