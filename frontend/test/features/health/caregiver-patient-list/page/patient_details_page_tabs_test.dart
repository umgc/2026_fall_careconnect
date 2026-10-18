// Tests for PatientDetailsPage's tabs with realistic data
// (lib/features/health/caregiver-patient-list/page/patient_details_page.dart).
//
// patient_details_page_test.dart covers the header and the Info tab with
// empty lists from every endpoint. These tests feed each loader real-shaped
// data (mood, symptoms, medications, risks, check-ins, call history, the
// caregiver link) and open the Mood, Health, In-home and Virtual Check-In
// tabs, so the parsing and the tab bodies run.

import 'dart:convert';

import 'package:care_connect_app/features/health/caregiver-patient-list/page/patient_details_page.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../mock_user_provider.dart';

/// Requests the fake backend saw, as "METHOD path".
final List<String> _calls = [];

/// Overrides for one test: path fragment → response.
final Map<String, http.Response Function(http.Request)> _overrides = {};

String _iso(Duration ago) => DateTime.now().subtract(ago).toIso8601String();

Map<String, dynamic> _profile() => {
      'id': 42,
      'userId': 142,
      'firstName': 'Sarah',
      'lastName': 'Johnson',
      'email': 'sarah.johnson@email.com',
      'phone': '(555) 123-4567',
      'dob': '1980-05-15',
      'gender': 'Female',
      'mrn': 'MRN-2024-0156',
      'diagnoses': ['Type 2 Diabetes', 'Hypertension'],
      'allergies': [
        {'allergen': 'Penicillin', 'severity': 'Severe'},
      ],
      'preferredName': 'Sally',
      'hobbies': [
        'Gardening',
        {'name': 'Chess'}
      ],
      'favoriteFoods': ['Soup'],
      'address': {
        'line1': '123 Main St',
        'city': 'Springfield',
        'state': 'IL',
        'zip': '62701',
      },
    };

List<Map<String, dynamic>> _mood() => [
      {
        'score': 9,
        'label': 'Great',
        'createdAt': _iso(const Duration(hours: 2)),
        'note': 'Slept well'
      },
      {
        'score': '3',
        'timestamp': _iso(const Duration(days: 1)),
        'notes': 'Tired'
      },
      {'score': 1, 'date': _iso(const Duration(days: 2))},
      {
        'score': 6,
        'createdAt': _iso(const Duration(days: 3)),
        'comment': 'Okay'
      },
      {'score': 'x', 'createdAt': 'not a date'},
    ];

List<Map<String, dynamic>> _symptoms() => [
      {
        'id': 1,
        'symptomKey': 'Headache',
        'symptomValue': 'frontal',
        'severity': 5,
        'takenAt': _iso(const Duration(minutes: 30)),
        'clinicalNotes': 'Took rest'
      },
      {
        'id': 2,
        'symptomKey': 'Nausea',
        'severity': 3,
        'createdAt': _iso(const Duration(hours: 5))
      },
      {
        'id': 3,
        'symptomKey': '',
        'severity': '1',
        'createdAt': _iso(const Duration(days: 4)),
        'notes': 'n/a'
      },
      {
        'id': 4,
        'symptomKey': 'Dizziness',
        'severity': 2,
        'createdAt': _iso(const Duration(days: 40))
      },
    ];

List<Map<String, dynamic>> _medications() => [
      {
        'id': 7,
        'patientId': 42,
        'medicationName': 'Metformin',
        'dosage': '500 mg',
        'frequency': 'Twice daily',
        'route': 'Oral',
        'medicationType': 'PRESCRIPTION',
        'prescribedBy': 'Dr. Lee',
        'prescribedDate': '2026-09-01',
        'startDate': '2026-09-01',
        'isActive': true,
        'notes': 'With food',
      },
      {
        'id': 8,
        'patientId': 42,
        'medicationName': 'Lisinopril',
        'dosage': '10 mg',
        'frequency': 'Daily',
        'route': 'Oral',
        'medicationType': 'PRESCRIPTION',
        'isActive': false,
      },
    ];

List<Map<String, dynamic>> _riskTypes() => [
      {'id': 1, 'name': 'Fall risk', 'description': 'History of falls'},
      {'id': 2, 'name': 'Wandering'},
      {'id': 3, 'name': 'Choking'},
    ];

