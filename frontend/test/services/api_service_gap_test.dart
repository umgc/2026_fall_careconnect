// Gap-filling tests for lib/services/api_service.dart.
//
// Strategy: ApiService exposes debugSetHttpClient, so a package:http MockClient
// records the exact method/URL/headers/body each static method produces and
// returns canned responses. A few methods build their own multipart request or
// use top-level http.* calls; those go through a fake HttpOverrides installed
// once in setUpAll. Auth state comes from FlutterSecureStorage mock values with
// a far-future expiry so no token validation call is attempted.

import 'dart:convert';
import 'dart:io';

import 'package:care_connect_app/services/api_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_http_overrides.dart';

typedef _Route = http.Response Function(http.Request req);

void main() {
  final requests = <http.Request>[];
  _Route route = (r) => http.Response('{}', 200);
  FakeResponse Function(String, Uri) rawRoute =
      (m, u) => FakeResponse(200, '{}');
  final rawRequests = <String>[];

  void signIn({Map<String, dynamic>? session}) {
    final exp =
        DateTime.now().add(const Duration(hours: 2)).millisecondsSinceEpoch ~/
            1000;
    FlutterSecureStorage.setMockInitialValues({
      'jwt_token': 'tok-xyz',
      'token_expiry': '$exp',
      if (session != null) 'user_session': jsonEncode(session),
    });
  }

  setUpAll(() {
    HttpOverrides.global = FakeHttpOverrides((m, u) {
      rawRequests.add('$m ${u.path}');
      return rawRoute(m, u);
    });
  });

  tearDownAll(() {
    ApiService.debugResetHttpClient();
    HttpOverrides.global = null;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    signIn();
    requests.clear();
    rawRequests.clear();
    route = (r) => http.Response('{}', 200);
    rawRoute = (m, u) => FakeResponse(200, '{}');
    ApiService.debugSetHttpClient(MockClient((req) async {
      requests.add(req);
      return route(req);
    }));
  });

  http.Request last() => requests.last;

  group('caregiver / patient link lookups', () {
    test('getCaregiverLinkedPatientUserIds dedupes and coerces ids', () async {
      route = (r) => http.Response(
            jsonEncode([
              {
                'link': {'patientUserId': 5},
              },
              {
                'link': {'patientUserId': '6'},
              },
              {
                'link': {'patientUserId': 5},
              },
              {
                'link': {'patientUserId': 'abc'},
              },
              {'link': 'nope'},
              'junk',
            ]),
            200,
          );
      final ids = await ApiService.getCaregiverLinkedPatientUserIds(3);
      expect(ids, [5, 6]);
      expect(last().url.path, endsWith('/caregivers/3/patients'));
      expect(last().headers['Authorization'], 'Bearer tok-xyz');
    });

    test('getCaregiverLinkedPatientUserIds returns [] on non-200', () async {
      route = (r) => http.Response('[]', 500);
      expect(await ApiService.getCaregiverLinkedPatientUserIds(3), isEmpty);
    });

    test('getCaregiverLinkedPatientUserIds returns [] for non-list JSON',
        () async {
      route = (r) => http.Response('{"a":1}', 200);
      expect(await ApiService.getCaregiverLinkedPatientUserIds(3), isEmpty);
    });

    test('getCaregiverLinkedPatientUserIds returns [] on malformed JSON',
        () async {
      route = (r) => http.Response('<html>', 200);
      expect(await ApiService.getCaregiverLinkedPatientUserIds(3), isEmpty);
    });

    test('getPatientLinkedCaregiverUserIds dedupes and coerces ids', () async {
      route = (r) => http.Response(
            jsonEncode([
              {'caregiverUserId': 9},
              {'caregiverUserId': '10'},
              {'caregiverUserId': 9},
              {'caregiverUserId': null},
              42,
            ]),
            200,
          );
      final ids = await ApiService.getPatientLinkedCaregiverUserIds(77);
      expect(ids, [9, 10]);
      expect(last().url.path,
          endsWith('/caregiver-patient-links/patients/77/caregivers'));
    });

    test(
        'getPatientLinkedCaregiverUserIds returns [] on error, non-list, throw',
        () async {
      route = (r) => http.Response('[]', 404);
      expect(await ApiService.getPatientLinkedCaregiverUserIds(1), isEmpty);
      route = (r) => http.Response('{}', 200);
      expect(await ApiService.getPatientLinkedCaregiverUserIds(1), isEmpty);
      route = (r) => throw const SocketException('down');
      expect(await ApiService.getPatientLinkedCaregiverUserIds(1), isEmpty);
    });

    test('getPatientLinkedCaregiverLinks keeps only map entries', () async {
      route = (r) => http.Response(
            jsonEncode([
              {'id': 1, 'caregiverUserId': 2},
              'skip',
              {'id': 3},
            ]),
            200,
          );
      final links = await ApiService.getPatientLinkedCaregiverLinks(8);
      expect(links, [
        {'id': 1, 'caregiverUserId': 2},
        {'id': 3},
      ]);
    });

    test('getPatientLinkedCaregiverLinks returns [] on error, non-list, throw',
        () async {
      route = (r) => http.Response('[]', 403);
      expect(await ApiService.getPatientLinkedCaregiverLinks(1), isEmpty);
      route = (r) => http.Response('"str"', 200);
      expect(await ApiService.getPatientLinkedCaregiverLinks(1), isEmpty);
      route = (r) => throw const SocketException('down');
      expect(await ApiService.getPatientLinkedCaregiverLinks(1), isEmpty);
    });
  });

  group('canInitiateVideoCall', () {
    test('never calls yourself and makes no request', () async {
      final ok = await ApiService.canInitiateVideoCall(
        currentUserId: 4,
        currentUserRole: 'PATIENT',
        targetUserId: 4,
      );
      expect(ok, isFalse);
      expect(requests, isEmpty);
    });

    test('patient may call a linked caregiver only', () async {
      route = (r) => http.Response(
            jsonEncode([
              {'caregiverUserId': 20},
            ]),
            200,
          );
      expect(
        await ApiService.canInitiateVideoCall(
          currentUserId: 1,
          currentUserRole: 'PATIENT',
          targetUserId: 20,
        ),
        isTrue,
      );
      expect(
        await ApiService.canInitiateVideoCall(
          currentUserId: 1,
          currentUserRole: 'PATIENT',
          targetUserId: 21,
        ),
        isFalse,
      );
    });

    test('caregiver without a caregiverId cannot call', () async {
      expect(
        await ApiService.canInitiateVideoCall(
          currentUserId: 1,
          currentUserRole: 'CAREGIVER',
          targetUserId: 2,
        ),
        isFalse,
      );
      expect(requests, isEmpty);
    });

    test('caregiver may call a linked patient directly', () async {
      route = (r) => http.Response(
            jsonEncode([
              {
                'link': {'patientUserId': 50},
              },
            ]),
            200,
          );
      expect(
        await ApiService.canInitiateVideoCall(
          currentUserId: 1,
          currentUserRole: 'CAREGIVER',
          targetUserId: 50,
          caregiverId: 9,
        ),
        isTrue,
      );
      expect(requests, hasLength(1));
    });

    test('caregiver may call another caregiver sharing a patient', () async {
      route = (r) {
        if (r.url.path.endsWith('/caregivers/9/patients')) {
          return http.Response(
            jsonEncode([
              {
                'link': {'patientUserId': 50},
              },
            ]),
            200,
          );
        }
        return http.Response(
          jsonEncode([
            {'caregiverUserId': 77},
          ]),
          200,
        );
      };
      expect(
        await ApiService.canInitiateVideoCall(
          currentUserId: 1,
          currentUserRole: 'CAREGIVER',
          targetUserId: 77,
          caregiverId: 9,
        ),
        isTrue,
      );
      expect(
        await ApiService.canInitiateVideoCall(
          currentUserId: 1,
          currentUserRole: 'CAREGIVER',
          targetUserId: 78,
          caregiverId: 9,
        ),
        isFalse,
      );
    });

    test('other roles cannot call', () async {
      expect(
        await ApiService.canInitiateVideoCall(
          currentUserId: 1,
          currentUserRole: 'ADMIN',
          targetUserId: 2,
        ),
        isFalse,
      );
    });
  });

  group('link permission toggles', () {
    test('video calls toggle posts enabled flag and reports success', () async {
      final ok = await ApiService.setPatientVideoCallsEnabledForLink(
          linkId: 12, enabled: true);
      expect(ok, isTrue);
      expect(last().method, 'POST');
      expect(last().url.path,
          endsWith('/caregiver-patient-links/12/patient-video-calls'));
      expect(jsonDecode(last().body), {'enabled': true});
    });

    test('video calls toggle is false on non-200 and on exception', () async {
      route = (r) => http.Response('', 500);
      expect(
        await ApiService.setPatientVideoCallsEnabledForLink(
            linkId: 1, enabled: false),
        isFalse,
      );
      route = (r) => throw Exception('x');
      expect(
        await ApiService.setPatientVideoCallsEnabledForLink(
            linkId: 1, enabled: false),
        isFalse,
      );
    });

    test('messaging toggle posts enabled flag and reports success', () async {
      final ok = await ApiService.setPatientMessagingEnabledForLink(
          linkId: 13, enabled: false);
      expect(ok, isTrue);
      expect(last().url.path,
          endsWith('/caregiver-patient-links/13/patient-messaging'));
      expect(jsonDecode(last().body), {'enabled': false});
    });

    test('messaging toggle is false on non-200 and on exception', () async {
      route = (r) => http.Response('', 403);
      expect(
        await ApiService.setPatientMessagingEnabledForLink(
            linkId: 1, enabled: true),
        isFalse,
      );
      route = (r) => throw Exception('x');
      expect(
        await ApiService.setPatientMessagingEnabledForLink(
            linkId: 1, enabled: true),
        isFalse,
      );
    });
  });

  group('subscriptions', () {
    test('getCurrentSubscription uses the session user id', () async {
      signIn(session: {'id': 31});
      await ApiService.getCurrentSubscription();
      expect(last().url.path, endsWith('/subscriptions/user/31/active'));
    });

    test('getCurrentSubscription throws when nobody is logged in', () async {
      await expectLater(
        ApiService.getCurrentSubscription(),
        throwsA(predicate((e) => '$e'.contains('User ID not found'))),
      );
      expect(requests, isEmpty);
    });

    test('getAvailablePlans GETs the plans endpoint', () async {
      await ApiService.getAvailablePlans();
      expect(last().method, 'GET');
      expect(last().url.path, endsWith('/subscriptions/plans'));
    });

    test('createSubscription sends form-encoded customer and price', () async {
      await ApiService.createSubscription('cus_1', 'price_9');
      expect(last().url.path, endsWith('/subscriptions/create-direct'));
      expect(last().headers['Content-Type'], startsWith('application/x-www'));
      expect(last().bodyFields, {'customerId': 'cus_1', 'priceId': 'price_9'});
    });

    test('createSubscriptionByUser sends form-encoded user and price',
        () async {
      await ApiService.createSubscriptionByUser('u5', 'price_2');
      expect(last().url.path, endsWith('/subscriptions/create-by-user'));
      expect(last().bodyFields, {'userId': 'u5', 'priceId': 'price_2'});
    });
  });

  group('audit log, risks and profile', () {
    test('getAuditLog adds only the filters supplied', () async {
      await ApiService.getAuditLog(
        4,
        startDate: DateTime(2026, 1, 5),
        endDate: DateTime(2026, 12, 31),
        type: 'LOGIN',
      );
      expect(last().url.path, endsWith('/clients/4/audit-log'));
      expect(last().url.queryParameters, {
        'startDate': '2026-01-05',
        'endDate': '2026-12-31',
        'type': 'LOGIN',
      });

      await ApiService.getAuditLog(4, type: '');
      expect(last().url.hasQuery, isFalse);
    });

    test('updatePatientProfile PUTs the JSON profile', () async {
      await ApiService.updatePatientProfile(8, {'name': 'Ann'});
      expect(last().method, 'PUT');
      expect(last().url.path, endsWith('/patients/8/profile'));
      expect(jsonDecode(last().body), {'name': 'Ann'});
    });

    test('risk endpoints use the expected verbs and bodies', () async {
      await ApiService.getRiskTypes();
      expect(last().url.path, endsWith('/risk-types'));

      await ApiService.getPatientRisks(8);
      expect(last().method, 'GET');
      expect(last().url.path, endsWith('/patients/8/risks'));

      await ApiService.flagPatientRisk(8, 3);
      expect(last().method, 'POST');
      expect(jsonDecode(last().body), {'riskTypeId': 3});

      await ApiService.unflagPatientRisk(8, 11);
      expect(last().method, 'DELETE');
      expect(last().url.path, endsWith('/patients/8/risks/11'));
    });
  });

  group('resolveImageUrl', () {
    test('returns null for null or blank input', () {
      expect(ApiService.resolveImageUrl(null), isNull);
      expect(ApiService.resolveImageUrl('   '), isNull);
    });

    test('keeps absolute http(s) URLs trimmed', () {
      expect(ApiService.resolveImageUrl(' https://x.test/a.png '),
          'https://x.test/a.png');
      expect(ApiService.resolveImageUrl('http://x.test/a.png'),
          'http://x.test/a.png');
    });

    test('prefixes relative paths with the backend base exactly once', () {
      final a = ApiService.resolveImageUrl('/img/a.png')!;
      final b = ApiService.resolveImageUrl('img/a.png')!;
      expect(a, endsWith('/img/a.png'));
      expect(a, b);
      expect(a.contains('//img'), isFalse);
    });
  });

  group('client activities', () {
    test('read endpoints build the right URLs', () async {
      await ApiService.getClientActivities(6);
      expect(last().url.path, endsWith('/clients/6/activities'));

      await ApiService.getActivities();
      expect(last().url.path, endsWith('/activities'));
      expect(last().url.hasQuery, isFalse);

      await ApiService.getActivities(category: 'ADL');
      expect(last().url.queryParameters, {'category': 'ADL'});

      await ApiService.getCompetencyScale();
      expect(last().url.path, endsWith('/config/competency-scale'));
    });

    test('putClientActivityConfig PUTs isEnabled', () async {
      await ApiService.putClientActivityConfig(6, 2, isEnabled: false);
      expect(last().method, 'PUT');
      expect(last().url.path, endsWith('/clients/6/activity-config/2'));
      expect(jsonDecode(last().body), {'isEnabled': false});
    });

    test('postActivityLog sends only provided optional fields, trimmed',
        () async {
      await ApiService.postActivityLog(
        clientId: 1,
        activityId: 2,
        competencyScore: 3,
      );
      expect(jsonDecode(last().body),
          {'clientId': 1, 'activityId': 2, 'competencyScore': 3});

      await ApiService.postActivityLog(
        clientId: 1,
        activityId: 2,
        competencyScore: 3,
        satisfactionRating: 4,
        notes: '  steady  ',
        activityName: ' Dress ',
      );
      expect(jsonDecode(last().body), {
        'clientId': 1,
        'activityId': 2,
        'competencyScore': 3,
        'satisfactionRating': 4,
        'notes': 'steady',
        'activityName': 'Dress',
      });

      await ApiService.postActivityLog(
        clientId: 1,
        activityId: 2,
        competencyScore: 3,
        notes: '   ',
        activityName: '',
      );
      expect(jsonDecode(last().body).containsKey('notes'), isFalse);
      expect(jsonDecode(last().body).containsKey('activityName'), isFalse);
    });

    test('getActivityLogs passes clientId and default/explicit limit',
        () async {
      await ApiService.getActivityLogs(9);
      expect(last().url.queryParameters, {'clientId': '9', 'limit': '100'});
      await ApiService.getActivityLogs(9, limit: 5);
      expect(last().url.queryParameters['limit'], '5');
    });

    test('behavioral incident omits blank trigger notes', () async {
      final when = DateTime.utc(2026, 3, 4, 5, 6);
      await ApiService.postBehavioralIncident(
        clientId: 2,
        observedBehavior: 'shouting',
        occurredAt: when,
        triggerNotes: '  ',
      );
      expect(last().url.path, endsWith('/clients/2/behavioral-incidents'));
      expect(jsonDecode(last().body), {
        'observed_behavior': 'shouting',
        'occurred_at': when.toIso8601String(),
      });

      await ApiService.postBehavioralIncident(
        clientId: 2,
        observedBehavior: 'shouting',
        occurredAt: when,
        triggerNotes: ' loud noise ',
      );
      expect(jsonDecode(last().body)['trigger_notes'], 'loud noise');

      await ApiService.getBehavioralIncidents(2);
      expect(last().method, 'GET');
    });

    test('postClientEvent sends the activity id', () async {
      await ApiService.postClientEvent(clientId: 2, activityId: 8);
      expect(last().url.path, endsWith('/clients/2/events'));
      expect(jsonDecode(last().body), {'activity_id': 8});
    });

    test('incident reports: create, list and fetch one', () async {
      final when = DateTime.utc(2026, 1, 2);
      await ApiService.postIncidentReport(
        clientId: 3,
        incidentType: 'FALL',
        occurredAt: when,
        location: 'kitchen',
        triggerNotes: ' wet floor ',
        actionsTaken: const ['ice', 'call'],
        outcome: 'ok',
      );
      expect(last().url.path, endsWith('/clients/3/incident-reports'));
      expect(jsonDecode(last().body), {
        'incident_type': 'FALL',
        'occurred_at': when.toIso8601String(),
        'location': 'kitchen',
        'outcome': 'ok',
        'actions_taken': ['ice', 'call'],
        'trigger_notes': 'wet floor',
      });

      await ApiService.postIncidentReport(
        clientId: 3,
        incidentType: 'FALL',
        occurredAt: when,
        location: 'kitchen',
        actionsTaken: const [],
        outcome: 'ok',
      );
      expect(jsonDecode(last().body).containsKey('trigger_notes'), isFalse);

      await ApiService.getIncidentReports(3);
      expect(last().url.path, endsWith('/clients/3/incident-reports'));
      await ApiService.getIncidentReport(3, 44);
      expect(last().url.path, endsWith('/clients/3/incident-reports/44'));
    });

    test('report endpoints format optional date ranges', () async {
      final start = DateTime(2026, 2, 3);
      final end = DateTime(2026, 11, 20);
      final calls = <String,
          Future<http.Response> Function(int,
              {DateTime? startDate, DateTime? endDate})>{
        'competency-trends': ApiService.getCompetencyTrends,
        'behavioral-trends': ApiService.getBehavioralTrends,
        'participation': ApiService.getParticipation,
      };
      for (final entry in calls.entries) {
        await entry.value(5, startDate: start, endDate: end);
        expect(last().url.path, endsWith('/clients/5/reports/${entry.key}'));
        expect(last().url.queryParameters,
            {'startDate': '2026-02-03', 'endDate': '2026-11-20'});

        await entry.value(5);
        expect(last().url.hasQuery, isFalse);
      }
    });
  });

  group('multipart uploads (via HttpOverrides)', () {
    late Directory dir;
    late File file;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('api_service_gap');
      file = File('${dir.path}${Platform.pathSeparator}pic.png');
      await file.writeAsBytes([1, 2, 3, 4]);
    });

    tearDown(() async {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    });

    test('createPost posts without an image', () async {
      rawRoute = (m, u) => FakeResponse(201, '{"id":1}');
      final r = await ApiService.createPost(7, 'hello');
      expect(r.statusCode, 201);
      expect(rawRequests.single, 'POST /v1/api/feed/create');
    });

    test('createPost posts with an image', () async {
      rawRoute = (m, u) => FakeResponse(201, '{"id":2}');
      final r = await ApiService.createPost(7, 'hello', file);
      expect(r.statusCode, 201);
      expect(r.body, '{"id":2}');
      expect(rawRequests.single, 'POST /v1/api/feed/create');
    });

    test('uploadUserFile posts to the user upload endpoint', () async {
      rawRoute = (m, u) => FakeResponse(200, '{"fileUrl":"/f/1"}');
      final r = await ApiService.uploadUserFile(
        userId: 12,
        file: file,
        category: 'profilePicture',
      );
      expect(r.statusCode, 200);
      expect(rawRequests.single, 'POST /v1/api/files/users/12/upload');
    });

    test('postClientActivityIcon posts the icon file', () async {
      rawRoute = (m, u) => FakeResponse(200, '{}');
      final r = await ApiService.postClientActivityIcon(3, 4, file);
      expect(r.statusCode, 200);
      expect(
          rawRequests.single, 'POST /v1/api/clients/3/activity-config/4/icon');
    });
  });

  group('getUserProfilePictureUrl', () {
    test('returns the first fileUrl from a list', () async {
      route = (r) => http.Response(
            jsonEncode([
              {'fileUrl': '/a.png'},
              {'fileUrl': '/b.png'},
            ]),
            200,
          );
      expect(await ApiService.getUserProfilePictureUrl(4), '/a.png');
      expect(last().url.path, endsWith('/files/users/4'));
      expect(last().url.queryParameters, {'category': 'profilePicture'});
    });

    test('returns fileUrl from a map body', () async {
      route = (r) => http.Response('{"fileUrl":"/m.png"}', 200);
      expect(await ApiService.getUserProfilePictureUrl(4, 'PATIENT'), '/m.png');
    });

    test('returns null for empty list, unknown map, non-200 and errors',
        () async {
      route = (r) => http.Response('[]', 200);
      expect(await ApiService.getUserProfilePictureUrl(4), isNull);
      route = (r) => http.Response('{"x":1}', 200);
      expect(await ApiService.getUserProfilePictureUrl(4), isNull);
      route = (r) => http.Response('[]', 404);
      expect(await ApiService.getUserProfilePictureUrl(4), isNull);
      route = (r) => throw Exception('boom');
      expect(await ApiService.getUserProfilePictureUrl(4), isNull);
    });
  });
}
