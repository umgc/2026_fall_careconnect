// IdentityConflictService: it never reports a save that didn't happen, and
// the sample conflict is opt-in only. Since the backend endpoint (#432) it
// loads and saves through GET/POST /v1/api/ehr/identity-conflicts.
// Test IDs TC-EHR-REC-065..069 and 094..101 are permanent. Never renumber,
// never reuse.

import 'dart:convert';
import 'dart:typed_data';

import 'package:care_connect_app/features/health/health_data/models/identity_conflict.dart';
import 'package:care_connect_app/features/health/health_data/services/identity_conflict_service.dart';
import 'package:care_connect_app/services/api_client.dart';
import 'package:care_connect_app/services/auth_service.dart';
import 'package:care_connect_app/services/user_role_storage_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // Every test talks to this fake backend: by default it has no pending
  // conflicts and refuses every save (400).
  late _FakeBackend backend;
  late HttpClientAdapter original;
  setUp(() {
    original = ApiClient.instance.debugHttpClientAdapter;
    backend = _FakeBackend();
    ApiClient.instance.debugSetHttpClientAdapter(backend);
  });
  tearDown(() => ApiClient.instance.debugSetHttpClientAdapter(original));

  group('with the demo data off (the default)', () {
    final service = IdentityConflictService(useMock: false);

    test('TC-EHR-REC-065: with nothing pending on the backend, there is '
        'nothing pending', () async {
      expect(await service.fetchPending(), isEmpty);
    });

    test('TC-EHR-REC-066: a choice the backend does not save is never '
        'reported as saved', () async {
      backend.postStatus = 500;
      expect(await service.resolve(1, accepted: true), isFalse);
      expect(await service.resolve(1, accepted: false), isFalse);
    });
  });

  group('the backend endpoint (#432)', () {
    final service = IdentityConflictService(useMock: false);
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      IdentityConflictService.clearFound();
    });

    Map<String, dynamic> dob(int id,
            {String before = '1980-05-14',
            String incoming = '1985-05-14',
            String field = 'date_of_birth',
            String status = 'PENDING'}) =>
        {
          'id': id,
          'fieldName': field,
          'canonicalValueBefore': before,
          'incomingValue': incoming,
          'canonicalSourceLabel': 'Epic',
          'incomingSourceLabel': 'Oracle Health',
          'status': status,
          'detectedAt': '2026-10-25T12:00:00Z',
          'identityCheck': {'type': 'PHONE', 'value': '4821'},
        };

    test('TC-EHR-REC-094: pending conflicts are loaded from the backend, '
        'with their sources and identity check, dates shown MM/DD/YYYY',
        () async {
      backend.conflicts = [dob(7)];
      final c = (await service.fetchPending()).single;
      expect(backend.gets.single.path, endsWith('/v1/api/ehr/identity-conflicts'));
      expect(backend.gets.single.queryParameters['status'], 'PENDING');
      expect(c.id, 7);
      expect(c.canonicalValueBefore, '05/14/1980');
      expect(c.incomingValue, '05/14/1985');
      expect(c.canonicalSourceLabel, 'Epic');
      expect(c.incomingSourceLabel, 'Oracle Health');
      expect(c.identityCheck?.type, IdentityCheckType.phone);
      expect(c.identityCheck?.value, '4821');
    });

    test('TC-EHR-REC-095: only pending date-of-birth conflicts with a '
        'backend id are offered', () async {
      backend.conflicts = [
        dob(1),
        dob(2, field: 'phone'),
        dob(3, status: 'REJECTED'),
        dob(0),
      ];
      expect((await service.fetchPending()).map((c) => c.id), [1]);
    });

    test('TC-EHR-REC-096: a date pair the backend already has and this '
        'device also found is shown once, as the backend\'s', () async {
      backend.conflicts = [dob(5, before: '1980-05-14', incoming: '1980-05-15')];
      await IdentityConflictService.reportDobDisagreement(
          current: DateTime(1980, 5, 14),
          currentSource: 'Epic',
          incoming: DateTime(1980, 5, 15),
          incomingSource: 'athenahealth');
      await IdentityConflictService.reportDobDisagreement(
          current: DateTime(1980, 5, 14),
          currentSource: 'Epic',
          incoming: DateTime(1990, 1, 1),
          incomingSource: 'athenahealth');
      final pending = await service.fetchPending();
      expect(pending.map((c) => c.id).first, 5);
      expect(pending, hasLength(2));
      expect(pending.last.id, isNegative);
      expect(pending.last.incomingValue, '01/01/1990');
    });

    for (final accepted in [true, false]) {
      test('TC-EHR-REC-101: once the backend saves '
          '${accepted ? 'Use new date' : 'Keep current'}, the same dates '
          'found on this device are not asked again, and Health Data shows '
          'the chosen date', () async {
        Future<DateTime?> report() =>
            IdentityConflictService.reportDobDisagreement(
                current: DateTime(1980, 5, 14),
                currentSource: 'Epic',
                incoming: DateTime(1980, 5, 15),
                incomingSource: 'athenahealth');
        backend.conflicts = [dob(5, before: '1980-05-14', incoming: '1980-05-15')];
        expect(await report(), isNull);
        expect((await service.fetchPending()).single.id, 5);

        backend.postStatus = 200;
        expect(await service.resolve(5, accepted: accepted), isTrue);
        backend.conflicts = [];

        expect(await service.fetchPending(), isEmpty);
        expect(await report(),
            accepted ? DateTime(1980, 5, 15) : DateTime(1980, 5, 14));
      });
    }

    for (final status in [400, 403, 404, 409]) {
      test('TC-EHR-REC-097: a $status from the backend means nothing to '
          'confirm there, and what this device found is still offered',
          () async {
        backend.getStatus = status;
        expect(await service.fetchPending(), isEmpty);
        await IdentityConflictService.reportDobDisagreement(
            current: DateTime(1980, 5, 14),
            currentSource: 'Epic',
            incoming: DateTime(1980, 5, 15),
            incomingSource: 'athenahealth');
        expect(await service.fetchPending(), hasLength(1));
      });
    }

    for (final failure in ['500', 'no connection']) {
      test('TC-EHR-REC-098: when the backend cannot be checked ($failure) '
          'loading fails, so the screen never says "all caught up"',
          () async {
        if (failure == '500') {
          backend.getStatus = 500;
        } else {
          backend.offline = true;
        }
        await expectLater(service.fetchPending(), throwsA(anything));
      });
    }

    for (final accepted in [true, false]) {
      test('TC-EHR-REC-099: ${accepted ? 'Use new date' : 'Keep current'} '
          'is saved through the backend and reported as saved', () async {
        backend.postStatus = 200;
        expect(await service.resolve(12, accepted: accepted), isTrue);
        final post = backend.posts.single;
        expect(post.path, endsWith('/v1/api/ehr/identity-conflicts/12/resolve'));
        expect(jsonDecode(jsonEncode(post.data)), {
          'status': accepted ? 'ACCEPTED' : 'REJECTED',
          'resolvedBy': 'PATIENT',
        });
      });
    }

    for (final failure in ['409', '500', 'no connection']) {
      test('TC-EHR-REC-100: a save that fails ($failure) is never reported '
          'as saved', () async {
        if (failure == 'no connection') {
          backend.offline = true;
        } else {
          backend.postStatus = int.parse(failure);
        }
        expect(await service.resolve(12, accepted: true), isFalse);
      });
    }
  });

  test('TC-EHR-REC-067: the default build has the demo data off', () {
    expect(IdentityConflictService().useMock, isFalse);
  });

  group('with the demo data on (CARECONNECT_DOB_MOCK=true)', () {
    final service = IdentityConflictService(useMock: true);

    test('TC-EHR-REC-068: one pending date-of-birth conflict is offered, from a named source', () async {
      final pending = await service.fetchPending();

      expect(pending, hasLength(1));
      final conflict = pending.single;
      expect(conflict.isDob, isTrue);
      expect(conflict.isPending, isTrue);
      expect(conflict.status, ConflictStatus.pending);
      expect(conflict.canonicalValueBefore, isNot(conflict.incomingValue));
      expect(conflict.incomingSourceLabel, isNotEmpty);
      expect(conflict.identityCheck?.type, IdentityCheckType.phone);
      expect(conflict.identityCheck?.value, '4821');
    });

    test('TC-EHR-REC-069: resolving succeeds either way', () async {
      expect(await service.resolve(1, accepted: true), isTrue);
      expect(await service.resolve(1, accepted: false), isTrue);
    });
  });

  group('a date of birth two connected sources disagree on (FR-XSRC-10…15)',
      () {
    TestWidgetsFlutterBinding.ensureInitialized();
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      IdentityConflictService.clearFound();
    });

    Future<DateTime?> report() => IdentityConflictService.reportDobDisagreement(
          current: DateTime(1980, 5, 14),
          currentSource: 'Epic',
          incoming: DateTime(1980, 5, 15),
          incomingSource: 'athenahealth',
        );

    test('is queued for the confirmation screen once, from named sources',
        () async {
      expect(await report(), isNull);
      expect(await report(), isNull);
      final pending = await IdentityConflictService(useMock: false).fetchPending();
      expect(pending, hasLength(1));
      final c = pending.single;
      expect(c.isDob, isTrue);
      expect(c.isPending, isTrue);
      expect(c.id, isNegative);
      expect(c.canonicalValueBefore, '05/14/1980');
      expect(c.incomingValue, '05/15/1980');
      expect(c.canonicalSourceLabel, 'Epic');
      expect(c.incomingSourceLabel, 'athenahealth');
    });

    for (final accepted in [true, false]) {
      test('${accepted ? 'Use new date' : 'Keep current'} is saved, leaves '
          'nothing pending, and decides the date shown', () async {
        await report();
        final service = IdentityConflictService(useMock: false);
        final id = (await service.fetchPending()).single.id;
        expect(await service.resolve(id, accepted: accepted), isTrue);
        expect(await service.fetchPending(), isEmpty);
        expect(await report(),
            accepted ? DateTime(1980, 5, 15) : DateTime(1980, 5, 14));
        expect(await service.fetchPending(), isEmpty);
      });
    }

    test('no date of birth is stored on the device', () async {
      await report();
      final service = IdentityConflictService(useMock: false);
      await service.resolve((await service.fetchPending()).single.id,
          accepted: true);
      final stored =
          (await SharedPreferences.getInstance()).getString('health_data.dob_choices')!;
      for (final text in ['1980', '05/14', '05/15', '14', '15']) {
        expect(stored.contains(text), isFalse, reason: text);
      }
    });

    test('a backend conflict id is still never reported as saved', () async {
      await report();
      expect(await IdentityConflictService(useMock: false)
          .resolve(1, accepted: true), isFalse);
    });
  });

  // Two accounts signed in one after the other in the same app session.
  group('date-of-birth conflicts belong to one patient', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    final storage = UserRoleStorageService.instance;
    final service = IdentityConflictService(useMock: false);

    Future<void> signIn(int userId, int patientId) => storage.setUserData(
        role: 'PATIENT', userId: userId, patientId: patientId);

    Future<DateTime?> report() => IdentityConflictService.reportDobDisagreement(
          current: DateTime(1980, 5, 14),
          currentSource: 'Epic',
          incoming: DateTime(1980, 5, 15),
          incomingSource: 'athenahealth',
        );

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      IdentityConflictService.clearFound();
      await storage.clearUserData();
    });
    tearDown(() => storage.clearUserData());

    test('another patient neither sees nor can resolve them', () async {
      await signIn(1, 10);
      await report();
      final id = (await service.fetchPending()).single.id;

      await storage.clearUserData();
      await signIn(2, 20);
      expect(await service.fetchPending(), isEmpty);
      expect(await service.resolve(id, accepted: true), isFalse);

      await signIn(1, 10);
      expect((await service.fetchPending()).single.id, id);
    });

    test("one patient's saved choice never decides another's date",
        () async {
      await signIn(1, 10);
      await report();
      await service.resolve((await service.fetchPending()).single.id,
          accepted: true);
      expect(await report(), DateTime(1980, 5, 15));

      await storage.clearUserData();
      await signIn(2, 20);
      expect(await report(), isNull);
      expect(await service.fetchPending(), hasLength(1));
    });

    test('logging out forgets them, so nobody signed in next sees them',
        () async {
      await signIn(1, 10);
      await report();
      expect(await service.fetchPending(), hasLength(1));

      try {
        await AuthService.logout();
      } catch (_) {
        // The backend is unreachable in tests; local cleanup still runs.
      }

      await signIn(1, 10);
      expect(await service.fetchPending(), isEmpty);
      await storage.clearUserData();
      await signIn(2, 20);
      expect(await service.fetchPending(), isEmpty);
    });
  });
}

/// A fake identity-conflicts backend for [ApiClient].
class _FakeBackend implements HttpClientAdapter {
  List<Map<String, dynamic>> conflicts = [];
  int getStatus = 200;
  int postStatus = 400;
  bool offline = false;
  final gets = <RequestOptions>[];
  final posts = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    if (offline) {
      throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
          message: 'offline');
    }
    final json = {
      Headers.contentTypeHeader: [Headers.jsonContentType]
    };
    if (options.method == 'GET') {
      gets.add(options);
      return getStatus == 200
          ? ResponseBody.fromString(
              jsonEncode({'resources': conflicts}), 200,
              headers: json)
          : ResponseBody.fromString('{"error":"x"}', getStatus, headers: json);
    }
    posts.add(options);
    return ResponseBody.fromString(
        postStatus == 200 ? '{"outcome":"applied"}' : '{"error":"x"}',
        postStatus,
        headers: json);
  }

  @override
  void close({bool force = false}) {}
}