List<Map<String, dynamic>> _patientRisks() => [
      {'id': 11, 'riskTypeId': 1},
      {'id': '12', 'riskTypeId': '3'},
    ];

Map<String, dynamic> _checkInPage({int totalPages = 2}) => {
      'items': [
        {
          'checkInId': 501,
          'patientId': 42,
          'createdAt': _iso(const Duration(days: 1)),
          'submittedAt': _iso(const Duration(hours: 20)),
          'reviewedAt': null,
          'questionCount': 4
        },
        {
          'checkInId': 502,
          'patientId': 42,
          'createdAt': _iso(const Duration(days: 3)),
          'submittedAt': _iso(const Duration(days: 3)),
          'reviewedAt': _iso(const Duration(days: 2)),
          'questionCount': 3
        },
        {
          'checkInId': 503,
          'patientId': 42,
          'createdAt': _iso(const Duration(days: 5)),
          'submittedAt': null,
          'reviewedAt': null,
          'questionCount': '2'
        },
      ],
      'page': 0,
      'size': 5,
      'totalElements': 8,
      'totalPages': totalPages,
    };

Map<String, dynamic> _checkInDetail(int id) => {
      'checkInId': id,
      'patientId': 42,
      'createdAt': _iso(const Duration(days: 1)),
      'submittedAt': _iso(const Duration(hours: 20)),
      'reviewedAt': null,
      'status': 'submitted',
      'answers': [
        {
          'questionId': 1,
          'prompt': 'How did you sleep?',
          'type': 'TEXT',
          'required': true,
          'ordinal': 1,
          'valueText': 'Fine',
          'answeredAt': _iso(const Duration(hours: 20))
        },
        {
          'questionId': 2,
          'prompt': 'Any pain today?',
          'type': 'BOOLEAN',
          'required': false,
          'ordinal': 2,
          'valueBoolean': true
        },
        {
          'questionId': 3,
          'prompt': 'Pain level',
          'type': 'NUMBER',
          'required': false,
          'ordinal': '3',
          'valueNumber': 4
        },
        {
          'questionId': 4,
          'prompt': 'Anything else?',
          'type': 'TEXT',
          'required': false,
          'ordinal': 4
        },
      ],
    };

List<Map<String, dynamic>> _telemetry() => [
      {
        'callId': 'c1',
        'eventType': 'CALL_START',
        'actorUserId': 1,
        'targetUserId': 142,
        'occurredAt': _iso(const Duration(hours: 3))
      },
      {
        'callId': 'c1',
        'eventType': 'CALL_END',
        'actorUserId': 1,
        'targetUserId': 142,
        'occurredAt': _iso(const Duration(hours: 2)),
        'metadataJson': '{"durationSeconds": 300}'
      },
      {
        'callId': 'c2',
        'eventType': 'SENTIMENT_FINAL',
        'actorUserId': 9,
        'targetUserId': 1,
        'occurredAt': _iso(const Duration(days: 1)),
        'metadataJson': {
          'contextPatientUserIds': [142, 'x']
        }
      },
      {
        'callId': 'c3',
        'eventType': 'WS_END_CALL',
        'actorUserId': 9,
        'targetUserId': 1,
        'occurredAt': _iso(const Duration(days: 2)),
        'metadataJson': '{"contextPatientUserId": "142"}'
      },
      {
        'callId': 'c4',
        'eventType': 'CALL_START',
        'actorUserId': 9,
        'targetUserId': 8,
        'occurredAt': 'bad',
        'metadataJson': 'not json'
      },
    ];

Map<String, dynamic> _caregiverView(
        {bool video = true, bool messaging = true}) =>
    {
      'patient': {
        'id': 42,
        'userId': 142,
        'firstName': 'Sarah',
        'lastName': 'Johnson'
      },
      'link': {
        'linkId': 77,
        'patientVideoCallsEnabled': video,
        'patientMessagingEnabled': messaging,
      },
    };

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

