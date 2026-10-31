// Widget tests for the patient dashboard page
// (lib/features/dashboard/patient_dashboard/pages/patient_dashboard.dart)
// covering the mobile layout, alert building, EVV sections, provider
// call-policy resolution, medication action outcomes and contact sheet.

import 'dart:async';
import 'dart:convert';

import 'package:care_connect_app/features/dashboard/patient_dashboard/pages/patient_dashboard.dart';
import 'package:care_connect_app/features/dashboard/patient_dashboard/widgets/alter_notification_widget.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:care_connect_app/services/api_service_offline.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../mock_user_provider.dart';

class _NoIdUserProvider extends MockUserProvider {
  _NoIdUserProvider() : super(mockUser: null);

  @override
  UserSession? get user => null;
}

/// Per-endpoint responses for the dashboard; tests override what they need.
class _Api {
  List<dynamic> mood = [];
  Object medications = [];
  String? medicationsRaw;
  int medicationsStatus = 200;
  List<dynamic> links = [];
  List<dynamic> vitalAlerts = [];
  Object scheduled = [];
  int scheduledStatus = 200;
  List<dynamic> evvRecords = [];
  int evvStatus = 200;
  FutureOr<http.Response> Function()? provider;
  http.Response Function(http.Request)? lastTaken;
  final requests = <http.Request>[];

  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    final path = request.url.path;
    if (path.endsWith('/mood')) {
      return http.Response(jsonEncode(mood), 200);
    }
    if (path.contains('/last-taken')) {
      return lastTaken != null
          ? lastTaken!(request)
          : http.Response('{}', 200);
    }
    if (path.contains('/medications')) {
      return http.Response(
        medicationsRaw ?? jsonEncode(medications),
        medicationsStatus,
      );
    }
    if (path.contains('caregiver-patient-links')) {
      return http.Response(jsonEncode(links), 200);
    }
    if (path.contains('/alerts/recent')) {
      return http.Response(jsonEncode({'data': vitalAlerts}), 200);
    }
    if (path.contains('/scheduled-visits/')) {
      return http.Response(jsonEncode(scheduled), scheduledStatus);
    }
    if (path.contains('/records/search')) {
      return http.Response(
        jsonEncode({
          'content': evvRecords,
          'totalElements': evvRecords.length,
          'totalPages': 1,
          'size': 200,
          'number': 0,
          'first': true,
          'last': true,
        }),
        evvStatus,
      );
    }
    if (path.endsWith('/provider')) {
      return provider != null ? await provider!() : http.Response('{}', 404);
    }
    return http.Response('[]', 200);
  }
}

late _Api _api;
bool _canLaunch = false;
final _client = MockClient((r) => _api.handle(r));

MockUserProvider _patient({int? patientId = 1}) => MockUserProvider(
      mockUser: MockUser(
        id: 1,
        role: 'PATIENT',
        patientId: patientId,
        name: 'Pat Example',
      ),
    );

Widget _wrap(UserProvider provider, {TargetPlatform? platform}) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData(
      platform: platform,
      splashFactory: InkRipple.splashFactory,
    ),
    // The test font renders wider than real fonts; shrink text so the
    // narrow (mobile) layout does not report overflow in the app header.
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: const TextScaler.linear(0.7)),
      child: child!,
    ),
    home: ChangeNotifierProvider<UserProvider>.value(
      value: provider,
      child: const PatientDashboard(),
    ),
  );
}

