// Additional coverage for the patient dashboard page
// (lib/features/dashboard/patient_dashboard/pages/patient_dashboard.dart):
// error screen + retry, session loss redirect, malformed mood / caregiver
// link responses, the enabled video-call branches and the SMS dialog.

import 'dart:convert';

import 'package:care_connect_app/features/dashboard/patient_dashboard/pages/patient_dashboard.dart';
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

/// User provider whose session can be dropped mid-test.
class _TogglingUserProvider extends MockUserProvider {
  _TogglingUserProvider()
      : super(
          mockUser: MockUser(
            id: 1,
            role: 'PATIENT',
            patientId: 1,
            name: 'Pat Example',
          ),
        );

  bool loggedOut = false;
  bool dropPatientId = false;

  @override
  UserSession? get user {
    if (loggedOut) return null;
    if (dropPatientId) {
      return MockUser(id: 1, role: 'PATIENT', patientId: null, name: 'Pat');
    }
    return super.user;
  }
}

class _Api {
  String moodRaw = '[]';
  String linksRaw = '[]';
  int linksStatus = 200;
  Map<String, dynamic>? provider;
  String medsRaw = '[]';

  Future<http.Response> handle(http.Request request) async {
    final path = request.url.path;
    if (path.endsWith('/mood')) return http.Response(moodRaw, 200);
    if (path.contains('caregiver-patient-links')) {
      return http.Response(linksRaw, linksStatus);
    }
    if (path.contains('/alerts/recent')) {
      return http.Response(jsonEncode({'data': []}), 200);
    }
    if (path.contains('/records/search')) {
      return http.Response(
        jsonEncode({
          'content': [],
          'totalElements': 0,
          'totalPages': 1,
          'size': 200,
          'number': 0,
          'first': true,
          'last': true,
        }),
        200,
      );
    }
    if (path.contains('/medications')) return http.Response(medsRaw, 200);
    if (path.endsWith('/provider')) {
      return provider == null
          ? http.Response('{}', 404)
          : http.Response(jsonEncode(provider), 200);
    }
    return http.Response('[]', 200);
  }
}

late _Api _api;
final _client = MockClient((r) => _api.handle(r));

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
      if (call.method == 'canLaunch') return false;
      return true;
    });
  }
}

Future<void> _pump(WidgetTester tester, UserProvider provider) async {
  tester.view.physicalSize = const Size(600, 5000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => ChangeNotifierProvider<UserProvider>.value(
          value: provider,
          child: const PatientDashboard(),
        ),
      ),
      GoRoute(path: '/login', builder: (_, __) => const Text('Login Route')),
    ],
  );
  await http.runWithClient(() async {
    await tester.pumpWidget(MaterialApp.router(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(splashFactory: InkRipple.splashFactory),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(0.7)),
        child: child!,
      ),
      routerConfig: router,
    ));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }, () => _client);
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
    _channels();
  });

  Future<void> openSheet(WidgetTester tester) async {
    final contact = find.text('Contact Provider');
    await tester.ensureVisible(contact);
    await tester.tap(contact);
    await tester.pumpAndSettle();
  }

  ListTile videoTile(WidgetTester tester) => tester.widget<ListTile>(
        find.ancestor(
          of: find.text('Video Call'),
          matching: find.byType(ListTile),
        ),
      );

  void enableVideoCalls() {
    _api
      ..provider = {
        'name': 'Dr. Email Match',
        'specialty': 'Family Medicine',
        'organization': 'Clinic',
        'phone': '(555) 999-0000',
        'email': 'match@example.test',
      }
      ..linksRaw = jsonEncode([
        {
          'caregiverUserId': 7,
          'caregiverEmail': 'match@example.test',
          'caregiverName': 'Casey Match',
          'patientVideoCallsEnabled': true,
        },
      ]);
  }

  testWidgets('malformed mood and caregiver link responses are tolerated',
      (tester) async {
    _api
      ..moodRaw = '{not json'
      ..linksRaw = '{not json'
      ..linksStatus = 500;
    await _pump(tester, _TogglingUserProvider());
    expect(find.byType(PatientDashboard), findsOneWidget);
    expect(find.text('SOS Emergency'), findsOneWidget);
  });

  testWidgets('error screen retry reloads, and a lost session goes to login',
      (tester) async {
    final provider = _TogglingUserProvider();
    await _pump(tester, provider);

    final dynamic state = tester.state(find.byType(PatientDashboard));
    state.error = 'Boom happened';
    state.loading = false;
    tester.element(find.byType(PatientDashboard)).markNeedsBuild();
    await tester.pump();
    expect(find.text('Boom happened'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);

    provider.loggedOut = true;
    await http.runWithClient(() async {
      await tester.tap(find.byIcon(Icons.refresh).first);
      await tester.pumpAndSettle();
    }, () => _client);
    expect(find.text('Login Route'), findsOneWidget);
  });

  testWidgets('enabled video call without provider info shows a snackbar',
      (tester) async {
    enableVideoCalls();
    await _pump(tester, _TogglingUserProvider());
    await openSheet(tester);
    expect(videoTile(tester).enabled, isTrue);

    final dynamic state = tester.state(find.byType(PatientDashboard));
    state.primaryCareProvider = null;
    videoTile(tester).onTap!();
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('enabled video call without a session shows a snackbar',
      (tester) async {
    enableVideoCalls();
    final provider = _TogglingUserProvider();
    await _pump(tester, provider);
    await openSheet(tester);
    expect(videoTile(tester).enabled, isTrue);

    provider.loggedOut = true;
    videoTile(tester).onTap!();
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('SMS button opens message dialog and sends', (tester) async {
    await _pump(tester, _TogglingUserProvider());
    final dynamic state = tester.state(find.byType(PatientDashboard));
    state.caregivers = <Map<String, dynamic>>[
      {'id': 5, 'firstName': 'Casey', 'lastName': 'Care', 'phone': ''},
      {
        'id': 6,
        'firstName': 'Robin',
        'lastName': 'Helper',
        'phone': '5551234567',
      },
    ];
    tester.element(find.byType(PatientDashboard)).markNeedsBuild();
    await tester.pump();

    final sms = find.byIcon(Icons.sms);
    await tester.ensureVisible(sms);
    await tester.tap(sms);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('Robin Helper'), findsWidgets);

    // Cancel first, then reopen and send.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);

    await tester.tap(sms);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.descendant(
            of: find.byType(AlertDialog), matching: find.byType(TextField)),
        'Hello there');
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(ElevatedButton)));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('medication action without a patient id shows an error',
      (tester) async {
    _api.medsRaw = jsonEncode([
      {
        'id': 101,
        'medicationName': 'Lisinopril',
        'dosage': '10 mg',
        'frequency': 'Once daily',
        'isActive': true,
        'lastTaken': null,
      },
    ]);
    final provider = _TogglingUserProvider();
    await _pump(tester, provider);
    final taken = find.text('Mark Taken');
    expect(taken, findsWidgets);
    provider.dropPatientId = true;
    await tester.ensureVisible(taken.first);
    await tester.tap(taken.first);
    await tester.pump();
    final snack = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(snack.backgroundColor, isNotNull);
  });
}
