// Tests for CheckinService.
//
// Coverage strategy:
//   CheckinService has two public static methods — addCheckin() and
//   getCheckinCount() — that each issue a single HTTP request.  No auth
//   headers or storage are involved, so the tests only need an http.MockClient
//   supplied via http.runWithClient().
//
//   Every status-code branch is exercised, the outgoing request shape is
//   asserted, and the body/query-parameter mappings are verified.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:care_connect_app/services/checkin_service.dart';

void main() {
  // ─── addCheckin ───────────────────────────────────────────────────────────

  group('CheckinService.addCheckin()', () {
    Future<bool> _runAddCheckinWithClient(
      Future<http.Response> Function(http.Request req) handler, {
      String patientId = '101',
      String caregiverId = 'caregiver-1',
    }) {
      return http.runWithClient(
        () => CheckinService.addCheckin(patientId, caregiverId),
        () => MockClient(handler),
      );
    }

    test('returns true when server responds with 201 Created', () async {
      // Verifies the primary success path after question IDs are resolved.
      final result = await _runAddCheckinWithClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/api/questions')) {
          return http.Response(
              jsonEncode([
                {'id': 1},
                {'id': 2}
              ]),
              200);
        }
        if (req.method == 'POST' && req.url.path.endsWith('/api/checkins')) {
          return http.Response('', 201);
        }
        return http.Response('Unexpected request', 500);
      });
      expect(result, isTrue);
    });

    test('returns true when server responds with 200 OK', () async {
      // Some backends return 200 instead of 201 on creation; both are accepted.
      final result = await _runAddCheckinWithClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/api/questions')) {
          return http.Response(
              jsonEncode([
                {'id': 11}
              ]),
              200);
        }
        if (req.method == 'POST' && req.url.path.endsWith('/api/checkins')) {
          return http.Response('', 200);
        }
        return http.Response('Unexpected request', 500);
      });
      expect(result, isTrue);
    });

    test('returns false when server responds with 400', () async {
      // Any status other than 200/201 must be treated as failure.
      final result = await _runAddCheckinWithClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/api/questions')) {
          return http.Response(
              jsonEncode([
                {'id': 7}
              ]),
              200);
        }
        if (req.method == 'POST' && req.url.path.endsWith('/api/checkins')) {
          return http.Response('Bad Request', 400);
        }
        return http.Response('Unexpected request', 500);
      });
      expect(result, isFalse);
    });

    test('returns false when server responds with 500', () async {
      // Server-side errors must propagate as a false result.
      final result = await _runAddCheckinWithClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/api/questions')) {
          return http.Response(
              jsonEncode([
                {'id': 8}
              ]),
              200);
        }
        if (req.method == 'POST' && req.url.path.endsWith('/api/checkins')) {
          return http.Response('Server Error', 500);
        }
        return http.Response('Unexpected request', 500);
      });
      expect(result, isFalse);
    });

    test('returns false when question lookup fails', () async {
      // If active question IDs cannot be resolved, check-in creation is skipped.
      final result = await _runAddCheckinWithClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/api/questions')) {
          return http.Response('Not Found', 404);
        }
        return http.Response('Unexpected request', 500);
      });
      expect(result, isFalse);
    });

    test('returns false when active questions list is empty', () async {
      final result = await _runAddCheckinWithClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/api/questions')) {
          return http.Response(jsonEncode([]), 200);
        }
        return http.Response('Unexpected request', 500);
      });
      expect(result, isFalse);
    });

    test('returns false for invalid patient id before making requests',
        () async {
      var requestCount = 0;
      final result = await _runAddCheckinWithClient((_) async {
        requestCount++;
        return http.Response('', 500);
      }, patientId: 'patient-abc');
      expect(result, isFalse);
      expect(requestCount, 0);
    });

    test('does not require caregiver id for snapshot create flow',
        () async {
      final result = await _runAddCheckinWithClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/api/questions')) {
          return http.Response(
              jsonEncode([
                {'id': 99}
              ]),
              200);
        }
        if (req.method == 'POST' && req.url.path.endsWith('/api/checkins')) {
          return http.Response('', 201);
        }
        return http.Response('Unexpected request', 500);
      }, caregiverId: '');
      expect(result, isTrue);
    });

    test('fetches active questions then posts check-in', () async {
      final requests = <http.Request>[];
      await _runAddCheckinWithClient((req) async {
        requests.add(req);
        if (req.method == 'GET' && req.url.path.endsWith('/api/questions')) {
          return http.Response(
              jsonEncode([
                {'id': '21'},
                {'id': 22}
              ]),
              200);
        }
        if (req.method == 'POST' && req.url.path.endsWith('/api/checkins')) {
          return http.Response('', 201);
        }
        return http.Response('Unexpected request', 500);
      });

      expect(requests, hasLength(2));
      expect(requests.first.method, 'GET');
      expect(requests.first.url.path, contains('/api/questions'));
      expect(requests.first.url.queryParameters['active'], 'true');
      expect(requests.last.method, 'POST');
      expect(requests.last.url.path, contains('/api/checkins'));
    });

    test('request body contains patientId and selectedQuestionIds', () async {
      http.Request? postRequest;
      await _runAddCheckinWithClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/api/questions')) {
          return http.Response(
              jsonEncode([
                {'id': 31},
                {'id': '32'}
              ]),
              200);
        }
        if (req.method == 'POST' && req.url.path.endsWith('/api/checkins')) {
          postRequest = req;
          return http.Response('', 201);
        }
        return http.Response('Unexpected request', 500);
      });

      final body = jsonDecode(postRequest!.body) as Map<String, dynamic>;
      expect(body['patientId'], 101);
      expect(body['selectedQuestionIds'], [31, 32]);
    });

    test('request body does not include legacy create fields', () async {
      http.Request? postRequest;
      await _runAddCheckinWithClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/api/questions')) {
          return http.Response(
              jsonEncode([
                {'id': 44}
              ]),
              200);
        }
        if (req.method == 'POST' && req.url.path.endsWith('/api/checkins')) {
          postRequest = req;
          return http.Response('', 201);
        }
        return http.Response('Unexpected request', 500);
      });

      final body = jsonDecode(postRequest!.body) as Map<String, dynamic>;
      expect(body.containsKey('caregiverId'), isFalse);
      expect(body.containsKey('timestamp'), isFalse);
      expect(body.containsKey('status'), isFalse);
    });

    test('request includes Content-Type: application/json header', () async {
      http.Request? postRequest;
      await _runAddCheckinWithClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/api/questions')) {
          return http.Response(
              jsonEncode([
                {'id': 55}
              ]),
              200);
        }
        if (req.method == 'POST' && req.url.path.endsWith('/api/checkins')) {
          postRequest = req;
          return http.Response('', 201);
        }
        return http.Response('Unexpected request', 500);
      });

      expect(
        postRequest!.headers['Content-Type'],
        contains('application/json'),
      );
    });
  });

  // ─── createCheckinWithSelectedQuestions ────────────────────────────────────

  group('CheckinService.createCheckinWithSelectedQuestions()', () {
    Future<int?> _runCreateWithClient(
      Future<http.Response> Function(http.Request req) handler, {
      String patientId = '101',
      List<int> selectedQuestionIds = const [1, 2],
    }) {
      return http.runWithClient(
        () => CheckinService.createCheckinWithSelectedQuestions(
          patientId: patientId,
          selectedQuestionIds: selectedQuestionIds,
        ),
        () => MockClient(handler),
      );
    }

    test('returns created checkInId from response body', () async {
      final result = await _runCreateWithClient((req) async {
        expect(req.method, 'POST');
        expect(req.url.path, contains('/api/checkins'));
        return http.Response(jsonEncode({'checkInId': 987}), 201);
      });

      expect(result, 987);
    });

    test('parses fallback id fields in response body', () async {
      final result = await _runCreateWithClient((_) async {
        return http.Response(jsonEncode({'id': '654'}), 200);
      });

      expect(result, 654);
    });

    test('returns null on non-success response status', () async {
      final result = await _runCreateWithClient((_) async {
        return http.Response('Bad Request', 400);
      });

      expect(result, isNull);
    });

    test('returns null when response body is empty', () async {
      final result = await _runCreateWithClient((_) async {
        return http.Response('', 201);
      });

      expect(result, isNull);
    });

    test('does not call backend for invalid input', () async {
      var requestCount = 0;
      final result = await _runCreateWithClient((_) async {
        requestCount++;
        return http.Response('', 500);
      }, patientId: 'not-an-int', selectedQuestionIds: const []);

      expect(result, isNull);
      expect(requestCount, 0);
    });
  });

  // ─── getCheckinCount ──────────────────────────────────────────────────────

  group('CheckinService.getCheckinCount()', () {
    test('returns the count from JSON body on HTTP 200', () async {
      // Verifies that the "count" field is extracted from the response and
      // returned as an integer.
      final result = await http.runWithClient(
        () => CheckinService.getCheckinCount('caregiver-1'),
        () => MockClient(
            (_) async => http.Response(jsonEncode({'count': 42}), 200)),
      );
      expect(result, 42);
    });

    test('returns 0 when count field is absent from response body', () async {
      // Verifies the null-coalescing default: missing "count" becomes 0.
      final result = await http.runWithClient(
        () => CheckinService.getCheckinCount('caregiver-2'),
        () => MockClient(
            (_) async => http.Response(jsonEncode({'other': 'field'}), 200)),
      );
      expect(result, 0);
    });

    test('returns 0 when count is explicitly null in response body', () async {
      // Verifies that an explicit null value also triggers the default of 0.
      final result = await http.runWithClient(
        () => CheckinService.getCheckinCount('caregiver-3'),
        () => MockClient(
            (_) async => http.Response(jsonEncode({'count': null}), 200)),
      );
      expect(result, 0);
    });

    test('returns 0 when server responds with 500', () async {
      // Verifies the fallback to 0 on any non-200 status.
      final result = await http.runWithClient(
        () => CheckinService.getCheckinCount('caregiver-4'),
        () => MockClient((_) async => http.Response('Error', 500)),
      );
      expect(result, 0);
    });

    test('returns 0 when server responds with 404', () async {
      // A 404 also returns 0 since only 200 is handled.
      final result = await http.runWithClient(
        () => CheckinService.getCheckinCount('caregiver-5'),
        () => MockClient((_) async => http.Response('Not Found', 404)),
      );
      expect(result, 0);
    });

    test('sends GET request to the count endpoint', () async {
      // Verifies the request method and path are correct.
      http.Request? captured;
      await http.runWithClient(
        () => CheckinService.getCheckinCount('cg-99'),
        () => MockClient((req) async {
          captured = req;
          return http.Response(jsonEncode({'count': 0}), 200);
        }),
      );
      expect(captured, isNotNull);
      expect(captured!.method, 'GET');
      expect(captured!.url.path, contains('count'));
    });

    test('includes caregiverId as a query parameter', () async {
      // The endpoint filters by caregiverId; it must be in the query string.
      http.Request? captured;
      await http.runWithClient(
        () => CheckinService.getCheckinCount('cg-77'),
        () => MockClient((req) async {
          captured = req;
          return http.Response(jsonEncode({'count': 5}), 200);
        }),
      );
      expect(captured!.url.queryParameters['caregiverId'], 'cg-77');
    });

    test('returns correct count of zero without mistaking for error', () async {
      // A legitimate count of 0 must not be confused with an error default.
      final result = await http.runWithClient(
        () => CheckinService.getCheckinCount('new-caregiver'),
        () => MockClient(
            (_) async => http.Response(jsonEncode({'count': 0}), 200)),
      );
      expect(result, 0);
    });
  });

  // ─── fetchCheckInsForPatient ──────────────────────────────────────────────

  group('CheckinService.fetchCheckInsForPatient()', () {
    test('returns parsed check-in summaries for patient', () async {
      final result = await http.runWithClient(
        () => CheckinService.fetchCheckInsForPatient('7'),
        () => MockClient((req) async {
          expect(req.method, 'GET');
          expect(req.url.path, contains('/api/checkins/patients/7'));
          return http.Response(
            jsonEncode([
              {
                'checkInId': 101,
                'patientId': 7,
                'createdAt': '2026-06-27T10:00:00Z',
                'submittedAt': null,
                'questionCount': 3,
              },
            ]),
            200,
          );
        }),
      );

      expect(result, hasLength(1));
      expect(result.first.checkInId, 101);
      expect(result.first.patientId, 7);
      expect(result.first.questionCount, 3);
    });

    test('returns empty list for invalid patient id', () async {
      var requestCount = 0;
      final result = await http.runWithClient(
        () => CheckinService.fetchCheckInsForPatient('patient-x'),
        () => MockClient((_) async {
          requestCount++;
          return http.Response('', 500);
        }),
      );

      expect(result, isEmpty);
      expect(requestCount, 0);
    });
  });
}