Future<void> _pump(
  WidgetTester tester, {
  UserProvider? provider,
  bool tablet = false,
  TargetPlatform? platform,
}) async {
  tester.view.physicalSize =
      tablet ? const Size(1400, 3000) : const Size(600, 5000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await http.runWithClient(() async {
    await tester.pumpWidget(_wrap(provider ?? _patient(), platform: platform));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }, () => _client);
}

Map<String, dynamic> _evvRecord({required int id, required int patientId}) {
  const ts = '2026-01-10T09:00:00';
  return {
    'id': id,
    'patient': {'id': patientId, 'firstName': 'Pat', 'lastName': 'Example'},
    'serviceType': 'Bathing Assist $id',
    'individualName': 'Pat Example',
    'caregiverId': 3,
    'dateOfService': '2026-01-10',
    'timeIn': ts,
    'timeOut': ts,
    'status': 'COMPLETED',
    'stateCode': 'MD',
    'createdAt': ts,
    'updatedAt': ts,
  };
}

Map<String, dynamic> _providerJson(Map<String, dynamic> overrides) => {
      'name': 'Dr. Base Provider',
      'specialty': 'Family Medicine',
      'organization': 'Base Clinic',
      'phone': '(555) 999-0000',
      'email': 'base@example.test',
      'nextAppointment': '2026-12-01T10:00:00',
      'appointmentType': 'Checkup',
      ...overrides,
    };

List<Map<String, dynamic>> _pendingMedication() => [
      {
        'id': 101,
        'medicationName': 'Lisinopril',
        'dosage': '10 mg',
        'frequency': 'Once daily',
        'isActive': true,
        'lastTaken': null,
      },
    ];

void _channels() {
  SharedPreferences.setMockInitialValues({});
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    (call) async {
      if (call.method == 'readAll') return <String, String>{};
      if (call.method == 'containsKey') return false;
      return null;
    },
  );
  for (final name in [
    'plugins.flutter.io/url_launcher',
    'plugins.flutter.io/url_launcher_android',
    'plugins.flutter.io/url_launcher_ios',
    'plugins.flutter.io/url_launcher_windows',
  ]) {
    messenger.setMockMethodCallHandler(MethodChannel(name), (call) async {
      if (call.method == 'canLaunch') return _canLaunch;
      return true;
    });
  }
}

