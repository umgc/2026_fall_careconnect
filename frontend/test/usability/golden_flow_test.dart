// Golden-path tests: derive the MINIMUM taps required for each feature flow by
// driving its intended shortest path with the usability instrument mounted.
//
// The runnable example below (password-reset request) needs no backend. The
// slide-6 headline flows are scaffolded as `skip:`ped templates — fill in the
// confirmed step sequence + service mocks and remove the skip to have each one
// emit its designed optimal tap count (feed that number back into
// kUsabilityOptimalTaps / kUsabilityFlows).

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/features/ai/presentation/pages/voice_command_ai.dart';
import 'package:care_connect_app/features/auth/presentation/pages/login_page.dart';
import 'package:care_connect_app/features/evv/presentation/pages/checkin_location_page.dart';
import 'package:care_connect_app/features/evv/presentation/pages/checkout_location_page.dart';
import 'package:care_connect_app/features/evv/presentation/pages/incident_report_screens.dart';
import 'package:care_connect_app/features/evv/presentation/pages/patient_selection_page.dart';
import 'package:care_connect_app/features/evv/presentation/pages/visit_complete_page.dart';
import 'package:care_connect_app/features/evv/schedule/pages/schedule_page.dart';
import 'package:care_connect_app/features/dashboard/models/patient_model.dart';
import 'package:care_connect_app/features/auth/presentation/pages/reset_password_screen.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:care_connect_app/services/api_service_offline.dart';
import 'package:care_connect_app/services/voice_intent_service.dart';

import '../mock_user_provider.dart';
import 'golden_flow.dart';

/// Wraps a screen with the app's localization delegates so widgets that call
/// AppLocalizations.of(context) build correctly under test.
Widget _localizedApp(Widget home) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    );

/// Suppresses only RenderFlex "overflowed" errors (LoginPage's security badges
/// overflow the card by design) while leaving real errors intact.
void _suppressOverflow() {
  final previous = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    if (details.exceptionAsString().contains('overflowed')) return;
    previous?.call(details);
  };
  addTearDown(() => FlutterError.onError = previous);
}

/// LoginPage wrapped with the providers, router (with the post-login dashboard
/// routes it navigates to), and localization delegates it needs to build.
Widget _loginApp() {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, __) => const LoginPage()),
      GoRoute(path: '/login', builder: (_, __) => const Scaffold()),
      GoRoute(path: '/signup', builder: (_, __) => const Scaffold()),
      GoRoute(path: '/reset-password', builder: (_, __) => const Scaffold()),
      GoRoute(path: '/dashboard', builder: (_, __) => const Scaffold()),
      GoRoute(path: '/caregiver-dashboard', builder: (_, __) => const Scaffold()),
      GoRoute(path: '/patient-dashboard', builder: (_, __) => const Scaffold()),
    ],
  );
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<UserProvider>(create: (_) => UserProvider()),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  );
}

/// VoiceCommandAI at /voice plus stub destination pages so `context.go`
/// navigation commands resolve under test.
Widget _voiceApp() {
  final router = GoRouter(
    initialLocation: '/voice',
    routes: [
      GoRoute(path: '/voice', builder: (_, __) => const VoiceCommandAI()),
      GoRoute(
          path: '/dashboard',
          builder: (_, __) => const Scaffold(body: Text('Dashboard Page'))),
      GoRoute(
          path: '/calendar',
          builder: (_, __) => const Scaffold(body: Text('Calendar Page'))),
      GoRoute(
          path: '/symptoms',
          builder: (_, __) => const Scaffold(body: Text('Symptoms Page'))),
    ],
  );
  return MaterialApp.router(
    routerConfig: router,
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
  );
}

