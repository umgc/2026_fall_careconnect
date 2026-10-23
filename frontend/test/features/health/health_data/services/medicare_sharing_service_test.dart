// MedicareSharingService against the 6.2.56 consent API (WBS 6.2.59, #323):
//   GET    /v1/api/caregiver-patient-links/patients/{id}/caregivers
//   GET    /v1/api/v3/consent/medicare-view?patientUserId=&granteeUserId=
//   POST   /v1/api/v3/consent/medicare-view
//   DELETE /v1/api/v3/consent/medicare-view
//
// Every request goes through http.runWithClient + MockClient; nothing touches
// the network. Test Plan §3.30: TC-MCR-SHR-001…009 are the PR's (009 is
// Terence's malformed-consent case); 023…029 are the Testing Lead's.
// AuthTokenManager reads flutter_secure_storage, which has no plugin in the
// test VM, so the stored-sign-in cases answer its channel from a map.

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/features/health/health_data/services/medicare_sharing_service.dart';

const _patient = 7;

Future<T> _with<T>(
  Future<T> Function() body,
  Future<http.Response> Function(http.Request req) handler, {
  List<http.Request>? seen,
}) =>
    http.runWithClient(
      body,
      () => MockClient((req) {
        seen?.add(req);
        return handler(req);
      }),
    );

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status);

