// MedicalPassportService against a MockClient, the pattern of
// consent_api_service_test.dart: each call's method, path and body, and how
// errors surface.
//
// Test Plan §3.28: TC-EMG-344…346 and 348…352 are the author's; TC-EMG-377
// and 378 are the Testing Lead's. TC-EMG-347 is withdrawn: createCode went
// when screen 2 (/emergency-qr) took over making the code (PR #362 follow-up).

import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/features/medical_passport/models/medical_passport.dart';
import 'package:care_connect_app/features/medical_passport/services/medical_passport_service.dart';

const _passport = {
  'name': 'Jordan Miller',
  'age': 41,
  'allergies': [],
  'medications': [],
  'sharing': {'ALLERGIES': true},
  'token': null,
  'ready': false,
};

Future<T> _with<T>(
  Future<T> Function() call,
  Future<http.Response> Function(http.Request) handler,
) =>
    http.runWithClient(call, () => MockClient(handler));

void main() {
  test('TC-EMG-344: fetch GETs /v1/api/passport and parses it', () async {
    late http.Request sent;
    final p = await _with(MedicalPassportService.fetch, (req) async {
      sent = req;
      return http.Response(jsonEncode(_passport), 200);
    });

    expect(sent.method, 'GET');
    expect(sent.url.path, '/v1/api/passport');
    expect(sent.headers['Accept'], 'application/json');
    expect(p.name, 'Jordan Miller');
    expect(p.isShared(PassportField.allergies), isTrue);
  });

  test('TC-EMG-345: setShared PUTs isPublic to the field\'s API name', () async {
    late http.Request sent;
    await _with(() => MedicalPassportService.setShared(PassportField.chronicConditions, false),
        (req) async {
      sent = req;
      return http.Response(jsonEncode(_passport), 200);
    });

    expect(sent.method, 'PUT');
    expect(sent.url.path, '/v1/api/passport/visibility/CHRONIC_CONDITIONS');
    expect(sent.headers['Content-Type'], startsWith('application/json'));
    expect(jsonDecode(sent.body), {'isPublic': false});
  });

  test('TC-EMG-346: updateProfile PUTs every field', () async {
    late http.Request sent;
    await _with(
        () => MedicalPassportService.updateProfile(const PassportProfileUpdate(
              bloodType: BloodType.abNegative,
              contactName: 'Dana',
            )), (req) async {
      sent = req;
      return http.Response(jsonEncode(_passport), 200);
    });

    expect(sent.method, 'PUT');
    expect(sent.url.path, '/v1/api/passport/profile');
    expect(jsonDecode(sent.body), {
      'bloodType': 'AB_NEGATIVE',
      'chronicConditions': null,
      'emergencyContactName': 'Dana',
      'emergencyContactRelationship': null,
      'emergencyContactPhone': null,
    });
  });

  test('TC-EMG-348: revokeCode DELETEs /token and accepts an empty 204', () async {
    late http.Request sent;
    await _with(MedicalPassportService.revokeCode, (req) async {
      sent = req;
      return http.Response('', 204);
    });

    expect(sent.method, 'DELETE');
    expect(sent.url.path, '/v1/api/passport/token');
  });

  group('errors', () {
    test('TC-EMG-349: a 400 carries the backend\'s error text', () async {
      final error = await _with(
        () => MedicalPassportService.updateProfile(const PassportProfileUpdate())
            .then<Object?>((_) => null, onError: (Object e) => e),
        (_) async => http.Response(jsonEncode({'error': 'emergencyContactPhone must be at most 32 characters'}), 400),
      );

      expect(error, isA<MedicalPassportException>());
      final e = error as MedicalPassportException;
      expect(e.statusCode, 400);
      expect(e.message, 'emergencyContactPhone must be at most 32 characters');
      expect(e.toString(), contains('400'));
    });

    test('TC-EMG-350: 403 is "not a patient" and 401 is "signed out"; an empty body has no message', () async {
      Future<MedicalPassportException> failWith(int status) => _with(
            () => MedicalPassportService.fetch().then<MedicalPassportException>(
                (_) => fail('expected an error'),
                onError: (Object e) => e as MedicalPassportException),
            (_) async => http.Response('', status),
          );

      final forbidden = await failWith(403);
      expect(forbidden.notAPatient, isTrue);
      expect(forbidden.signedOut, isFalse);
      expect(forbidden.message, isNull);

      final unauthorized = await failWith(401);
      expect(unauthorized.signedOut, isTrue);
      expect(unauthorized.notAPatient, isFalse);
    });

    test('TC-EMG-351: a non-object body is a FormatException', () async {
      await expectLater(
        _with(MedicalPassportService.fetch, (_) async => http.Response('[]', 200)),
        throwsA(isA<FormatException>()),
      );
    });

    test('TC-EMG-352: a revoke that fails throws', () async {
      await expectLater(
        _with(MedicalPassportService.revokeCode, (_) async => http.Response('{"error":"nope"}', 500)),
        throwsA(isA<MedicalPassportException>().having((e) => e.message, 'message', 'nope')),
      );
    });
  });

  test(
      'TC-EMG-377: a save that loses a race (409) is a MedicalPassportException '
      'with the backend\'s text, neither "not a patient" nor "signed out"',
      () async {
    final error = await _with(
      () => MedicalPassportService.setShared(PassportField.allergies, true)
          .then<Object?>((_) => null, onError: (Object e) => e),
      (_) async => http.Response(
          jsonEncode({'error': 'Your passport was changed at the same time'}), 409),
    );
    expect(error, isA<MedicalPassportException>());
    final e = error as MedicalPassportException;
    expect(e.statusCode, 409);
    expect(e.message, 'Your passport was changed at the same time');
    expect(e.notAPatient, isFalse);
    expect(e.signedOut, isFalse);
  });

  // A widget test only for its fake clock: no widget is pumped.
  testWidgets(
      'TC-EMG-378: every call gives up after 20 s when the server never '
      'answers, with a TimeoutException (DEF-EMG-16)', (t) async {
    // The sign-in header is read first; answer it at once, inside the fake clock.
    const secure = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(secure, (call) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(secure, null));
    SharedPreferences.setMockInitialValues({});
    final calls = <String, Future<Object?> Function()>{
      'fetch': MedicalPassportService.fetch,
      'updateProfile': () => MedicalPassportService.updateProfile(const PassportProfileUpdate()),
      'setShared': () => MedicalPassportService.setShared(PassportField.allergies, true),
      'revokeCode': MedicalPassportService.revokeCode,
    };
    for (final c in calls.entries) {
      Object? error;
      var done = false;
      http.runWithClient(
        () => c.value().then<void>((_) {
          done = true;
        }, onError: (Object e) {
          error = e;
          done = true;
        }),
        () => MockClient((_) => Completer<http.Response>().future),
      );
      await t.pump(const Duration(seconds: 19));
      expect(done, isFalse, reason: '${c.key} still waiting at 19 s');
      await t.pump(const Duration(seconds: 2));
      expect(error, isA<TimeoutException>(), reason: c.key);
    }
  });
}