void main() {
  setUpAll(() {
    ApiServiceOffline.debugOverrideHttpClient(_client);
    ApiService.debugSetHttpClient(_client);
  });

  tearDownAll(() {
    ApiServiceOffline.debugOverrideHttpClient(null);
  });

  setUp(() {
    _api = _Api();
    _canLaunch = false;
    _channels();
  });

  group('PatientDashboard without a session', () {
    testWidgets('redirects to the login route', (tester) async {
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, __) => ChangeNotifierProvider<UserProvider>.value(
              value: _NoIdUserProvider(),
              child: const PatientDashboard(),
            ),
          ),
          GoRoute(
            path: '/login',
            builder: (_, __) => const Text('Login Route'),
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp.router(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Login Route'), findsOneWidget);
    });
  });

  group('PatientDashboard mobile layout', () {
    testWidgets('renders mood, alerts, EVV lists and provider', (tester) async {
      final now = DateTime.now();
      final future = now.add(const Duration(days: 2));
      String d(DateTime x) =>
          '${x.year.toString().padLeft(4, '0')}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';
      _api
        ..mood = [
          {'score': '3', 'label': '', 'createdAt': now.toIso8601String()},
          {
            'score': 4.4,
            'label': 'Sad',
            'createdAt': now
                .subtract(const Duration(days: 1))
                .millisecondsSinceEpoch,
          },
          {'score': 'x', 'label': 'Neutral', 'date': 'not-a-date'},
          'not-a-map',
        ]
        ..vitalAlerts = [
          {
            'metricType': 'heart_rate',
            'measuredValue': 130,
            'alertLevel': 'CRITICAL',
            'successCount': 2,
            'failureCount': '1',
          },
          {
            'metricType': 'blood_pressure',
            'measuredValue': '150/95',
            'alertLevel': 'LOW',
            'successCount': '3',
            'failureCount': 0,
          },
          {
            'metricType': 'body_temp',
            'measuredValue': 101,
            'alertLevel': 'MEDIUM',
          },
        ]
        ..evvRecords = [
          _evvRecord(id: 1, patientId: 1),
          _evvRecord(id: 2, patientId: 99),
        ]
        ..scheduled = [
          // HH:mm time with ISO date
          {'id': 1, 'serviceType': 'Bathing', 'scheduledDate': d(future), 'scheduledTime': '09:30'},
          // duplicate id is skipped
          {'id': 1, 'serviceType': 'Bathing', 'scheduledDate': d(future), 'scheduledTime': '09:30'},
          // full ISO timestamp
          {'visitId': 2, 'service_type': 'Meals', 'scheduledTime': future.add(const Duration(hours: 3)).toIso8601String()},
          // epoch millis
          {'scheduledVisitId': 3, 'service': 'Laundry', 'time': future.add(const Duration(hours: 5)).millisecondsSinceEpoch},
          // unparseable time string falls back to date + split time
          {'id': 4, 'scheduledDate': '${d(future)}T00:00:00', 'scheduledTime': '10:15:xx'},
          // past visit is dropped
          {'id': 5, 'serviceType': 'Old', 'scheduledTime': now.subtract(const Duration(days: 1)).toIso8601String()},
          // no time at all is dropped
          {'id': 6, 'serviceType': 'Never'},
        ]
        ..provider = () => http.Response(
              jsonEncode({
                'name': 'Dr. Alex Kim',
                'specialty': 'Geriatrics',
                'organization': 'Test Clinic',
                'phone': '(555) 000-1111',
                'email': 'alex.kim@example.test',
                'nextAppointment': '2026-12-01T10:00:00',
                'appointmentType': 'Follow-up',
              }),
              200,
            );

      await _pump(tester);

      // Mobile single column layout renders the pieces.
      expect(find.text('Geriatrics'), findsOneWidget);
      expect(find.text('Test Clinic'), findsOneWidget);

      // Vital alerts.
      expect(
        find.textContaining('heart rate alert: 130 [CRITICAL] (2 delivered, 1 failed)', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('blood pressure alert: 150/95 [LOW] (3 delivered)', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('body temp alert: 101 [MEDIUM] (0 delivered)', findRichText: true),
        findsOneWidget,
      );

      // Low mood alert from the 7-day average.
      expect(
        find.textContaining('Mood score below normal range',
            findRichText: true),
        findsOneWidget,
      );

      // Upcoming EVV list (deduplicated, sorted, past/invalid dropped).
      expect(find.text('Bathing'), findsOneWidget);
      expect(find.text('Meals'), findsOneWidget);
      expect(find.text('Laundry'), findsOneWidget);
      expect(find.text('Service'), findsOneWidget);
      expect(find.text('Old'), findsNothing);
      expect(find.text('Never'), findsNothing);

      // Past EVV list only shows this patient's records.
      expect(find.text('Bathing Assist 1'), findsOneWidget);
      expect(find.text('Bathing Assist 2'), findsNothing);
      expect(find.text('1/10/2026'), findsOneWidget);
    });

    for (final tablet in [false, true]) {
      testWidgets(
          'dismissing an alert hides it (${tablet ? 'tablet' : 'mobile'})',
          (tester) async {
        _api.vitalAlerts = [
          {
            'metricType': 'spo2',
            'measuredValue': 85,
            'alertLevel': 'HIGH',
            'successCount': 1,
            'failureCount': 0,
          },
        ];
        await _pump(tester, tablet: tablet);
        const text = 'spo2 alert: 85 [HIGH] (1 delivered)';
        final alert = find.textContaining(text, findRichText: true);
        expect(alert, findsOneWidget);
        final close = find.descendant(
          of: find.ancestor(
            of: alert,
            matching: find.byType(AlertNotification),
          ),
          matching: find.byIcon(Icons.close),
        );
        await tester.tap(close);
        await tester.pump();
        expect(find.textContaining(text, findRichText: true), findsNothing);
      });
    }

    testWidgets('mood labels map to tags for each score band', (tester) async {
      for (final entry in <int, String>{
        10: 'Excellent',
        8: 'Good',
        6: 'Fair',
        2: 'Poor',
        0: 'Unknown',
      }.entries) {
        _api = _Api()
          ..mood = [
            {
              'score': entry.key,
              'label': '',
              'createdAt': DateTime.now().toIso8601String(),
            },
          ];
        await _pump(tester);
        expect(find.text(entry.value), findsWidgets,
            reason: 'score ${entry.key}');
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('patient without patient id skips patient-only loads',
        (tester) async {
      await _pump(tester, provider: _patient(patientId: null));
      expect(
        _api.requests.where((r) => r.url.path.contains('/alerts/recent')),
        isEmpty,
      );
      expect(
        _api.requests.where((r) => r.url.path.contains('/records/search')),
        isEmpty,
      );
      expect(find.text('SOS Emergency'), findsOneWidget);
    });

    testWidgets('malformed scheduled visits leave upcoming list empty',
        (tester) async {
      _api
        ..scheduled = {'not': 'a list'}
        ..evvRecords = [_evvRecord(id: 3, patientId: 1)];
      await _pump(tester);
      expect(find.text('No upcoming appointments.'), findsOneWidget);
      expect(find.text('Bathing Assist 3'), findsOneWidget);
    });

    testWidgets('EVV search failure leaves both lists empty', (tester) async {
      _api.evvStatus = 500;
      await _pump(tester);
      expect(find.text('No upcoming appointments.'), findsOneWidget);
      expect(find.text('No past visits found.'), findsOneWidget);
    });

    testWidgets('scheduled visits non-200 response leaves list empty',
        (tester) async {
      _api
        ..scheduledStatus = 500
        ..evvRecords = [];
      await _pump(tester);
      expect(find.text('No upcoming appointments.'), findsOneWidget);
    });

    testWidgets('EVV refresh button reloads the sections', (tester) async {
      await _pump(tester);
      final before = _api.requests
          .where((r) => r.url.path.contains('/records/search'))
          .length;
      final refresh = find.byIcon(Icons.refresh);
      await tester.ensureVisible(refresh.first);
      await tester.tap(refresh.first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final after = _api.requests
          .where((r) => r.url.path.contains('/records/search'))
          .length;
      expect(after, greaterThan(before));
    });

    testWidgets('SOS button opens the emergency dialog', (tester) async {
      await _pump(tester);
      final sos = find.text('SOS Emergency');
      await tester.ensureVisible(sos);
      await tester.tap(sos);
      await tester.pumpAndSettle();
      expect(find.text('Fall Emergency'), findsOneWidget);
    });
  });

  group('PatientDashboard provider loading', () {
    testWidgets('invalid provider JSON falls back to default provider',
        (tester) async {
      _api.provider = () => http.Response('not json', 200);
      await _pump(tester);
      expect(find.text('Dr. Sarah Mitchell, MD'), findsOneWidget);
    });

    testWidgets('empty provider map uses default provider', (tester) async {
      _api.provider = () => http.Response('{}', 200);
      await _pump(tester);
      expect(find.text('Internal Medicine'), findsOneWidget);
    });
  });

  group('PatientDashboard contact provider sheet', () {
    Future<void> openSheet(WidgetTester tester) async {
      final contact = find.text('Contact Provider');
      await tester.ensureVisible(contact);
      await tester.tap(contact);
      await tester.pumpAndSettle();
    }

    testWidgets('video call disabled without caregiver links shows message',
        (tester) async {
      await _pump(tester);
      await openSheet(tester);
      final video = find.text('Video Call');
      expect(video, findsOneWidget);
      // Disabled ListTile does not respond to taps; invoke the handler.
      final tile = tester.widget<ListTile>(
        find.ancestor(of: video, matching: find.byType(ListTile)),
      );
      expect(tile.enabled, isFalse);
      tile.onTap!();
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('provider matched by caregiver user id with calls disabled',
        (tester) async {
      _api
        ..provider = (() => http.Response(
              jsonEncode(_providerJson({'name': 'Dr. Lee', 'caregiverUserId': '42'})),
              200,
            ))
        ..links = [
          {'caregiverUserId': 41, 'caregiverName': 'Other'},
          {
            'caregiverUserId': '42',
            'caregiverName': 'Lee',
            'patientVideoCallsEnabled': 'false',
          },
        ];
      await _pump(tester);
      await openSheet(tester);
      final tile = tester.widget<ListTile>(
        find.ancestor(
          of: find.text('Video Call'),
          matching: find.byType(ListTile),
        ),
      );
      expect(tile.enabled, isFalse);
    });

    testWidgets('provider matched by email enables video calls',
        (tester) async {
      _api
        ..provider = (() => http.Response(
              jsonEncode(_providerJson({
                'name': 'Dr. Email Match',
                'email': 'Match@Example.test',
              })),
              200,
            ))
        ..links = [
          {
            'caregiverUserId': 7,
            'caregiverEmail': 'match@example.test',
            'patientVideoCallsEnabled': true,
          },
        ];
      await _pump(tester);
      await openSheet(tester);
      final tile = tester.widget<ListTile>(
        find.ancestor(
          of: find.text('Video Call'),
          matching: find.byType(ListTile),
        ),
      );
      expect(tile.enabled, isTrue);
    });

    testWidgets('provider matched by phone and by name', (tester) async {
      _api
        ..provider = (() => http.Response(
              jsonEncode(_providerJson({
                'name': 'Dr. Phone Person',
                'email': '',
                'phone': '(555) 222-3333',
              })),
              200,
            ))
        ..links = [
          {'caregiverUserId': 8, 'email': 'nope@x.test', 'phone': '555.222.3333'},
        ];
      await _pump(tester);
      await openSheet(tester);
      expect(
        tester
            .widget<ListTile>(find.ancestor(
              of: find.text('Video Call'),
              matching: find.byType(ListTile),
            ))
            .enabled,
        isTrue,
      );
      await tester.pumpWidget(const SizedBox());

      _api = _Api()
        ..provider = (() => http.Response(
              jsonEncode(_providerJson({'name': 'Dr. Name Match, MD', 'phone': ''})),
              200,
            ))
        ..links = [
          {'caregiverUserId': 9, 'phone': '1', 'name': 'Name Match'},
        ];
      await _pump(tester);
      await openSheet(tester);
      expect(
        tester
            .widget<ListTile>(find.ancestor(
              of: find.text('Video Call'),
              matching: find.byType(ListTile),
            ))
            .enabled,
        isTrue,
      );
    });

    testWidgets('no matching caregiver link disables video calls',
        (tester) async {
      _api
        ..provider = (() => http.Response(
              jsonEncode(_providerJson({'name': 'Dr. Nobody', 'email': 'a@b.test'})),
              200,
            ))
        ..links = [
          {'caregiverUserId': 5, 'caregiverName': 'Somebody Else'},
        ];
      await _pump(tester);
      await openSheet(tester);
      expect(
        tester
            .widget<ListTile>(find.ancestor(
              of: find.text('Video Call'),
              matching: find.byType(ListTile),
            ))
            .enabled,
        isFalse,
      );
    });

    testWidgets('email option launches mail client when available',
        (tester) async {
      _canLaunch = true;
      await _pump(tester);
      await openSheet(tester);
      await tester.tap(find.text('Email').last);
      await tester.pumpAndSettle();
      expect(find.text('Video Call'), findsNothing);
    });

    testWidgets('call and email options close the sheet', (tester) async {
      await _pump(tester, platform: TargetPlatform.iOS);
      await openSheet(tester);
      await tester.tap(find.text('Call'));
      await tester.pumpAndSettle();
      expect(find.text('Video Call'), findsNothing);

      await openSheet(tester);
      await tester.tap(find.text('Email').last);
      await tester.pumpAndSettle();
      expect(find.text('Video Call'), findsNothing);
    });
  });

  group('PatientDashboard medication actions', () {
    Future<void> tapAction(WidgetTester tester, String label) async {
      final f = find.text(label);
      await tester.ensureVisible(f.first);
      await tester.tap(f.first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets('queued offline taken update shows queued message',
        (tester) async {
      _api
        ..medications = _pendingMedication()
        ..lastTaken = (r) => http.Response(
              '{}',
              503,
              headers: {'x-offline-queued': 'true'},
            );
      await _pump(tester);
      await tapAction(tester, 'Mark Taken');
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('Medication marked as taken until next dose'),
          findsNothing);
    });

    testWidgets('queued offline missed update shows queued message',
        (tester) async {
      _api
        ..medications = _pendingMedication()
        ..lastTaken = (r) => http.Response(
              '{}',
              503,
              headers: {'x-offline-queued': 'true'},
            );
      await _pump(tester);
      await tapAction(tester, 'Mark Missed');
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('Medication marked as missed'), findsNothing);
    });

    testWidgets('successful taken and missed updates show confirmations',
        (tester) async {
      _api.medications = _pendingMedication();
      await _pump(tester);
      await tapAction(tester, 'Mark Taken');
      expect(find.text('Medication marked as taken until next dose'),
          findsOneWidget);
      tester
          .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
          .clearSnackBars();
      await tester.pumpAndSettle();
    });

    testWidgets('successful missed update shows confirmation', (tester) async {
      _api.medications = _pendingMedication();
      await _pump(tester);
      await tapAction(tester, 'Mark Missed');
      expect(find.text('Medication marked as missed'), findsOneWidget);
    });

    testWidgets('failed update shows error message', (tester) async {
      _api
        ..medications = _pendingMedication()
        ..lastTaken = (r) => http.Response('{}', 500);
      await _pump(tester);
      await tapAction(tester, 'Mark Taken');
      final snack = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(snack.backgroundColor, isNotNull);
      expect(find.text('Medication marked as taken until next dose'),
          findsNothing);
    });

    testWidgets('medication load error clears reminders', (tester) async {
      _api.medicationsRaw = '{not json';
      await _pump(tester);
      expect(find.text('Mark Taken'), findsNothing);
    });
  });
}