/// Mocks the native speech / wake-word plugins so VoiceCommandAI can initialize,
/// listen, and receive recognition results in a headless test.
void _setupVoiceMocks() {
  VoiceIntentService.testOverride = ({
    required String utterance,
    String locale = 'en',
    String? screenId,
  }) =>
      null; // fall through to on-device keyword matching
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    const MethodChannel('flutter.picovoice.ai/porcupine_manager'),
    (call) async => null,
  );
  messenger.setMockMethodCallHandler(
    const MethodChannel('plugin.csdcorp.com/speech_to_text'),
    (call) async {
      if (call.method == 'has_permission') return true;
      if (call.method == 'initialize') return true;
      if (call.method == 'listen') return true;
      return null; // cancel / stop / others
    },
  );
  addTearDown(() {
    VoiceIntentService.testOverride = null;
    messenger.setMockMethodCallHandler(
        const MethodChannel('flutter.picovoice.ai/porcupine_manager'), null);
    messenger.setMockMethodCallHandler(
        const MethodChannel('plugin.csdcorp.com/speech_to_text'), null);
  });
}

/// Delivers a final speech-recognition result to the plugin channel (this is a
/// platform message, NOT a tap, so it is not counted by the instrument).
Future<void> _sendVoiceResult(WidgetTester tester, String words) async {
  final resultJson = jsonEncode({
    'resultType': 2,
    'alternates': [
      {'recognizedWords': words, 'confidence': 0.95}
    ],
  });
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
    'plugin.csdcorp.com/speech_to_text',
    const StandardMethodCodec()
        .encodeMethodCall(MethodCall('textRecognition', resultJson)),
    (ByteData? data) {},
  );
  await tester.pump();
}