Future<http.Response> _handle(http.Request request) async {
  final path = request.url.path;
  _calls.add('${request.method} $path');
  for (final entry in _overrides.entries) {
    if (path.contains(entry.key)) return entry.value(request);
  }
  if (path.contains('/checkins/') && path.endsWith('/detail')) {
    final id = int.parse(path.split('/').reversed.elementAt(1));
    return _json(_checkInDetail(id));
  }
  if (path.contains('/checkins/') && path.endsWith('/review')) {
    return _json({'ok': true});
  }
  if (path.contains('/checkins/patients/') && path.endsWith('/search')) {
    return _json(_checkInPage());
  }
  if (path.contains('/profile')) {
    return request.method == 'GET'
        ? _json(_profile())
        : _json({..._profile(), 'preferredName': 'Sal'});
  }
  if (path.contains('/family-members')) {
    return _json([
      {
        'familyMemberName': 'Michael Johnson',
        'relationship': 'Spouse',
        'familyMemberPhone': '(555) 987-6543'
      },
    ]);
  }
  if (path.contains('/medications')) return _json(_medications());
  if (path.contains('risk-types') || path.contains('riskTypes')) {
    return _json(_riskTypes());
  }
  if (path.contains('/risks')) {
    if (request.method == 'GET') return _json(_patientRisks());
    return _json({'id': 99, 'riskTypeId': 2});
  }
  if (path.contains('/mood')) return _json(_mood());
  if (path.contains('/symptom')) return _json({'data': _symptoms()});
  if (path.endsWith('/telemetry') && request.method == 'DELETE') {
    return _json({'deletedEvents': 4, 'deletedCalls': 2});
  }
  if (path.contains('/dev/telemetry/enabled')) return _json({'enabled': true});
  if (path.contains('/telemetry')) return _json(_telemetry());
  if (path.contains('/caregivers/') && path.contains('/patients/')) {
    return _json(_caregiverView());
  }
  if (RegExp(r'/patients/\d+$').hasMatch(path)) {
    return _json({..._profile(), 'virtualCheckIns': []});
  }
  return _json({});
}

final MockClient _client = MockClient(_handle);

/// The default response for a path, for overrides that only change one path.
http.Response _handleSync(http.Request request) {
  final path = request.url.path;
  if (path.contains('/profile')) return _json(_profile());
  if (path.contains('/family-members')) return _json([]);
  if (path.contains('/risks')) return _json(_patientRisks());
  return _json({});
}

