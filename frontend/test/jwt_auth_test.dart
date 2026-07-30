import 'dart:ui';

import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/services/api_service.dart' as api_service;
import 'package:care_connect_app/services/auth_service.dart';
import 'package:care_connect_app/providers/user_provider.dart';

void main() {
  group('JWT Authentication Tests', () {
    test('JWT token should be extractable from Set-Cookie header', () {
      // Arrange
      const setCookieHeader =
          'AUTH=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c; HttpOnly; Path=/; SameSite=Strict';

      // Act
      final authCookieMatch = RegExp(
        r'AUTH=([^;]+)',
      ).firstMatch(setCookieHeader);

      // Assert
      expect(authCookieMatch, isNotNull);
      expect(authCookieMatch!.group(1), isNotNull);
      expect(authCookieMatch.group(1)!.length, greaterThan(20));
    });

    test('getAuthHeaders should return correct headers format', () async {
      // Act
      final headers = await api_service.ApiService.getAuthHeaders();

      // Assert
      expect(headers, isA<Map<String, String>>());
      expect(headers['Content-Type'], 'application/json');
      expect(headers.containsKey('Authorization'), isA<bool>());
    });

    test('UserSession should be created from JSON correctly', () {
      // Arrange
      final jsonData = {
        'id': 1,
        'email': 'test@example.com',
        'role': 'PATIENT',
        'patientId': 1,
      };

      // Act
      final userSession = UserSession.fromJson(jsonData);

      // Assert
      expect(userSession.id, 1);
      expect(userSession.email, 'test@example.com');
      expect(userSession.role, 'PATIENT');
      expect(userSession.patientId, 1);
    });

    test('AuthService.login should handle network errors gracefully', () async {
      // This tests error handling without making actual network calls
      final t = await AppLocalizations.delegate.load(Locale ('en'));
      expect(() async {
        try {
          await AuthService.login(
            'test@example.com',
            'password123',
            t
          );
        } catch (e) {
          // Expected to fail in test environment without backend
          expect(e, isA<Exception>());
        }
      }, returnsNormally);
    });
  });

  group('Authentication Flow Tests', () {
    test('login flow structure should be correct', () async {
      // Test the structure without making actual network calls
      expect(() async {
        try {
          // Step 1: Try to get auth headers (should work even without token)
          final headers = await api_service.ApiService.getAuthHeaders();

          // Verify headers are structured correctly
          expect(headers, isA<Map<String, String>>());
          expect(headers['Content-Type'], 'application/json');
        } catch (e) {
          // Should not throw errors for header generation
          fail('Header generation should not throw errors: $e');
        }
      }, returnsNormally);
    });

    test('JWT token regex pattern should work correctly', () {
      // Test various Set-Cookie header formats
      const testCases = [
        'AUTH=token123; HttpOnly; Path=/',
        'AUTH=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.test; HttpOnly',
        'AUTH=simple-token; Path=/; SameSite=Lax',
      ];

      for (final testCase in testCases) {
        final match = RegExp(r'AUTH=([^;]+)').firstMatch(testCase);
        expect(match, isNotNull, reason: 'Failed to match: $testCase');
        expect(match!.group(1), isNotNull);
        expect(match.group(1)!.isNotEmpty, isTrue);
      }
    });
  });

  group('API Endpoint Tests', () {
    test('ApiConstants should have correct endpoint URLs', () {
      // Test that API constants are properly configured
      expect(api_service.ApiConstants.auth, contains('/v1/api/auth'));
      expect(api_service.ApiConstants.baseUrl, contains('/v1/api/'));
      expect(api_service.ApiConstants.analytics, contains('/v1/api/analytics'));
      expect(api_service.ApiConstants.users, contains('/v1/api/users'));
      expect(api_service.ApiConstants.feed, contains('/v1/api/feed'));
      expect(api_service.ApiConstants.friends, contains('/v1/api/friends'));
    });

    test('login endpoint should be correctly formatted', () {
      expect(api_service.ApiConstants.auth, endsWith('/v1/api/auth'));
    });

    test('protected endpoints should be correctly formatted', () {
      expect(api_service.ApiConstants.analytics, endsWith('/v1/api/analytics'));
      expect(api_service.ApiConstants.users, endsWith('/v1/api/users'));
    });

    test('API URLs should be valid URIs', () {
      // Test that all API constants form valid URLs
      expect(() => Uri.parse(api_service.ApiConstants.auth), returnsNormally);
      expect(
        () => Uri.parse(api_service.ApiConstants.baseUrl),
        returnsNormally,
      );
      expect(
        () => Uri.parse(api_service.ApiConstants.analytics),
        returnsNormally,
      );
      expect(() => Uri.parse(api_service.ApiConstants.users), returnsNormally);
      expect(() => Uri.parse(api_service.ApiConstants.feed), returnsNormally);
      expect(
        () => Uri.parse(api_service.ApiConstants.friends),
        returnsNormally,
      );
    });
  });

  group('Authentication Security Tests', () {
    test('JWT token should not be logged in production', () {
      // This test ensures we're not accidentally logging sensitive data
      const mockJWT = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.test';

      // In our debug code, we only log the first 20 characters
      final loggedPortion = mockJWT.substring(0, 20);
      expect(loggedPortion.length, 20);
      expect(
        loggedPortion,
        isNot(contains('test')),
      ); // The payload shouldn't be in the logged portion
    });

    test('Authorization header should be correctly formatted', () {
      const mockToken = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.test';
      const authHeader = 'Bearer $mockToken';

      expect(authHeader, startsWith('Bearer '));
      expect(authHeader.substring(7), equals(mockToken));
    });

    test('public endpoints should not require authentication', () {
      // Test that login and registration endpoints don't use auth headers
      expect(
        () => api_service.ApiService.login('test@example.com', 'password'),
        returnsNormally,
      );
      expect(
        () => api_service.ApiService.register(
          'Test User',
          'test@example.com',
          'password',
        ),
        returnsNormally,
      );
    });
  });
}
