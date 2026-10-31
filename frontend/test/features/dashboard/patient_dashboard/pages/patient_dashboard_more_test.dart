// More happy-path tests for the patient dashboard page
// (lib/features/dashboard/patient_dashboard/pages/patient_dashboard.dart):
// starting a video call to a provider whose caregiver link allows it, and a
// medication action without a patient id. The harness mirrors
// patient_dashboard_flows_test.dart.

import 'dart:async';
import 'dart:convert';

import 'package:care_connect_app/features/dashboard/patient_dashboard/pages/patient_dashboard.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:care_connect_app/services/api_service_offline.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../mock_user_provider.dart';

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

/// Removes each pushed page route before it builds, so a tap that opens the
/// video call screen records the push without starting a call.
class _SwallowPushes extends NavigatorObserver {
  final pushed = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute && previousRoute != null) {
      pushed.add(route);
      scheduleMicrotask(() => route.navigator?.removeRoute(route));
    }
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

  Future<_SwallowPushes> pumpWithObserver(WidgetTester tester,
      {UserProvider? provider}) async {
    final observer = _SwallowPushes();
    tester.view.physicalSize = const Size(600, 5000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await http.runWithClient(() async {
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        navigatorObservers: [observer],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(0.7)),
          child: child!,
        ),
        home: ChangeNotifierProvider<UserProvider>.value(
          value: provider ?? _patient(),
          child: const PatientDashboard(),
        ),
      ));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }, () => _client);
    return observer;
  }

  Future<void> openSheet(WidgetTester tester) async {
    final contact = find.text('Contact Provider');
    await tester.ensureVisible(contact);
    await tester.tap(contact);
    await tester.pumpAndSettle();
  }

  for (final name in ['Dr. Email Match', 'Plato']) {
    testWidgets('an allowed provider video call opens the call ($name)',
        (tester) async {
      _api
        ..provider = (() => http.Response(
              jsonEncode(_providerJson({
                'name': name,
                'email': 'Match@Example.test',
              })),
              200,
            ))
        ..links = [
          {
            'caregiverUserId': 7,
            'caregiverName': name,
            'caregiverEmail': 'match@example.test',
            'patientVideoCallsEnabled': true,
          },
        ];
      final observer = await pumpWithObserver(tester);
      await openSheet(tester);
      final tile = tester.widget<ListTile>(find.ancestor(
          of: find.text('Video Call'), matching: find.byType(ListTile)));
      expect(tile.enabled, isTrue);
      await http.runWithClient(() async {
        tile.onTap!();
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
      }, () => _client);
      expect(observer.pushed, isNotEmpty);
    });
  }
}
