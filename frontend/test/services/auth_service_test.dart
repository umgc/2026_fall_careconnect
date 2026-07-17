import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/services/auth_service.dart';

typedef RequestHandler = Future<void> Function(HttpRequest request);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  final Map<String, String> secureStorage = <String, String>{};

  late HttpServer server;
  HttpOverrides? previousOverrides;

  final Map<String, RequestHandler> handlers = <String, RequestHandler>{};

  setUpAll(() async {
    // Mock flutter_secure_storage so AuthTokenManager/UserRoleStorageService
    // can run inside widget tests without platform errors.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      secureStorageChannel,
      (MethodCall methodCall) async {
        final Map<dynamic, dynamic> args =
            (methodCall.arguments as Map<dynamic, dynamic>?) ??
                <dynamic, dynamic>{};

        final String? key = args['key'] as String?;
        final String? value = args['value'] as String?;

        switch (methodCall.method) {
          case 'read':
            return secureStorage[key];
          case 'write':
            if (key != null && value != null) {
              secureStorage[key] = value;
            }
            return null;
          case 'delete':
            if (key != null) {
              secureStorage.remove(key);
            }
            return null;
          case 'deleteAll':
            secureStorage.clear();
            return null;
          case 'containsKey':
            return key != null && secureStorage.containsKey(key);
          case 'readAll':
            return Map<String, String>.from(secureStorage);
          default:
            return null;
        }
      },
    );

    // Local fake HTTP server. All outgoing package:http requests are rewritten
    // to this server by HttpOverrides below.
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(
      server.forEach((HttpRequest request) async {
        final RequestHandler? handler = handlers[request.uri.path];
        if (handler != null) {
          await handler(request);
          await request.response.close();
          return;
        }

        request.response.statusCode = HttpStatus.notFound;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(<String, dynamic>{
          'error': 'Unhandled path: ${request.uri.path}',
        }));
        await request.response.close();
      }),
    );

    previousOverrides = HttpOverrides.current;
    HttpOverrides.global = _RewritingHttpOverrides(server.port);
  });

  tearDownAll(() async {
    HttpOverrides.global = previousOverrides;
    await server.close(force: true);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
  });

  setUp(() async {
    handlers.clear();
    secureStorage.clear();
    SharedPreferences.setMockInitialValues(<String, Object>{});

    // Best-effort cleanup for tests that touch auth/user storage.
    try {
      await AuthService.initialize();
    } catch (_) {}
    try {
      await AuthService.logout();
    } catch (_) {}
  });

  group('ApiConstants', () {
    test('builds core URLs from env-backed base URL', () {
      // Verifies the constants expose the expected auth/users/caregivers roots.
      expect(ApiConstants.baseUrl, isNotEmpty);
      expect(ApiConstants.auth, contains('/v1/api/auth'));
      expect(ApiConstants.caregivers, contains('/v1/api/caregivers'));
      expect(ApiConstants.users, contains('/v1/api/users'));
      expect(ApiConstants.webBaseUrl, isNotEmpty);
    });
  });

  group('AuthService singleton and simple helpers', () {
    test('instance returns the same singleton object', () {
      // Verifies the singleton accessor always returns the same instance.
      expect(identical(AuthService.instance, AuthService.instance), isTrue);
    });

    test('initialize completes without throwing', () async {
      // Verifies storage initialization can be called safely.
      await AuthService.initialize();
    });

    test('handleOAuthCallback completes without throwing', () async {
      // Verifies the callback helper is safe to call even though it currently
      // only logs diagnostic output.
      await AuthService.handleOAuthCallback('code-123', 'state-456');
    });

    test('updateUserActivity completes without throwing', () async {
      // Verifies the activity update path delegates to token storage cleanly.
      await AuthService.updateUserActivity();
    });
  });

  group('register', () {
    test('returns string body when backend returns a plain string', () async {
      // Verifies the branch where the backend responds with a raw JSON string.
      handlers['/v1/api/auth/register'] = (HttpRequest request) async {
        expect(request.method, 'POST');

        final String body = await utf8.decoder.bind(request).join();
        final Map<String, dynamic> payload =
            jsonDecode(body) as Map<String, dynamic>;

        expect(payload['name'], 'Test User');
        expect(payload['email'], 'test@example.com');
        expect(payload['password'], 'secret');
        expect(payload['role'], 'PATIENT');
        expect(payload['verificationBaseUrl'], 'https://frontend.example.com');

        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode('Registered successfully'));
      };

      final String result = await AuthService.register(
        name: 'Test User',
        email: 'test@example.com',
        password: 'secret',
        verificationBaseUrl: 'https://frontend.example.com',
      );

      expect(result, 'Registered successfully');
    });

    test('returns message field when backend returns JSON object', () async {
      // Verifies the branch where the backend responds with a JSON object.
      handlers['/v1/api/auth/register'] = (HttpRequest request) async {
        request.response.statusCode = HttpStatus.created;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(<String, dynamic>{
          'message': 'Check your email',
        }));
      };

      final String result = await AuthService.register(
        name: 'Test User',
        email: 'test@example.com',
        password: 'secret',
        verificationBaseUrl: 'https://frontend.example.com',
      );

      expect(result, 'Check your email');
    });

    test('throws when backend returns an error response', () async {
      // Verifies registration failures surface the backend error message.
      handlers['/v1/api/auth/register'] = (HttpRequest request) async {
        request.response.statusCode = HttpStatus.badRequest;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(<String, dynamic>{
          'error': 'Email already exists',
        }));
      };

      await expectLater(
        AuthService.register(
          name: 'Test User',
          email: 'test@example.com',
          password: 'secret',
          verificationBaseUrl: 'https://frontend.example.com',
        ),
        throwsA(
          isA<Exception>().having(
            (Exception e) => e.toString(),
            'message',
            contains('Email already exists'),
          ),
        ),
      );
    });
  });

  group('registerCaregiver', () {
    test('registers caregiver with professional and address data', () async {
      // Verifies optional professional/address blocks are included and that the
      // success payload extracts nested user and caregiver identifiers.
      handlers['/v1/api/caregivers'] = (HttpRequest request) async {
        expect(request.method, 'POST');

        final String body = await utf8.decoder.bind(request).join();
        final Map<String, dynamic> payload =
            jsonDecode(body) as Map<String, dynamic>;

        expect(payload['firstName'], 'Jane');
        expect(payload['lastName'], 'Doe');
        expect(payload['email'], 'jane@example.com');
        expect(payload['credentials']['email'], 'jane@example.com');
        expect(payload['credentials']['password'], 'secret');
        expect(payload['professional']['licenseNumber'], 'RN-123');
        expect(payload['professional']['issuingState'], 'NY');
        expect(payload['professional']['yearsExperience'], 5);
        expect(payload['address']['line1'], '123 Main St');
        expect(payload['address']['city'], 'Albany');
        expect(payload['address']['state'], 'NY');
        expect(payload['address']['zip'], '12207');

        request.response.statusCode = HttpStatus.created;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(<String, dynamic>{
          'id': 9001,
          'user': <String, dynamic>{
            'id': 42,
            'paymentCustomerId': 'cus_123',
          },
        }));
      };

      final Map<String, dynamic> result = await AuthService.registerCaregiver(
        firstName: 'Jane',
        lastName: 'Doe',
        email: 'jane@example.com',
        password: 'secret',
        gender: 'female',
        phone: '555-555-5555',
        licenseNumber: 'RN-123',
        issuingState: 'NY',
        yearsExperience: 5,
        addressLine1: '123 Main St',
        city: 'Albany',
        state: 'NY',
        zip: '12207',
      );

      expect(result['message'], 'Caregiver registration successful!');
      expect(result['userId'], '42');
      expect(result['caregiverId'], '9001');
      expect(result['paymentCustomerId'], 'cus_123');
    });

    test('registers caregiver with default values when optional data is omitted',
        () async {
      // Verifies the null/default-path logic for optional fields and the branch
      // where professional/address blocks are not added.
      handlers['/v1/api/caregivers'] = (HttpRequest request) async {
        final String body = await utf8.decoder.bind(request).join();
        final Map<String, dynamic> payload =
            jsonDecode(body) as Map<String, dynamic>;

        expect(payload['dob'], '01/01/1990');
        expect(payload['phone'], '000-000-0000');
        expect(payload['gender'], '');
        expect(payload.containsKey('professional'), isFalse);
        expect(payload.containsKey('address'), isFalse);
        expect(payload['credentials']['email'], 'minimal@example.com');

        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(<String, dynamic>{
          'id': 100,
          'user': <String, dynamic>{
            'id': 5,
            'paymentCustomerId': '',
          },
        }));
      };

      final Map<String, dynamic> result = await AuthService.registerCaregiver(
        firstName: 'Min',
        lastName: 'User',
        email: 'minimal@example.com',
        password: 'secret',
      );

      expect(result['userId'], '5');
      expect(result['caregiverId'], '100');
      expect(result['paymentCustomerId'], '');
    });

    test('throws when caregiver registration fails', () async {
      // Verifies backend errors are rethrown for caller handling.
      handlers['/v1/api/caregivers'] = (HttpRequest request) async {
        request.response.statusCode = HttpStatus.badRequest;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(<String, dynamic>{
          'error': 'Caregiver registration failed',
        }));
      };

      await expectLater(
        AuthService.registerCaregiver(
          firstName: 'Bad',
          lastName: 'Request',
          email: 'bad@example.com',
          password: 'secret',
        ),
        throwsA(
          isA<Exception>().having(
            (Exception e) => e.toString(),
            'message',
            contains('Caregiver registration failed'),
          ),
        ),
      );
    });
  });

  group('verifyEmail', () {
    test('returns success message on 200', () async {
      // Verifies successful email verification returns the backend message.
      handlers['/v1/api/auth/verify'] = (HttpRequest request) async {
        final String body = await utf8.decoder.bind(request).join();
        final Map<String, dynamic> payload =
            jsonDecode(body) as Map<String, dynamic>;
        expect(payload['token'], 'verify-token');

        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(<String, dynamic>{
          'message': 'Email verified successfully!',
        }));
      };

      final String result = await AuthService.verifyEmail('verify-token');
      expect(result, 'Email verified successfully!');
    });

    test('throws on non-200 response', () async {
      // Verifies verification failures surface backend error text.
      handlers['/v1/api/auth/verify'] = (HttpRequest request) async {
        request.response.statusCode = HttpStatus.badRequest;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(<String, dynamic>{
          'error': 'Invalid token',
        }));
      };

      await expectLater(
        AuthService.verifyEmail('bad-token'),
        throwsA(
          isA<Exception>().having(
            (Exception e) => e.toString(),
            'message',
            contains('Invalid token'),
          ),
        ),
      );
    });
  });

  group('requestPasswordReset', () {
    test('returns success message on 200', () async {
      // Verifies the forgot-password flow returns the backend success message.
      handlers['/v1/api/auth/password/forgot'] = (HttpRequest request) async {
        final String body = await utf8.decoder.bind(request).join();
        final Map<String, dynamic> payload =
            jsonDecode(body) as Map<String, dynamic>;
        expect(payload['email'], 'reset@example.com');

        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(<String, dynamic>{
          'message': 'Reset link sent',
        }));
      };

      final String result =
          await AuthService.requestPasswordReset(email: 'reset@example.com');

      expect(result, 'Reset link sent');
    });

    test('wraps backend failure in Network error exception', () async {
      // Verifies the method catches exceptions and wraps them with the
      // "Network error:" prefix used by the implementation.
      handlers['/v1/api/auth/password/forgot'] = (HttpRequest request) async {
        request.response.statusCode = HttpStatus.badRequest;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(<String, dynamic>{
          'message': 'Unknown email',
        }));
      };

      await expectLater(
        AuthService.requestPasswordReset(email: 'missing@example.com'),
        throwsA(
          isA<Exception>().having(
            (Exception e) => e.toString(),
            'message',
            allOf(
              contains('Network error'),
              contains('Unknown email'),
            ),
          ),
        ),
      );
    });
  });

  group('resetPassword', () {
    test('returns success message on 200', () async {
      // Verifies successful password reset returns the backend message.
      handlers['/v1/api/users/reset-password'] = (HttpRequest request) async {
        final String body = await utf8.decoder.bind(request).join();
        final Map<String, dynamic> payload =
            jsonDecode(body) as Map<String, dynamic>;

        expect(payload['username'], 'user@example.com');
        expect(payload['resetToken'], 'reset-token');
        expect(payload['newPassword'], 'new-password');

        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(<String, dynamic>{
          'message': 'Password reset successfully!',
        }));
      };

      final String result = await AuthService.resetPassword(
        email: 'user@example.com',
        resetToken: 'reset-token',
        newPassword: 'new-password',
      );

      expect(result, 'Password reset successfully!');
    });

    test('maps expired-token backend error to friendly message', () async {
      // Verifies the special-case expired-token branch.
      handlers['/v1/api/users/reset-password'] = (HttpRequest request) async {
        request.response.statusCode = HttpStatus.badRequest;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(<String, dynamic>{
          'error': 'Token expired',
        }));
      };

      await expectLater(
        AuthService.resetPassword(
          email: 'user@example.com',
          resetToken: 'expired',
          newPassword: 'new-password',
        ),
        throwsA(
          isA<Exception>().having(
            (Exception e) => e.toString(),
            'message',
            contains('Password reset link has expired'),
          ),
        ),
      );
    });

    test('maps invalid-token backend error to friendly message', () async {
      // Verifies the special-case invalid-token branch.
      handlers['/v1/api/users/reset-password'] = (HttpRequest request) async {
        request.response.statusCode = HttpStatus.badRequest;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(<String, dynamic>{
          'error': 'Invalid reset token',
        }));
      };

      await expectLater(
        AuthService.resetPassword(
          email: 'user@example.com',
          resetToken: 'invalid',
          newPassword: 'new-password',
        ),
        throwsA(
          isA<Exception>().having(
            (Exception e) => e.toString(),
            'message',
            contains('Invalid reset token'),
          ),
        ),
      );
    });

    test('throws generic backend error when no special case matches', () async {
      // Verifies fallback error propagation for other reset failures.
      handlers['/v1/api/users/reset-password'] = (HttpRequest request) async {
        request.response.statusCode = HttpStatus.badRequest;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(<String, dynamic>{
          'message': 'Password too weak',
        }));
      };

      await expectLater(
        AuthService.resetPassword(
          email: 'user@example.com',
          resetToken: 'weak',
          newPassword: '123',
        ),
        throwsA(
          isA<Exception>().having(
            (Exception e) => e.toString(),
            'message',
            contains('Password too weak'),
          ),
        ),
      );
    });
  });

  group('processOAuthCallback', () {
    test('throws a wrapped exception when user data cannot be decoded',
        () async {
      // Verifies the catch/rethrow branch for malformed callback payloads.
      await expectLater(
        AuthService.processOAuthCallback(
          token: 'jwt-token',
          userDataString: '%7Bnot-valid-json',
        ),
        throwsA(
          isA<Exception>().having(
            (Exception e) => e.toString(),
            'message',
            contains('Failed to process OAuth callback'),
          ),
        ),
      );
    });
  });

  group('forceRefreshToken', () {
    test('returns null when there is no current token', () async {
      // Verifies the early-return path when the user is not authenticated.
      final result = await AuthService.forceRefreshToken();
      expect(result, isNull);
    });
  });

  group('logout', () {
    test('completes even when backend returns a non-200 response', () async {
      // Verifies logout always clears local auth state and does not throw based
      // on the backend status code.
      handlers['/v1/api/auth/logout'] = (HttpRequest request) async {
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(<String, dynamic>{
          'error': 'Server error',
        }));
      };

      await AuthService.logout();
    });

    test('completes on 200 response', () async {
      // Verifies the success path also completes without error.
      handlers['/v1/api/auth/logout'] = (HttpRequest request) async {
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(<String, dynamic>{
          'message': 'Logged out',
        }));
      };

      await AuthService.logout();
    });
  });

  group('UserRoleStorageService pass-through helpers', () {
    test('role helpers and auth helpers can be called through AuthService',
        () async {
      // Verifies the public pass-through helpers delegate to the underlying
      // storage service without throwing.
      await AuthService.initialize();

      final bool initialAuth = await AuthService.isUserAuthenticated();
      expect(initialAuth, isA<bool>());

      final String? initialRole = await AuthService.getUserRole();
      expect(initialRole, anyOf(isNull, isA<String>()));

      await AuthService.updateUserRole('CAREGIVER');
      final String? updatedRole = await AuthService.getUserRole();
      expect(updatedRole, anyOf(isNull, 'CAREGIVER'));

      await AuthService.updatePatientId(123);
      final dynamic userData = await AuthService.getCurrentUserData();
      expect(userData, anyOf(isNull, isNotNull));
    });
  });

  group('Alexa SSO helpers', () {
    test('getAlexaAuthorizationCode returns success payload on 200', () async {
      // Verifies successful Alexa authorization-code generation.
      handlers['/v1/api/auth/sso/alexa/code'] = (HttpRequest request) async {
        expect(request.method, 'POST');
        expect(
          request.headers.value('authorization'),
          'Bearer token-123',
        );

        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(<String, dynamic>{
          'code': 'temp-code-123',
        }));
      };

      final Map<String, dynamic> result =
          await AuthService.getAlexaAuthorizationCode(token: 'token-123');

      expect(result['isSuccess'], isTrue);
      expect(result['code'], 'temp-code-123');
      expect(result['message'], 'Authorization code generated successfully');
    });

    test('getAlexaAuthorizationCode returns unauthorized payload on 401',
        () async {
      // Verifies the explicit 401 handling branch.
      handlers['/v1/api/auth/sso/alexa/code'] = (HttpRequest request) async {
        request.response.statusCode = HttpStatus.unauthorized;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(<String, dynamic>{
          'error': 'invalid_token',
        }));
      };

      final Map<String, dynamic> result =
          await AuthService.getAlexaAuthorizationCode(token: 'bad-token');

      expect(result['isSuccess'], isFalse);
      expect(result['code'], isNull);
      expect(result['message'], 'invalid_token');
    });

    test('getAlexaAuthorizationCode returns generic failure on other errors',
        () async {
      // Verifies non-200/non-401 responses use the generic failure branch.
      handlers['/v1/api/auth/sso/alexa/code'] = (HttpRequest request) async {
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(<String, dynamic>{
          'error': 'backend_failure',
        }));
      };

      final Map<String, dynamic> result =
          await AuthService.getAlexaAuthorizationCode(token: 'token-123');

      expect(result['isSuccess'], isFalse);
      expect(result['code'], isNull);
      expect(result['message'], 'backend_failure');
    });

    test('unlinkAlexaAccount returns success on 200', () async {
      // Verifies successful Alexa unlink response mapping.
      handlers['/v1/api/auth/sso/alexa/unlink'] = (HttpRequest request) async {
        expect(request.method, 'POST');

        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(<String, dynamic>{
          'message': 'ok',
        }));
      };

      final Map<String, dynamic> result =
          await AuthService.unlinkAlexaAccount();

      expect(result['isSuccess'], isTrue);
      expect(result['message'], 'Alexa account unlinked successfully');
    });

    test('unlinkAlexaAccount returns backend error message on failure',
        () async {
      // Verifies failed unlink responses surface the backend error.
      handlers['/v1/api/auth/sso/alexa/unlink'] = (HttpRequest request) async {
        request.response.statusCode = HttpStatus.badRequest;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(<String, dynamic>{
          'error': 'Failed to unlink Alexa account',
        }));
      };

      final Map<String, dynamic> result =
          await AuthService.unlinkAlexaAccount();

      expect(result['isSuccess'], isFalse);
      expect(result['message'], 'Failed to unlink Alexa account');
    });

    test('unlinkAlexaAccount returns error payload when response body is malformed',
        () async {
      // Verifies the catch branch when jsonDecode throws on a non-JSON body.
      handlers['/v1/api/auth/sso/alexa/unlink'] = (HttpRequest request) async {
        request.response.statusCode = HttpStatus.badRequest;
        request.response.headers.contentType = ContentType.text;
        request.response.write('not-valid-json');
      };

      final Map<String, dynamic> result =
          await AuthService.unlinkAlexaAccount();

      expect(result['isSuccess'], isFalse);
      expect(
        result['message'].toString(),
        startsWith('An unexpected error occurred'),
      );
    });

    test('getAlexaAuthorizationCode returns error payload when response body is malformed',
        () async {
      // Verifies the generic catch branch when jsonDecode throws.
      handlers['/v1/api/auth/sso/alexa/code'] = (HttpRequest request) async {
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType.text;
        request.response.write('not-valid-json');
      };

      final Map<String, dynamic> result =
          await AuthService.getAlexaAuthorizationCode(token: 'token-123');

      expect(result['isSuccess'], isFalse);
      expect(result['message'].toString(), startsWith('Error:'));
    });
  });

  group('login', () {
    test('returns UserSession on successful login', () async {
      // Verifies the success path stores auth data and returns a valid session.
      handlers['/v1/api/auth/login'] = (HttpRequest request) async {
        expect(request.method, 'POST');

        final String body = await utf8.decoder.bind(request).join();
        final Map<String, dynamic> payload =
            jsonDecode(body) as Map<String, dynamic>;
        expect(payload['email'], 'login@example.com');
        expect(payload['password'], 'password123');

        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(<String, dynamic>{
          'id': 1,
          'email': 'login@example.com',
          'role': 'PATIENT',
          'token': 'login-jwt-token',
          'name': 'Login User',
          'emailVerified': true,
        }));
      };

      final result =
          await AuthService.login('login@example.com', 'password123');

      expect(result.email, 'login@example.com');
      expect(result.role, 'PATIENT');
    });

    test('throws on failed login', () async {
      // Verifies that a non-200 login response surfaces the backend error.
      handlers['/v1/api/auth/login'] = (HttpRequest request) async {
        request.response.statusCode = HttpStatus.unauthorized;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(<String, dynamic>{
          'error': 'Invalid credentials',
        }));
      };

      await expectLater(
        AuthService.login('bad@example.com', 'wrongpassword'),
        throwsA(
          isA<Exception>().having(
            (Exception e) => e.toString(),
            'message',
            contains('Invalid credentials'),
          ),
        ),
      );
    });
  });

  group('processOAuthCallback success', () {
    test('processes valid callback data and returns UserSession', () async {
      // Verifies the happy path where URL-decoded JSON produces a valid session.
      final String userData = jsonEncode(<String, dynamic>{
        'id': 2,
        'email': 'oauth@example.com',
        'role': 'CAREGIVER',
        'token': 'oauth-jwt',
        'name': 'OAuth User',
        'emailVerified': true,
      });

      final result = await AuthService.processOAuthCallback(
        token: 'oauth-jwt',
        userDataString: userData,
      );

      expect(result.email, 'oauth@example.com');
      expect(result.role, 'CAREGIVER');
    });
  });

  group('forceRefreshToken with existing token', () {
    test('returns UserSession when backend returns 200', () async {
      // Verifies the success path: token is refreshed and new session returned.
      secureStorage['jwt_token'] = 'existing-token';
      final int farFuture =
          DateTime.now().add(const Duration(days: 365)).millisecondsSinceEpoch ~/
              1000;
      secureStorage['token_expiry'] = farFuture.toString();

      handlers['/v1/api/auth/refresh-token'] = (HttpRequest request) async {
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(<String, dynamic>{
          'id': 1,
          'email': 'refreshed@example.com',
          'role': 'PATIENT',
          'token': 'new-jwt-token',
          'emailVerified': true,
        }));
      };

      final result = await AuthService.forceRefreshToken();

      expect(result, isNotNull);
      expect(result!.email, 'refreshed@example.com');
    });

    test('returns null when backend returns non-200', () async {
      // Verifies the failure path clears auth data and returns null.
      secureStorage['jwt_token'] = 'existing-token';
      final int farFuture =
          DateTime.now().add(const Duration(days: 365)).millisecondsSinceEpoch ~/
              1000;
      secureStorage['token_expiry'] = farFuture.toString();

      handlers['/v1/api/auth/refresh-token'] = (HttpRequest request) async {
        request.response.statusCode = HttpStatus.unauthorized;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
            jsonEncode(<String, dynamic>{'error': 'Token expired'}));
      };

      final result = await AuthService.forceRefreshToken();

      expect(result, isNull);
    });

    test('returns null when response body is malformed JSON', () async {
      // Verifies the catch branch: jsonDecode failure clears auth and returns null.
      secureStorage['jwt_token'] = 'existing-token';
      final int farFuture =
          DateTime.now().add(const Duration(days: 365)).millisecondsSinceEpoch ~/
              1000;
      secureStorage['token_expiry'] = farFuture.toString();

      handlers['/v1/api/auth/refresh-token'] = (HttpRequest request) async {
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType.text;
        request.response.write('not-valid-json');
      };

      final result = await AuthService.forceRefreshToken();

      expect(result, isNull);
    });
  });

  group('registerCaregiver edge cases', () {
    test('handles response without nested user object', () async {
      // Verifies the branch where the response lacks a "user" object,
      // defaulting userId to "0".
      handlers['/v1/api/caregivers'] = (HttpRequest request) async {
        request.response.statusCode = HttpStatus.created;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(<String, dynamic>{
          'id': 55,
        }));
      };

      final Map<String, dynamic> result = await AuthService.registerCaregiver(
        firstName: 'No',
        lastName: 'UserObj',
        email: 'nouserobj@example.com',
        password: 'secret',
      );

      expect(result['caregiverId'], '55');
      expect(result['userId'], '0');
    });
  });

  group('getCurrentUser', () {
    test('returns null when no session is stored', () async {
      // Verifies that getCurrentUser returns null when secureStorage has no
      // user_session entry.
      final result = await AuthService.getCurrentUser();
      expect(result, isNull);
    });

    test('returns UserSession when session data exists', () async {
      // Verifies that getCurrentUser correctly deserializes stored session
      // data into a UserSession object with the expected field values.
      secureStorage['user_session'] = jsonEncode(<String, dynamic>{
        'id': 42,
        'email': 'current@example.com',
        'role': 'PATIENT',
        'token': 'stored-jwt-token',
        'name': 'Current User',
        'emailVerified': true,
        'patientId': 7,
      });

      final result = await AuthService.getCurrentUser();

      expect(result, isNotNull);
      expect(result!.id, 42);
      expect(result.email, 'current@example.com');
      expect(result.role, 'PATIENT');
      expect(result.token, 'stored-jwt-token');
      expect(result.name, 'Current User');
      expect(result.emailVerified, isTrue);
      expect(result.patientId, 7);
    });

    test('returns null on malformed session data', () async {
      // Verifies that getCurrentUser catches JSON decode errors from
      // malformed data and returns null instead of throwing.
      secureStorage['user_session'] = 'not-valid-json{{{';

      final result = await AuthService.getCurrentUser();
      expect(result, isNull);
    });
  });
}

/// Rewrites all outgoing `package:http` requests to the local fake server while
/// preserving the original request path and query string. This lets the tests
/// exercise production code that calls `http.post(...)` directly.
class _RewritingHttpOverrides extends HttpOverrides {
  _RewritingHttpOverrides(this.port);

  final int port;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final HttpClient inner = super.createHttpClient(context);
    return _RewritingHttpClient(inner, port);
  }
}

class _RewritingHttpClient implements HttpClient {
  _RewritingHttpClient(this._inner, this._port);

  final HttpClient _inner;
  final int _port;

  Uri _rewrite(Uri original) {
    return Uri(
      scheme: 'http',
      host: '127.0.0.1',
      port: _port,
      path: original.path,
      query: original.hasQuery ? original.query : null,
    );
  }

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) {
    return _inner.openUrl(method, _rewrite(url));
  }

  @override
  Future<HttpClientRequest> postUrl(Uri url) {
    return _inner.postUrl(_rewrite(url));
  }

  @override
  void close({bool force = false}) {
    _inner.close(force: force);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    return super.noSuchMethod(invocation);
  }
}