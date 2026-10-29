// Page-title tests for CaregiverDashboard (lib/features/dashboard/presentation/pages/caregiver_dashboard.dart).
// Setup copied from caregiver_dashboard_test.dart; adds the page-title
// checks (WCAG 2.4.2) for this PR's TitledMaterialPageRoute changes.

import 'dart:convert';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/dashboard/presentation/pages/caregiver_dashboard.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import '../../../../mock_user_provider.dart';
import '../../../../helpers/titled_route_probe.dart';

Future<void> _pumpWithLargeScreen(WidgetTester tester, Widget widget) async {
  tester.view.physicalSize = const Size(1800, 1400);
  tester.view.devicePixelRatio = 1.0;
  final origHandler = FlutterError.onError;
  FlutterError.onError = (details) {
    final msg = details.exceptionAsString();
    if (msg.contains('overflowed') || msg.contains('overflow')) return;
    origHandler?.call(details);
  };
  addTearDown(() {
    FlutterError.onError = origHandler;
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(widget);
}

/// Builds a widget tree with GoRouter, UserProvider, and optional HTTP mock.
Widget _buildTestWidget({
  UserProvider? provider,
  String initialLocation = '/dash',
  List<GoRoute>? extraRoutes,
}) {
  final userProvider = provider ??
      MockUserProvider(
        mockUser: MockUser(
          id: 1,
          email: 'cg@example.com',
          role: 'CAREGIVER',
          token: 'test-token',
          name: 'Test Caregiver',
          caregiverId: 1,
        ),
      );

  final routes = <GoRoute>[
    GoRoute(path: '/', builder: (_, __) => const Scaffold()),
    GoRoute(
      path: '/dash',
      builder: (_, __) => const CaregiverDashboard(),
    ),
    GoRoute(path: '/login', builder: (_, __) => const Scaffold(body: Text('Login Page'))),
    GoRoute(
      path: '/analytics',
      builder: (_, __) => const Scaffold(body: Text('Analytics Page')),
    ),
    GoRoute(
      path: '/patient/:id',
      builder: (_, state) => Scaffold(body: Text('Patient ${state.pathParameters["id"]}')),
    ),
    GoRoute(
      path: '/add-patient',
      builder: (_, __) => const Scaffold(body: Text('Add Patient Page')),
    ),
    GoRoute(
      path: '/evv/select-patient',
      builder: (_, __) => const Scaffold(body: Text('Select Patient')),
    ),
    ...(extraRoutes ?? []),
  ];

  final router = GoRouter(observers: [probe], 
    initialLocation: initialLocation,
    routes: routes,
  );

  return ChangeNotifierProvider<UserProvider>.value(
    value: userProvider,
    child: MaterialApp.router(locale: Locale('en'), localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, routerConfig: router),
  );
}

/// Returns a MockClient that returns the given patient list JSON for the
/// caregivers/X/patients endpoint and optional enhanced profile data.
MockClient _mockHttpClient({
  int statusCode = 200,
  List<Map<String, dynamic>>? patientList,
  Map<String, dynamic>? enhancedProfile,
  int enhancedStatusCode = 200,
}) {
  return MockClient((request) async {
    final uri = request.url.toString();

    // Match enhanced profile requests
    if (uri.contains('/profile/enhanced')) {
      final body = enhancedProfile ?? {
        'data': {
          'allergies': [],
          'latestVitals': {},
          'medications': [],
        },
      };
      return http.Response(jsonEncode(body), enhancedStatusCode);
    }

    // Match patient list requests
    if (uri.contains('caregivers/') && uri.contains('/patients')) {
      final body = patientList ?? [];
      return http.Response(jsonEncode(body), statusCode);
    }

    // Match messaging/notification/subscription endpoints
    if (uri.contains('messaging') || uri.contains('subscription') || uri.contains('links')) {
      return http.Response('{"success": true}', 200);
    }

    // Default
    return http.Response('{}', 200);
  });
}

TitledRouteProbe probe = TitledRouteProbe();

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => call.method == 'check' ? ['wifi'] : null,
    );
  });

  final patients = [
    {
      'id': 10,
      'firstName': 'John',
      'lastName': 'Doe',
      'email': 'john@example.com',
      'phone': '555-1234',
      'dob': '01/15/1960',
      'gender': 'Male',
      'relationship': 'Parent',
      'linkId': 100,
      'linkStatus': 'ACTIVE',
    },
  ];

  for (final (button, title) in [
    ('Video Call', 'Video Call'),
    ('Message', 'Messages'),
    ('Medical Notes', 'Patient Medical Notes'),
  ]) {
    testWidgets('$button opens a page titled "$title"', (tester) async {
      probe = TitledRouteProbe();
      await http.runWithClient(() async {
        // Admins skip the caregiver premium check before a call.
        await _pumpWithLargeScreen(
            tester,
            _buildTestWidget(
              provider: MockUserProvider(
                mockUser: MockUser(
                    id: 1, role: 'ADMIN', token: 'test-token', caregiverId: 1),
              ),
            ));
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        // The action buttons scroll sideways; bring this one on screen.
        await tester.ensureVisible(find.text(button).first);
        await tester.pump();
        expect(
            await probe.tapAndReadTitle(tester, find.text(button).first),
            title);
      }, () => _mockHttpClient(patientList: patients));
    });
  }
}