/// CheckinLocationPage (for a loaded caregiver) plus the visit-progress route it
/// pushes to on a completed check-in.
Widget _checkinApp() {
  final router = GoRouter(
    initialLocation: '/evv/checkin-location',
    routes: [
      GoRoute(
        path: '/evv/checkin-location',
        builder: (_, __) =>
            CheckinLocationPage(patientId: 1, serviceType: 'Personal Care'),
      ),
      GoRoute(
          path: '/evv/visit-progress',
          builder: (_, __) =>
              const Scaffold(body: Text('Visit In Progress Page'))),
      GoRoute(path: '/evv/select-patient', builder: (_, __) => const Scaffold()),
      GoRoute(path: '/dashboard', builder: (_, __) => const Scaffold()),
    ],
  );
  return ChangeNotifierProvider<UserProvider>.value(
    value: MockUserProvider(
        mockUser: MockUser(id: 1, role: 'CAREGIVER', caregiverId: 1)),
    child: MaterialApp.router(
      routerConfig: router,
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  );
}

/// PatientSelectionPage plus the start-visit route it pushes to on selection.
Widget _selectPatientApp() {
  final router = GoRouter(
    initialLocation: '/evv/select-patient',
    routes: [
      GoRoute(
          path: '/evv/select-patient',
          builder: (_, __) => const PatientSelectionPage()),
      GoRoute(
          path: '/evv/start-visit',
          builder: (_, __) => const Scaffold(body: Text('Start Visit Page'))),
      GoRoute(path: '/add-patient', builder: (_, __) => const Scaffold()),
      GoRoute(path: '/dashboard', builder: (_, __) => const Scaffold()),
    ],
  );
  return ChangeNotifierProvider<UserProvider>.value(
    value: MockUserProvider(
        mockUser: MockUser(id: 1, role: 'CAREGIVER', caregiverId: 1)),
    child: MaterialApp.router(
      routerConfig: router,
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  );
}

/// CheckoutLocationPage plus the visit-complete route it pushes to on checkout.
Widget _checkoutApp() {
  final router = GoRouter(
    initialLocation: '/evv/checkout-location',
    routes: [
      GoRoute(
        path: '/evv/checkout-location',
        builder: (_, __) => CheckoutLocationPage(
          patientId: 1,
          serviceType: 'Personal Care',
          locationType: 'gps',
          notes: 'Visit notes',
          duration: 3600,
        ),
      ),
      GoRoute(
          path: '/evv/visit-complete',
          builder: (_, __) => const Scaffold(body: Text('Visit Complete Page'))),
      GoRoute(path: '/evv/select-patient', builder: (_, __) => const Scaffold()),
      GoRoute(path: '/dashboard', builder: (_, __) => const Scaffold()),
    ],
  );
  return ChangeNotifierProvider<UserProvider>.value(
    value: MockUserProvider(
        mockUser: MockUser(id: 1, role: 'CAREGIVER', caregiverId: 1)),
    child: MaterialApp.router(
      routerConfig: router,
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  );
}

/// VisitCompletePage (pre-filled visit summary) plus the success route it pushes
/// to once the EVV record submits.
Widget _visitCompleteApp() {
  final provider = UserProvider()
    ..setUser(UserSession(
      id: 1,
      email: 'cg@careconnect.com',
      role: 'CAREGIVER',
      token: 'test-token',
      caregiverId: 1,
      name: 'Test Caregiver',
    ));
  final router = GoRouter(
    initialLocation: '/visit-complete',
    routes: [
      GoRoute(
        path: '/visit-complete',
        builder: (_, __) => VisitCompletePage(
          patientId: 42,
          serviceType: 'Personal Care',
          checkinLocationType: 'gps',
          checkoutLocationType: 'gps',
          checkinLatitude: 38.9,
          checkinLongitude: -77.0,
          checkoutLatitude: 38.9,
          checkoutLongitude: -77.0,
          notes: 'Administered morning medications',
          duration: 3600,
        ),
      ),
      GoRoute(
          path: '/evv/visit-completed-success',
          builder: (_, __) => const Scaffold(body: Text('VISIT SUCCESS'))),
      GoRoute(path: '/evv', builder: (_, __) => const Scaffold()),
      GoRoute(path: '/evv/select-patient', builder: (_, __) => const Scaffold()),
    ],
  );
  return ChangeNotifierProvider<UserProvider>.value(
    value: provider,
    child: MaterialApp.router(
      routerConfig: router,
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  );
}

/// SchedulePage for a caregiver.
Widget _scheduleApp() {
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, __) => const SchedulePage()),
      GoRoute(
          path: '/evv/checkin-location',
          builder: (_, __) => const Scaffold()),
      GoRoute(
          path: '/evv/select-patient', builder: (_, __) => const Scaffold()),
    ],
  );
  return ChangeNotifierProvider<UserProvider>.value(
    value: MockUserProvider(
        mockUser: MockUser(id: 1, role: 'CAREGIVER', caregiverId: 1)),
    child: MaterialApp.router(
      routerConfig: router,
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  );
}

void main() {
  setUp(() {
    // Opt out so endFlow's telemetry event short-circuits (no network in tests).
    SharedPreferences.setMockInitialValues({'telemetry_opted_out': true});
  });

  testWidgets('golden path — Request password reset (minimum taps)',
      (tester) async {
    final result = await measureGoldenFlow(
      tester,
      name: 'flow_request_password_reset',
      app: _localizedApp(const ResetPasswordScreen()),
      drive: (t) async {
        // Designed minimal path: focus the email field, type, submit.
        final email = find.byType(TextFormField).first;
        await t.tap(email); // tap 1: focus email
        await t.enterText(email, 'user@example.com');
        await t.pump();
        await t.tap(find.text('Send Reset Link')); // tap 2: submit
        await t.pump(const Duration(seconds: 2)); // let the fire-and-forget call settle
      },
    );

    // The golden path is the optimum, so this is the minimum taps for the flow.
    // ignore: avoid_print
    print('GOLDEN flow_request_password_reset -> minimum taps = ${result.taps}');
    expect(result.task, 'flow_request_password_reset');
    expect(result.taps, 2);
  });

  // ---------------------------------------------------------------------------
  // Slide-6 headline flows — templates to confirm & activate.
  // Each needs the flow's real screens wrapped with a router/providers and its
  // services mocked so the happy path completes offline. Replace the drive body
  // with the CONFIRMED minimal step sequence, then delete `skip:`.
  // ---------------------------------------------------------------------------

  testWidgets('golden path — Log in (minimum taps)', (tester) async {
    _suppressOverflow();
    // Mock the auth backend + storage so the happy path completes offline.
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        if (call.method == 'readAll') return <String, String>{};
        if (call.method == 'containsKey') return false;
        return null; // write / read / delete
      },
    );
    ApiService.debugSetHttpClient(MockClient((req) async {
      return http.Response(
        jsonEncode({
          'id': 1,
          'email': 'user@test.com',
          'role': 'PATIENT',
          'token': 'jwt-token',
          'name': 'Test User',
          'emailVerified': true,
        }),
        200,
      );
    }));
    addTearDown(ApiService.debugResetHttpClient);

    final result = await measureGoldenFlow(
      tester,
      name: 'flow_login',
      optimalTaps: 3,
      app: _loginApp(),
      drive: (t) async {
        // Designed minimal path: focus username, focus password, submit.
        final username = find.byType(TextFormField).at(0);
        final password = find.byType(TextFormField).at(1);
        await t.ensureVisible(username);
        await t.tap(username); // tap 1: focus username
        await t.enterText(username, 'user@test.com');
        await t.ensureVisible(password);
        await t.tap(password); // tap 2: focus password
        await t.enterText(password, 'password123');
        await t.pump();
        final signIn = find.widgetWithText(ElevatedButton, 'Sign In');
        await t.ensureVisible(signIn);
        await t.tap(signIn); // tap 3: submit
        // Success makes several async storage round-trips + a delay, then
        // navigates; pump repeatedly so they all resolve before endFlow.
        for (var i = 0; i < 15; i++) {
          await t.pump(const Duration(milliseconds: 200));
        }
      },
    );

    // ignore: avoid_print
    print('GOLDEN flow_login -> minimum taps = ${result.taps}');
    expect(result.task, 'flow_login');
    expect(result.taps, 3);
    // Sanity: the golden path actually completed (login navigated away).
    expect(find.byType(LoginPage), findsNothing);
  });

  testWidgets('golden path — EVV check-in (patient address, minimum taps)',
      (tester) async {
    _suppressOverflow();
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());

    // Storage + connectivity channels the load path touches.
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        if (call.method == 'readAll') return <String, String>{};
        if (call.method == 'containsKey') return false;
        if (call.method == 'read') return 'mock_token';
        return null;
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => call.method == 'check' ? ['wifi'] : null,
    );
    addTearDown(() {
      messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          null);
      messenger.setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/connectivity'), null);
    });

    // Mock the caregiver-patients API so the patient loads (id must match).
    ApiService.debugSetHttpClient(MockClient((req) async {
      return http.Response(
        jsonEncode([
          {
            'id': 1,
            'firstName': 'Jane',
            'lastName': 'Doe',
            'email': 'jane@example.com',
            'phone': '555-0100',
            'dob': '1990-01-01',
            'relationship': 'CHILD',
            'address': {
              'line1': '123 Main St',
              'city': 'Anytown',
              'state': 'MD',
              'zip': '21000',
            },
          }
        ]),
        200,
      );
    }));
    addTearDown(ApiService.debugResetHttpClient);

    final result = await measureGoldenFlow(
      tester,
      name: 'flow_evv_checkin_patient_address',
      optimalTaps: 2,
      app: _checkinApp(),
      drive: (t) async {
        // Wait for the async patient load to render the loaded UI.
        for (var i = 0; i < 8; i++) {
          await t.pump(const Duration(milliseconds: 500));
        }
        // Designed minimal (patient-address) path: the no-GPS reason dropdown
        // pre-fills HOME_VISIT_ADDRESS_USED, so it's just: select address, confirm.
        final selectBtn = find.text('Select Patient Address');
        await t.ensureVisible(selectBtn);
        await t.tap(selectBtn); // tap 1: use patient address -> reason dialog
        await t.pump(const Duration(milliseconds: 300));
        await t.tap(find.widgetWithText(ElevatedButton, 'Continue')); // tap 2
        await t.pump();
        await t.pump();
      },
    );

    // ignore: avoid_print
    print('GOLDEN flow_evv_checkin_patient_address -> minimum taps = ${result.taps}');
    expect(result.task, 'flow_evv_checkin_patient_address');
    expect(result.taps, 2);
    // Golden path completed: check-in pushed the visit-progress screen.
    expect(find.text('Visit In Progress Page'), findsOneWidget);
  });

  testWidgets('golden path — Complete visit & submit EVV (minimum taps)',
      (tester) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => call.method == 'readAll' ? <String, String>{} : null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => call.method == 'check' ? ['wifi'] : null,
    );
    addTearDown(() {
      messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          null);
      messenger.setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/connectivity'), null);
    });

    // Patient load (ApiService seam) + EVV submit (ApiServiceOffline seam).
    ApiService.debugSetHttpClient(MockClient((_) async => http.Response(
        jsonEncode([
          {
            'id': 42,
            'firstName': 'Mary',
            'lastName': 'Johnson',
            'email': 'mary@careconnect.com',
            'phone': '555-0100',
            'dob': '1950-01-01',
            'relationship': 'parent',
            'address': {
              'line1': '123 Main St',
              'city': 'Richmond',
              'state': 'VA',
              'zip': '23220',
            },
          }
        ]),
        200)));
    ApiServiceOffline.debugOverrideHttpClient(MockClient((_) async =>
        http.Response(
            jsonEncode({
              'id': 100,
              'serviceType': 'Personal Care',
              'individualName': 'Mary Johnson',
              'caregiverId': 1,
              'status': 'COMPLETED',
              'stateCode': 'VA',
              'dateOfService': '2026-08-01T09:00:00.000',
              'timeIn': '2026-08-01T09:00:00.000',
              'timeOut': '2026-08-01T10:00:00.000',
              'createdAt': '2026-08-01T10:00:00.000',
              'updatedAt': '2026-08-01T10:00:00.000',
            }),
            201)));
    addTearDown(() {
      ApiService.debugResetHttpClient();
      ApiServiceOffline.debugOverrideHttpClient(null);
    });

    final result = await measureGoldenFlow(
      tester,
      name: 'flow_complete_visit',
      optimalTaps: 1,
      app: _visitCompleteApp(),
      drive: (t) async {
        await t.pumpAndSettle(); // patient load + summary render
        // The summary is pre-filled from check-in/out; the only action is submit.
        final completeBtn = find.widgetWithText(FilledButton, 'Complete Visit');
        await t.ensureVisible(completeBtn);
        await t.tap(completeBtn); // tap 1: complete visit & submit EVV record
        await t.pumpAndSettle();
      },
    );

    // ignore: avoid_print
    print('GOLDEN flow_complete_visit -> minimum taps = ${result.taps}');
    expect(result.task, 'flow_complete_visit');
    expect(result.taps, 1);
    expect(find.text('VISIT SUCCESS'), findsOneWidget); // golden path completed
  });

  testWidgets('golden path — Schedule a new visit (minimum taps)',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());

    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => call.method == 'readAll' ? <String, String>{} : null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => call.method == 'check' ? ['wifi'] : null,
    );
    addTearDown(() {
      messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          null);
      messenger.setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/connectivity'), null);
    });

    // One handler for both seams: patients for the dropdown, [] for visit lists,
    // 201 for the create POST.
    Future<http.Response> handler(http.Request req) async {
      if (req.method == 'POST') return http.Response(jsonEncode({'id': 1}), 201);
      if (req.url.toString().toLowerCase().contains('patient')) {
        return http.Response(
            jsonEncode([
              {
                'id': 10,
                'firstName': 'John',
                'lastName': 'Doe',
                'email': 'john@example.com',
                'phone': '555-1234',
                'dob': '1980-01-01',
                'relationship': 'Self',
                'linkStatus': 'ACTIVE',
              }
            ]),
            200);
      }
      return http.Response(jsonEncode([]), 200);
    }

    ApiService.debugSetHttpClient(MockClient(handler));
    ApiServiceOffline.debugOverrideHttpClient(MockClient(handler));
    addTearDown(() {
      ApiService.debugResetHttpClient();
      ApiServiceOffline.debugOverrideHttpClient(null);
    });

    final result = await measureGoldenFlow(
      tester,
      name: 'flow_schedule_visit',
      optimalTaps: 8,
      app: _scheduleApp(),
      drive: (t) async {
        await t.pumpAndSettle();
        await t.tap(find.widgetWithText(FilledButton, 'Schedule New Visit'));
        await t.pumpAndSettle(); // dialog opens + patients load
        // Patient dropdown
        await t.tap(find.byType(DropdownButtonFormField<Patient>));
        await t.pumpAndSettle();
        await t.tap(find.text('John Doe').last);
        await t.pumpAndSettle();
        // Service-type dropdown (first <String> dropdown in the dialog)
        await t.tap(find.byType(DropdownButtonFormField<String>).first);
        await t.pumpAndSettle();
        await t.tap(find.text('Personal Care').last);
        await t.pumpAndSettle();
        // Time picker (tap the '--:-- --' placeholder, accept default time)
        await t.tap(find.text('--:-- --'));
        await t.pumpAndSettle();
        await t.tap(find.text('OK'));
        await t.pumpAndSettle();
        // Submit
        final submit = find.widgetWithText(ElevatedButton, 'Schedule Visit');
        await t.ensureVisible(submit);
        await t.tap(submit);
        await t.pumpAndSettle();
      },
    );

    // ignore: avoid_print
    print('GOLDEN flow_schedule_visit -> minimum taps = ${result.taps}');
    expect(result.task, 'flow_schedule_visit');
    expect(result.taps, 8); // New Visit + patient + service + time(open+OK) + submit
    expect(find.text('Visit scheduled successfully!'), findsWidgets);
  });

  testWidgets('golden path — File an incident report (minimum taps)',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());

    // AuthTokenManager reads the JWT from secure storage on submit; stub it.
    const secureStorage =
        MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, (call) async {
      if (call.method == 'read') return 'test-token';
      if (call.method == 'readAll') return <String, String>{};
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, null));

    ApiService.debugSetHttpClient(MockClient((req) async {
      return http.Response(jsonEncode({'id': 7, 'clientId': 42}), 201);
    }));
    addTearDown(ApiService.debugResetHttpClient);

    final result = await measureGoldenFlow(
      tester,
      name: 'flow_incident_report',
      optimalTaps: 8,
      app: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home:
            IncidentReportWizardScreen(clientId: 42, clientName: 'Mary Johnson'),
      ),
      drive: (t) async {
        // Designed path through the 6-step wizard: select type, fill each
        // required field, advance, and submit. (Text entry is not a tap; the
        // counted taps are the type/action selections, the 5 Next presses, and
        // Submit — 8 in all.)
        Future<void> next() async {
          await t.tap(find.widgetWithText(FilledButton, 'Next'));
          await t.pumpAndSettle();
        }

        await t.tap(find.text('Fall')); // incident type
        await t.pumpAndSettle();
        await next();
        await t.enterText(find.byType(TextField).first, 'Living room');
        await t.pumpAndSettle();
        await next();
        await t.enterText(find.byType(TextField).first, 'Tripped on a rug');
        await t.pumpAndSettle();
        await next();
        await t.tap(find.text('Applied first aid')); // action taken
        await t.pumpAndSettle();
        await next();
        await t.enterText(find.byType(TextField).first, 'Client stable');
        await t.pumpAndSettle();
        await next();
        await t.tap(find.widgetWithText(FilledButton, 'Submit Report')); // submit
        await t.pump();
        await t.pump(const Duration(seconds: 1));
        await t.pump(const Duration(seconds: 1));
      },
    );

    // ignore: avoid_print
    print('GOLDEN flow_incident_report -> minimum taps = ${result.taps}');
    expect(result.task, 'flow_incident_report');
    expect(result.taps, 8);
    // Golden path completed: submit navigated to the detail screen.
    expect(find.byType(IncidentReportDetailScreen), findsOneWidget);
  });

  testWidgets('golden path — Voice command navigation (minimum taps)',
      (tester) async {
    _setupVoiceMocks();
    final result = await measureGoldenFlow(
      tester,
      name: 'flow_voice_navigation',
      optimalTaps: 2,
      app: _voiceApp(),
      drive: (t) async {
        // Designed minimal path: tap mic, speak (mocked), tap Confirm.
        await t.tap(find.byType(FloatingActionButton)); // tap 1: mic
        await t.pump(const Duration(milliseconds: 200));
        await _sendVoiceResult(t, 'take me to calendar'); // speech = not a tap
        await t.pump(const Duration(milliseconds: 100));
        await t.tap(find.byKey(const Key('voice_confirm_btn'))); // tap 2: confirm
        await t.pump();
        await t.pump();
        // Drain the speech-plugin timers so no timer is pending at teardown.
        for (var i = 0; i < 5; i++) {
          await t.pump(const Duration(seconds: 3));
        }
      },
    );

    // ignore: avoid_print
    print('GOLDEN flow_voice_navigation -> minimum taps = ${result.taps}');
    expect(result.task, 'flow_voice_navigation');
    expect(result.taps, 2); // speaking is not a tap; slide 6's "3" was an estimate
    expect(find.text('Calendar Page'), findsOneWidget); // golden path completed

    // Dispose the tree and drain any residual timers.
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(seconds: 3));
    }
  });

  testWidgets('golden path — EVV check-out (patient address, minimum taps)',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());

    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        if (call.method == 'readAll') return <String, String>{};
        if (call.method == 'read') return 'mock_token';
        return null;
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => call.method == 'check' ? ['wifi'] : null,
    );
    addTearDown(() {
      messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          null);
      messenger.setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/connectivity'), null);
    });
    ApiService.debugSetHttpClient(MockClient((_) async => http.Response(
        jsonEncode([
          {
            'id': 1,
            'firstName': 'Jane',
            'lastName': 'Doe',
            'email': 'jane@example.com',
            'phone': '555-0100',
            'dob': '1990-01-01',
            'relationship': 'CHILD',
            'address': {
              'line1': '123 Main St',
              'city': 'Anytown',
              'state': 'MD',
              'zip': '21000',
            },
          }
        ]),
        200)));
    addTearDown(ApiService.debugResetHttpClient);

    final result = await measureGoldenFlow(
      tester,
      name: 'flow_evv_checkout_patient_address',
      optimalTaps: 2,
      app: _checkoutApp(),
      drive: (t) async {
        for (var i = 0; i < 8; i++) {
          await t.pump(const Duration(milliseconds: 500));
        }
        final selectBtn = find.text('Select Patient Address');
        await t.ensureVisible(selectBtn);
        await t.tap(selectBtn); // tap 1: use patient address -> reason dialog
        await t.pump(const Duration(milliseconds: 300));
        await t.tap(find.widgetWithText(ElevatedButton, 'Confirm')); // tap 2
        await t.pump();
        await t.pump();
      },
    );

    // ignore: avoid_print
    print('GOLDEN flow_evv_checkout_patient_address -> minimum taps = ${result.taps}');
    expect(result.task, 'flow_evv_checkout_patient_address');
    expect(result.taps, 2);
    expect(find.text('Visit Complete Page'), findsOneWidget);
  });

  testWidgets('golden path — EVV select patient (minimum taps)', (tester) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());

    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        if (call.method == 'readAll') return <String, String>{};
        if (call.method == 'read') return 'mock_token';
        return null;
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => call.method == 'check' ? ['wifi'] : null,
    );
    addTearDown(() {
      messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          null);
      messenger.setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/connectivity'), null);
    });
    ApiService.debugSetHttpClient(MockClient((_) async => http.Response(
        jsonEncode([
          {
            'id': 1,
            'firstName': 'Jane',
            'lastName': 'Doe',
            'email': 'jane@example.com',
            'phone': '555-0100',
            'dob': '1990-01-01',
            'relationship': 'CHILD',
          }
        ]),
        200)));
    addTearDown(ApiService.debugResetHttpClient);

    final result = await measureGoldenFlow(
      tester,
      name: 'flow_evv_select_patient',
      optimalTaps: 1,
      app: _selectPatientApp(),
      drive: (t) async {
        for (var i = 0; i < 8; i++) {
          await t.pump(const Duration(milliseconds: 500));
        }
        final patientCard = find.text('Jane Doe').first;
        await t.ensureVisible(patientCard);
        await t.tap(patientCard); // tap 1: select patient -> start visit
        await t.pumpAndSettle();
      },
    );

    // ignore: avoid_print
    print('GOLDEN flow_evv_select_patient -> minimum taps = ${result.taps}');
    expect(result.task, 'flow_evv_select_patient');
    expect(result.taps, 1);
    expect(find.text('Start Visit Page'), findsOneWidget);
  });
}