Future<MedicareSharingError?> _loadError(
    Future<http.Response> Function(http.Request) handler) async {
  try {
    await _with(() => MedicareSharingService().load(), handler);
    return null;
  } on MedicareSharingException catch (e) {
    return e.error;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Future<int?> Function() previousUser;
  setUp(() {
    previousUser = MedicareSharingService.currentUserId;
    MedicareSharingService.currentUserId = () async => _patient;
  });
  tearDown(() => MedicareSharingService.currentUserId = previousUser);

  test(
      'TC-MCR-SHR-001: load lists the patient\'s ACTIVE caregivers once each, '
      'sorted by name, with each one\'s Medicare sharing state', () async {
    final seen = <http.Request>[];
    final list =
        await _with(() => MedicareSharingService().load(), (req) async {
      if (req.url.path
          .endsWith('/caregiver-patient-links/patients/7/caregivers')) {
        return _json([
          {
            'caregiverUserId': 21,
            'caregiverName': 'Zoe Park',
            'status': 'ACTIVE'
          },
          {
            'caregiverUserId': 22,
            'caregiverName': 'Ann Lee',
            'caregiverEmail': 'ann@example.test',
            'status': 'ACTIVE'
          },
          {
            'caregiverUserId': 22,
            'caregiverName': 'Ann Lee',
            'status': 'ACTIVE'
          },
          {
            'caregiverUserId': 23,
            'caregiverName': 'Pending Pat',
            'status': 'PENDING'
          },
          {
            'caregiverUserId': 24,
            'caregiverName': 'Gone Gil',
            'status': 'REVOKED'
          },
        ]);
      }
      if (req.url.path.endsWith('/v3/consent/medicare-view')) {
        expect(req.url.queryParameters['patientUserId'], '7');
        return _json(
            {'granted': req.url.queryParameters['granteeUserId'] == '22'});
      }
      fail('Unexpected request ${req.url}');
    }, seen: seen);

    expect(list.map((c) => c.name), ['Ann Lee', 'Zoe Park']);
    expect(list.map((c) => c.shared), [true, false]);
    expect(list.first.email, 'ann@example.test');
    // One links call and one consent check per listed caregiver, all GETs.
    expect(seen, hasLength(3));
    expect(seen.every((r) => r.method == 'GET'), isTrue);
  });

  test(
      'TC-MCR-SHR-002: a link with no status counts as active, and a blank '
      'name shows as "Caregiver"', () async {
    final list =
        await _with(() => MedicareSharingService().load(), (req) async {
      if (req.url.path.contains('caregiver-patient-links')) {
        return _json([
          {'caregiverUserId': '30', 'caregiverName': '  '},
        ]);
      }
      return _json({'granted': false});
    });
    expect(list.single.userId, 30);
    expect(list.single.name, 'Caregiver');
  });

  test(
      'TC-MCR-SHR-003: load maps 401, 403, 500, a bad body and a dropped '
      'connection to signedOut, notPatient, server, server and network',
      () async {
    expect(await _loadError((_) async => http.Response('', 401)),
        MedicareSharingError.signedOut);
    expect(await _loadError((_) async => http.Response('', 403)),
        MedicareSharingError.notPatient);
    expect(await _loadError((_) async => http.Response('', 500)),
        MedicareSharingError.server);
    expect(await _loadError((_) async => http.Response('not json', 200)),
        MedicareSharingError.server);
    expect(await _loadError((_) async => throw http.ClientException('down')),
        MedicareSharingError.network);
  });

  test('TC-MCR-SHR-004: with no signed-in user nothing is requested', () async {
    MedicareSharingService.currentUserId = () async => null;
    final seen = <http.Request>[];
    try {
      await _with(() => MedicareSharingService().load(), (_) async => _json([]),
          seen: seen);
      fail('expected signedOut');
    } on MedicareSharingException catch (e) {
      expect(e.error, MedicareSharingError.signedOut);
    }
    expect(seen, isEmpty);
  });

  test(
      'TC-MCR-SHR-005: a failed consent check fails the load rather than '
      'showing a guessed switch state', () async {
    expect(
        await _loadError((req) async => req.url.path.contains('consent')
            ? http.Response('', 500)
            : _json([
                {
                  'caregiverUserId': 21,
                  'caregiverName': 'Zoe',
                  'status': 'ACTIVE'
                }
              ])),
        MedicareSharingError.server);
  });

  test(
      'TC-MCR-SHR-006: turning sharing on POSTs the caregiver as a CAREGIVER '
      'grantee and succeeds on 201', () async {
    final seen = <http.Request>[];
    final ok = await _with(() => MedicareSharingService().setShared(21, true),
        (_) async => _json({'status': 'ACTIVE'}, 201),
        seen: seen);
    expect(ok, isTrue);
    expect(seen.single.method, 'POST');
    expect(seen.single.url.path, endsWith('/v1/api/v3/consent/medicare-view'));
    expect(jsonDecode(seen.single.body),
        {'granteeUserId': 21, 'granteeRole': 'CAREGIVER'});
    expect(seen.single.headers['Content-Type'], startsWith('application/json'));
  });

  test(
      'TC-MCR-SHR-007: turning sharing off DELETEs with the caregiver\'s id '
      'and succeeds on 200', () async {
    final seen = <http.Request>[];
    final ok = await _with(() => MedicareSharingService().setShared(21, false),
        (_) async => _json({'revokedCount': 1}),
        seen: seen);
    expect(ok, isTrue);
    expect(seen.single.method, 'DELETE');
    expect(jsonDecode(seen.single.body), {'granteeUserId': 21});
  });

  test('TC-MCR-SHR-008: a refused or failed change reports false', () async {
    expect(
        await _with(() => MedicareSharingService().setShared(21, true),
            (_) async => http.Response('', 400)),
        isFalse);
    expect(
        await _with(() => MedicareSharingService().setShared(21, false),
            (_) async => throw http.ClientException('down')),
        isFalse);
  });
  test(
      'TC-MCR-SHR-009: a missing or non-boolean "granted" fails the load '
      'instead of guessing "not shared"', () async {
    for (final state in [
      <String, Object?>{},
      {'granted': null},
      {'granted': 'true'},
      {'granted': 0}
    ]) {
      expect(
          await _loadError((req) async => req.url.path.contains('consent')
              ? _json(state)
              : _json([
                  {'caregiverUserId': 21, 'status': 'ACTIVE'}
                ])),
          MedicareSharingError.server);
    }
  });

  // ---- Testing Lead (Test Plan §3.30) ----

  List<Map<String, Object?>> oneLink() => [
        {'caregiverUserId': 21, 'caregiverName': 'Zoe Park', 'status': 'ACTIVE'}
      ];

  test(
      'TC-MCR-SHR-023: a 403 or a dropped connection on a consent check '
      'fails the load as notPatient or network', () async {
    expect(
        await _loadError((req) async => req.url.path.contains('consent')
            ? http.Response('', 403)
            : _json(oneLink())),
        MedicareSharingError.notPatient);
    expect(
        await _loadError((req) async => req.url.path.contains('consent')
            ? throw http.ClientException('down')
            : _json(oneLink())),
        MedicareSharingError.network);
  });

  test(
      'TC-MCR-SHR-024: a links body that is not a list fails the load; rows '
      'with no usable caregiver id, and non-object rows, are left out',
      () async {
    expect(await _loadError((_) async => _json({'caregivers': []})),
        MedicareSharingError.server);

    final seen = <http.Request>[];
    final list =
        await _with(() => MedicareSharingService().load(), (req) async {
      if (req.url.path.contains('caregiver-patient-links')) {
        return _json([
          {'caregiverName': 'No Id', 'status': 'ACTIVE'},
          {'caregiverUserId': 'abc', 'caregiverName': 'Bad Id'},
          'not an object',
          {'caregiverUserId': 21, 'caregiverName': 'Zoe Park', 'status': 'active'},
        ]);
      }
      return _json({'granted': false});
    }, seen: seen);
    expect(list.map((c) => c.name), ['Zoe Park']);
    // One consent check, for the one usable row only.
    expect(seen.where((r) => r.url.path.contains('consent')), hasLength(1));
  });

  test(
      'TC-MCR-SHR-025: names sort without regard to case, and a blank email '
      'is dropped', () async {
    final list =
        await _with(() => MedicareSharingService().load(), (req) async {
      if (req.url.path.contains('caregiver-patient-links')) {
        return _json([
          {'caregiverUserId': 1, 'caregiverName': 'carl Diaz'},
          {'caregiverUserId': 2, 'caregiverName': 'Bea Ortiz', 'caregiverEmail': ' '},
          {'caregiverUserId': 3, 'caregiverName': 'adam Wu'},
        ]);
      }
      return _json({'granted': true});
    });
    expect(list.map((c) => c.name), ['adam Wu', 'Bea Ortiz', 'carl Diaz']);
    expect(list[1].email, isNull);
  });

  test('TC-MCR-SHR-026: a change counts as saved on 200, 201 or 204 only',
      () async {
    for (final (status, saved) in [
      (200, true),
      (201, true),
      (204, true),
      (202, false),
      (403, false),
      (409, false),
      (500, false),
    ]) {
      for (final share in [true, false]) {
        expect(
            await _with(() => MedicareSharingService().setShared(21, share),
                (_) async => http.Response('', status)),
            saved,
            reason: '$status, share=$share');
      }
    }
  });

  group('with a stored sign-in', () {
    const secure = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    final store = <String, String>{};
    // Unsigned test JWTs: only the payload's exp is read, to keep them "valid".
    String jwt(String sub) =>
        'e30.${base64Url.encode(utf8.encode('{"sub":"$sub","exp":4102444800}')).replaceAll('=', '')}.sig';

    void signIn(int id, String role) => store['user_session'] =
        jsonEncode({'id': id, 'email': 'u$id@example.test', 'role': role});

    setUp(() {
      // The real lookups, which read the stored session.
      MedicareSharingService.currentUserId = previousUser;
      SharedPreferences.setMockInitialValues({});
      store
        ..clear()
        ..['jwt_token'] = jwt('old')
        ..['token_expiry'] = '4102444800';
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(secure, (call) async {
        final args = (call.arguments as Map?) ?? const {};
        final key = args['key'] as String?;
        switch (call.method) {
          case 'read':
            return store[key];
          case 'write':
            store[key!] = args['value'] as String;
            return null;
          case 'delete':
            store.remove(key);
            return null;
          case 'deleteAll':
            store.clear();
            return null;
          case 'containsKey':
            return store.containsKey(key);
          case 'readAll':
            return Map<String, String>.of(store);
        }
        return null;
      });
    });
    tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secure, null));

    test(
        'TC-MCR-SHR-027: a signed-in patient\'s own user id and stored token '
        'are used, and a 401 refreshes the sign-in once and retries', () async {
      signIn(41, 'PATIENT');
      final seen = <http.Request>[];
      final list =
          await _with(() => MedicareSharingService().load(), (req) async {
        if (req.url.path.endsWith('/refresh-token')) {
          return _json({
            'id': 41,
            'email': 'u41@example.test',
            'role': 'PATIENT',
            'token': jwt('new')
          });
        }
        final fresh = (req.headers['Authorization'] ?? '')
            .contains(jwt('new').split('.')[1]);
        if (!fresh) return http.Response('', 401);
        return req.url.path.contains('consent')
            ? _json({'granted': true})
            : _json(oneLink());
      }, seen: seen);
      expect(list.single.shared, isTrue);
      expect(seen.map((r) => '${r.method} ${r.url.path}'), [
        'GET /v1/api/caregiver-patient-links/patients/41/caregivers',
        'POST /v1/api/auth/refresh-token',
        'GET /v1/api/caregiver-patient-links/patients/41/caregivers',
        'GET /v1/api/v3/consent/medicare-view',
      ]);
      expect(seen.first.headers['Authorization'], 'Bearer ${jwt('old')}');
      expect(seen.last.headers['Authorization'], 'Bearer ${jwt('new')}');
      expect(seen.last.url.queryParameters,
          {'patientUserId': '41', 'granteeUserId': '21'});
    });

    test(
        'TC-MCR-SHR-028: a 401 on a save refreshes once and retries; when the '
        'refresh is refused the save reports false after one attempt',
        () async {
      signIn(41, 'PATIENT');
      final seen = <http.Request>[];
      final ok = await _with(() => MedicareSharingService().setShared(21, true),
          (req) async {
        if (req.url.path.endsWith('/refresh-token')) {
          return _json({
            'id': 41,
            'email': 'u41@example.test',
            'role': 'PATIENT',
            'token': jwt('new')
          });
        }
        return (req.headers['Authorization'] ?? '')
                .contains(jwt('new').split('.')[1])
            ? http.Response('{}', 201)
            : http.Response('', 401);
      }, seen: seen);
      expect(ok, isTrue);
      expect(seen.map((r) => '${r.method} ${r.url.path}'), [
        'POST /v1/api/v3/consent/medicare-view',
        'POST /v1/api/auth/refresh-token',
        'POST /v1/api/v3/consent/medicare-view',
      ]);
      expect(jsonDecode(seen.last.body),
          {'granteeUserId': 21, 'granteeRole': 'CAREGIVER'});

      seen.clear();
      final refused = await _with(
          () => MedicareSharingService().setShared(21, false),
          (_) async => http.Response('', 401),
          seen: seen);
      expect(refused, isFalse);
      expect(seen.map((r) => '${r.method} ${r.url.path}'), [
        'DELETE /v1/api/v3/consent/medicare-view',
        'POST /v1/api/auth/refresh-token',
      ]);
    });

    // DEF-MCR-31: the links endpoint answers any signed-in user for their own
    // id, so a caregiver or family member got an empty list and the "no linked
    // caregivers yet" text instead of being told the screen is the patient's.
    test(
        'TC-MCR-SHR-029: a signed-in caregiver, family member or admin is told '
        'only the patient can choose, and nothing is requested', () async {
      for (final role in ['CAREGIVER', 'FAMILY_MEMBER', 'ADMIN']) {
        signIn(52, role);
        final seen = <http.Request>[];
        MedicareSharingError? error;
        try {
          await _with(() => MedicareSharingService().load(),
              (_) async => _json([]), seen: seen);
        } on MedicareSharingException catch (e) {
          error = e.error;
        }
        expect(error, MedicareSharingError.notPatient, reason: role);
        expect(seen, isEmpty, reason: role);
      }
      // A lower-case stored role still counts as the patient.
      signIn(41, 'patient');
      final list = await _with(
          () => MedicareSharingService().load(), (req) async => _json([]));
      expect(list, isEmpty);
    });
  });
}