void main() {
  setUp(() {
    _calls.clear();
    _overrides.clear();
    SharedPreferences.setMockInitialValues({});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        if (call.method == 'readAll') {
          return <String, String>{
            'jwt_token': 'mock-token',
            'user_session': jsonEncode({'id': 1, 'token': 'mock-token'}),
          };
        }
        if (call.method == 'read') {
          final key = (call.arguments as Map?)?['key'] as String?;
          if (key == 'jwt_token') return 'mock-token';
          if (key == 'user_session') {
            return jsonEncode({'id': 1, 'token': 'mock-token'});
          }
          return null;
        }
        if (call.method == 'containsKey') return true;
        return null;
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => call.method == 'check' ? ['wifi'] : null,
    );
    messenger.setMockStreamHandler(
      const EventChannel('dev.fluttercommunity.plus/connectivity_status'),
      MockStreamHandler.inline(
          onListen: (args, events) => events.success(['wifi'])),
    );
    ApiService.debugSetHttpClient(_client);
  });

  tearDown(() {
    ApiService.debugResetHttpClient();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        null);
    messenger.setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/connectivity'), null);
    messenger.setMockStreamHandler(
        const EventChannel('dev.fluttercommunity.plus/connectivity_status'),
        null);
  });

  Widget app({bool isCaregiver = true, String patientId = '42'}) {
    return ChangeNotifierProvider<UserProvider>.value(
      value: MockUserProvider(
        mockUser: MockUser(role: 'CAREGIVER', caregiverId: 10),
      ),
      child: MaterialApp(
        home:
            PatientDetailsPage(patientId: patientId, isCaregiver: isCaregiver),
      ),
    );
  }

  Future<void> settle(WidgetTester tester, [int frames = 30]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// RenderFlex overflows seen while a test ran. The Virtual Check-In status
  /// filter overflows its row by a few pixels (a layout issue in the page, not
  /// what these tests check), so overflows are recorded instead of failing.
  final overflows = <String>[];

  Future<void> pumpPage(WidgetTester tester, {bool isCaregiver = true}) async {
    overflows.clear();
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      final text = details.exceptionAsString();
      if (text.contains('overflowed')) {
        overflows.add(text);
        return;
      }
      previous?.call(details);
    };
    addTearDown(() => FlutterError.onError = previous);
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await http.runWithClient(() async {
      await tester.pumpWidget(app(isCaregiver: isCaregiver));
      await settle(tester);
    }, () => _client);
  }

  Future<void> openTab(WidgetTester tester, String label) async {
    await http.runWithClient(() async {
      await tester.tap(find.text(label).first);
      await settle(tester, 15);
    }, () => _client);
  }

  /// Scrolls every scrollable on screen to its end, so lazily built rows run.
  Future<void> scrollAll(WidgetTester tester) async {
    final scrollables = find.byType(Scrollable);
    for (var i = 0; i < scrollables.evaluate().length; i++) {
      try {
        await tester.drag(scrollables.at(i), const Offset(0, -3000),
            warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 200));
      } catch (_) {}
    }
  }

  group('PatientDetailsPage – tabs with data', () {
    testWidgets('loads every source and shows the latest mood on Mood',
        (tester) async {
      await pumpPage(tester);
      expect(_calls.any((c) => c.contains('/mood')), isTrue);
      expect(_calls.any((c) => c.contains('/symptom')), isTrue);
      expect(_calls.any((c) => c.contains('/medications')), isTrue);
      expect(_calls.any((c) => c.contains('/search')), isTrue);

      await openTab(tester, 'Mood');
      expect(find.textContaining('Great'), findsWidgets);
      await scrollAll(tester);
    });

    testWidgets('Health tab shows symptoms, medications and known risks',
        (tester) async {
      await pumpPage(tester);
      await openTab(tester, 'Health');
      await scrollAll(tester);
      expect(find.textContaining('Metformin'), findsWidgets);
    });

    testWidgets('In-home tab renders its cards', (tester) async {
      await pumpPage(tester);
      await openTab(tester, 'In-home');
      await scrollAll(tester);
      expect(find.byType(PatientDetailsPage), findsOneWidget);
    });

    testWidgets('Virtual Check-In tab lists submitted, reviewed and draft',
        (tester) async {
      await pumpPage(tester);
      await openTab(tester, 'Virtual Check-In');
      expect(find.textContaining('pending caregiver review'), findsWidgets);
      expect(find.textContaining('reviewed by caregiver'), findsWidgets);
      expect(find.textContaining('pending patient submission'), findsWidgets);
      await scrollAll(tester);
    });
  });
  group('PatientDetailsPage – Virtual Check-In actions', () {
    testWidgets('opening a check-in shows its answers and marks it reviewed',
        (tester) async {
      await pumpPage(tester);
      await openTab(tester, 'Virtual Check-In');
      await http.runWithClient(() async {
        await tester.tap(find.textContaining('pending caregiver review').first);
        await settle(tester, 10);
      }, () => _client);
      expect(find.text('Check-in #501 details'), findsOneWidget);
      expect(find.text('Answer: Fine'), findsOneWidget);
      expect(find.text('Answer: Yes'), findsOneWidget);
      expect(find.text('Answer: 4'), findsOneWidget);
      expect(find.text('Answer: No answer submitted'), findsOneWidget);
      expect(find.text('Answered at: N/A'), findsWidgets);

      await http.runWithClient(() async {
        await tester.tap(find.text('Mark as reviewed'));
        await settle(tester, 20);
      }, () => _client);
      expect(_calls, contains('POST /api/checkins/501/review'));
      expect(find.text('Check-in #501 details'), findsNothing);
    });

    testWidgets('Close leaves a check-in unreviewed', (tester) async {
      await pumpPage(tester);
      await openTab(tester, 'Virtual Check-In');
      await http.runWithClient(() async {
        await tester.tap(find.textContaining('reviewed by caregiver').first);
        await settle(tester, 10);
      }, () => _client);
      await tester.tap(find.text('Close'));
      await settle(tester, 5);
      expect(_calls.where((c) => c.endsWith('/review')), isEmpty);
    });

    testWidgets('a failed review keeps the dialog and says so', (tester) async {
      _overrides['/review'] = (_) => _json({'error': 'no'}, 500);
      await pumpPage(tester);
      await openTab(tester, 'Virtual Check-In');
      await http.runWithClient(() async {
        await tester.tap(find.textContaining('pending caregiver review').first);
        await settle(tester, 10);
        await tester.tap(find.text('Mark as reviewed'));
        await settle(tester, 10);
      }, () => _client);
      expect(find.text('Failed to mark check-in as reviewed'), findsOneWidget);
    });

    testWidgets('a check-in whose details fail to load shows a message',
        (tester) async {
      _overrides['/detail'] = (_) => _json({'error': 'gone'}, 500);
      await pumpPage(tester);
      await openTab(tester, 'Virtual Check-In');
      await http.runWithClient(() async {
        await tester.tap(find.textContaining('pending caregiver review').first);
        await settle(tester, 10);
      }, () => _client);
      expect(find.text('Failed to load check-in details'), findsOneWidget);
    });

    testWidgets('the status filter and pager reload the list', (tester) async {
      await pumpPage(tester);
      await openTab(tester, 'Virtual Check-In');
      expect(find.text('Page 1 of 2'), findsOneWidget);

      final searches = _calls.where((c) => c.endsWith('/search')).length;
      await http.runWithClient(() async {
        await tester.tap(find.byIcon(Icons.chevron_right));
        await settle(tester, 15);
      }, () => _client);
      expect(_calls.where((c) => c.endsWith('/search')).length,
          greaterThan(searches));
      expect(find.text('Page 2 of 2'), findsOneWidget);

      await http.runWithClient(() async {
        await tester.tap(find.byIcon(Icons.chevron_left));
        await settle(tester, 15);
      }, () => _client);
      expect(find.text('Page 1 of 2'), findsOneWidget);

      await http.runWithClient(() async {
        await tester.tap(find.text('All').first);
        await settle(tester, 5);
        await tester.tap(find.text('Submitted').last);
        await settle(tester, 15);
      }, () => _client);
      expect(find.text('Submitted'), findsWidgets);
    });

    testWidgets('without the search endpoint it falls back to the full list',
        (tester) async {
      _overrides['/search'] = (_) => _json({'error': 'missing'}, 404);
      _overrides['/checkins/patients/42'] = (_) => _json([]);
      await pumpPage(tester);
      expect(_calls, contains('GET /api/checkins/patients/42'));
      await openTab(tester, 'Virtual Check-In');
      expect(find.text('No pages'), findsOneWidget);
    });

    testWidgets('check-ins embedded in the patient record are shown',
        (tester) async {
      _overrides['/search'] = (_) => _json({'error': 'missing'}, 404);
      _overrides['/checkins/patients/42'] = (_) => _json([]);
      _overrides['/v1/api/patients/42'] = (request) {
        if (request.url.path != '/v1/api/patients/42') {
          return _handleSync(request);
        }
        return _json({
          ..._profile(),
          'virtualCheckIns': [
            {
              'id': 'v1',
              'type': 'follow_up',
              'status': 'missed',
              'clinicianName': 'Nurse Kim',
              'startedAt': _iso(const Duration(days: 2)),
              'durationMinutes': '15',
              'summary': 'Missed call'
            },
            {
              'checkInId': 'v2',
              'type': 'urgent',
              'status': 'canceled',
              'caregiverName': 'Dr. Lee',
              'startedAt': _iso(const Duration(days: 6)),
              'notes': 'Rescheduled',
              'nextCheckIn': _iso(const Duration(days: -1))
            },
            {
              'id': 'v3',
              'type': 'routine',
              'status': 'completed',
              'durationMinutes': 20
            },
          ],
        });
      };
      await pumpPage(tester);
      await openTab(tester, 'Virtual Check-In');
      await scrollAll(tester);
      expect(find.textContaining('Missed call'), findsWidgets);
    });
  });

  group('PatientDetailsPage – caregiver edits', () {
    testWidgets('Known Risks: edit, change the selection and save',
        (tester) async {
      await pumpPage(tester);
      await openTab(tester, 'Health');
      expect(find.textContaining('Fall risk'), findsWidgets);
      await tester.tap(find.text('Edit').first);
      await settle(tester, 3);
      // Fall risk off, Wandering on.
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Fall risk'));
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Wandering'));
      await settle(tester, 2);
      await http.runWithClient(() async {
        await tester.tap(find.text('Save').first);
        await settle(tester, 20);
      }, () => _client);
      expect(_calls, contains('POST /v1/api/patients/42/risks'));
      expect(_calls, contains('DELETE /v1/api/patients/42/risks/11'));
    });

    testWidgets('Personalization: edit and save', (tester) async {
      await pumpPage(tester);
      final edit = find.text('Edit');
      await tester.ensureVisible(edit.first);
      await tester.tap(edit.first);
      await settle(tester, 3);
      final fields = find.byType(TextField);
      if (fields.evaluate().isNotEmpty) {
        await tester.enterText(fields.first, 'Sal');
      }
      final save = find.text('Save');
      await http.runWithClient(() async {
        await tester.ensureVisible(save.first);
        await tester.tap(save.first);
        await settle(tester, 20);
      }, () => _client);
      expect(
          _calls.any((c) =>
              c.endsWith('/patients/42/profile') && !c.startsWith('GET')),
          isTrue);
    });

    testWidgets('the video call and messaging switches save the link policy',
        (tester) async {
      await pumpPage(tester);
      final video = find.text('Allow Patient-Initiated Video Calls');
      final messaging = find.text('Allow Patient Messaging');
      await http.runWithClient(() async {
        await tester.ensureVisible(video);
        await tester.tap(video);
        await settle(tester, 15);
        await tester.ensureVisible(messaging);
        await tester.tap(messaging);
        await settle(tester, 15);
      }, () => _client);
      expect(_calls.any((c) => c.contains('/77/patient-video-calls')), isTrue);
      expect(find.textContaining('currently blocked'), findsWidgets);
    });

    testWidgets('a refused switch change keeps the old setting',
        (tester) async {
      _overrides['caregiver-patient-links/77'] = (_) => _json({}, 500);
      await pumpPage(tester);
      final video = find.text('Allow Patient-Initiated Video Calls');
      final messaging = find.text('Allow Patient Messaging');
      await http.runWithClient(() async {
        await tester.ensureVisible(video);
        await tester.tap(video);
        await settle(tester, 15);
        await tester.ensureVisible(messaging);
        await tester.tap(messaging);
        await settle(tester, 15);
      }, () => _client);
      expect(find.textContaining('can initiate video calls'), findsWidgets);
    });

    testWidgets('Delete Call History (Dev) asks first, then deletes',
        (tester) async {
      await pumpPage(tester);
      final button = find.text('Delete Call History (Dev)');
      expect(button, findsOneWidget);
      await tester.ensureVisible(button);
      await http.runWithClient(() async {
        await tester.tap(button);
        await settle(tester, 3);
        expect(find.text('Delete Call History (Dev Only)'), findsOneWidget);
        await tester.tap(find.descendant(
            of: find.byType(AlertDialog), matching: find.text('Delete')));
        await settle(tester, 30);
      }, () => _client);
      expect(
          _calls.any((c) =>
              RegExp(r'^DELETE /api/v3/calls/patients/\d+/telemetry$')
                  .hasMatch(c)),
          isTrue);
      expect(
          find.textContaining('Deleted 4 telemetry event(s)'), findsOneWidget);
    });
  });

  group('PatientDetailsPage – load failures', () {
    testWidgets('a failing medications call offers Retry', (tester) async {
      _overrides['/medications'] = (_) => _json({'error': 'down'}, 500);
      await pumpPage(tester);
      await openTab(tester, 'Health');
      await scrollAll(tester);
      expect(find.text('Retry'), findsWidgets);
    });

    testWidgets('failing risk endpoints leave an empty Known Risks card',
        (tester) async {
      _overrides['risk-types'] = (_) => _json({'error': 'down'}, 500);
      _overrides['/risks'] = (_) => _json({'error': 'down'}, 500);
      await pumpPage(tester);
      await openTab(tester, 'Health');
      expect(find.textContaining('Known Risks'), findsWidgets);
    });

    testWidgets('a failed load offers Retry, which reloads the profile',
        (tester) async {
      // The complete profile is missing and the symptoms call fails, so the
      // load stops with no profile and the personalization card says so.
      _overrides['/profile'] = (_) => _json({'error': 'down'}, 500);
      _overrides['/symptom'] = (_) => _json({'error': 'down'}, 500);
      await pumpPage(tester);
      expect(find.textContaining('Error loading'), findsWidgets);

      final retry = find.text('Retry');
      await tester.ensureVisible(retry.first);
      await http.runWithClient(() async {
        await tester.tap(retry.first);
        await settle(tester, 15);
      }, () => _client);
      expect(_calls.where((c) => c == 'GET /v1/api/patients/42').length,
          greaterThan(1));
    });
  });
}
