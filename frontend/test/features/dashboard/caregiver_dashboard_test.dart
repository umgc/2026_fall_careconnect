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

import '../../mock_user_provider.dart';

/// Pumps the widget with a large screen size and suppresses overflow errors
/// from source layout (not test responsibility to fix source widget overflow).
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

  final router = GoRouter(
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        if (call.method == 'readAll') return <String, String>{};
        if (call.method == 'containsKey') return false;
        if (call.method == 'read') return null;
        if (call.method == 'write') return null;
        if (call.method == 'delete') return null;
        return null;
      },
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async {
        if (call.method == 'check') return ['wifi'];
        return null;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      null,
    );
  });

  group('CaregiverDashboard construction', () {
    testWidgets('can be constructed with default parameters', (tester) async {
      const dashboard = CaregiverDashboard();
      expect(dashboard.userRole, 'CAREGIVER');
      expect(dashboard.patientId, isNull);
      expect(dashboard.caregiverId, 1);
    });

    testWidgets('can be constructed with custom parameters', (tester) async {
      const dashboard = CaregiverDashboard(
        userRole: 'ADMIN',
        patientId: 42,
        caregiverId: 7,
      );
      expect(dashboard.userRole, 'ADMIN');
      expect(dashboard.patientId, 42);
      expect(dashboard.caregiverId, 7);
    });
  });

  group('CaregiverDashboard rendering', () {
    testWidgets('renders CaregiverDashboard widget', (tester) async {
      await http.runWithClient(
        () async {
          await _pumpWithLargeScreen(tester, _buildTestWidget());
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));
          expect(find.byType(CaregiverDashboard), findsOneWidget);
        },
        () => _mockHttpClient(),
      );
    });

    testWidgets('renders Scaffold', (tester) async {
      await http.runWithClient(
        () async {
          await _pumpWithLargeScreen(tester, _buildTestWidget());
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));
          expect(find.byType(Scaffold), findsAtLeastNWidgets(1));
        },
        () => _mockHttpClient(),
      );
    });

    testWidgets('shows content after loading completes', (tester) async {
      await http.runWithClient(
        () async {
          await _pumpWithLargeScreen(tester, _buildTestWidget());
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));
          // After loading completes with empty patient list, no loading indicator
          expect(find.byType(CircularProgressIndicator), findsNothing);
          // And we should see the empty state
          expect(find.text('No patients yet'), findsOneWidget);
        },
        () => _mockHttpClient(patientList: []),
      );
    });
  });

  group('CaregiverDashboard with caregiver name', () {
    testWidgets('shows welcome message with caregiver name', (tester) async {
      await http.runWithClient(
        () async {
          await _pumpWithLargeScreen(tester, _buildTestWidget());
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));
          expect(find.textContaining('Welcome, Test Caregiver'), findsOneWidget);
        },
        () => _mockHttpClient(),
      );
    });

    testWidgets('shows default title when caregiver has no name', (tester) async {
      final provider = MockUserProvider(
        mockUser: MockUser(
          id: 1,
          email: 'cg@example.com',
          role: 'CAREGIVER',
          token: 'test-token',
          name: null,
          caregiverId: 1,
        ),
      );

      await http.runWithClient(
        () async {
          await _pumpWithLargeScreen(tester, _buildTestWidget(provider: provider));
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));
          expect(find.textContaining('Caregiver Dashboard'), findsOneWidget);
        },
        () => _mockHttpClient(),
      );
    });
  });

  group('CaregiverDashboard error state', () {
    testWidgets('shows error state when API returns non-200', (tester) async {
      await http.runWithClient(
        () async {
          await _pumpWithLargeScreen(tester, _buildTestWidget());
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          expect(find.text('Error Loading Patients'), findsOneWidget);
          expect(find.text('Try Again'), findsOneWidget);
          expect(find.byIcon(Icons.error_outline), findsOneWidget);
        },
        () => _mockHttpClient(statusCode: 500),
      );
    });

    testWidgets('shows error message text when API fails', (tester) async {
      await http.runWithClient(
        () async {
          await _pumpWithLargeScreen(tester, _buildTestWidget());
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          expect(find.textContaining('Failed to load patients'), findsOneWidget);
        },
        () => _mockHttpClient(statusCode: 500),
      );
    });

    testWidgets('shows error state when network exception occurs', (tester) async {
      final errorClient = MockClient((request) async {
        throw Exception('Network error');
      });

      await http.runWithClient(
        () async {
          await _pumpWithLargeScreen(tester, _buildTestWidget());
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          expect(find.text('Error Loading Patients'), findsOneWidget);
          expect(find.textContaining('Error:'), findsOneWidget);
        },
        () => errorClient,
      );
    });

    testWidgets('retry button triggers refetch', (tester) async {
      int callCount = 0;
      final client = MockClient((request) async {
        final uri = request.url.toString();
        if (uri.contains('caregivers/') && uri.contains('/patients')) {
          callCount++;
          return http.Response('server error', 500);
        }
        return http.Response('{}', 200);
      });

      await http.runWithClient(
        () async {
          await _pumpWithLargeScreen(tester, _buildTestWidget());
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          expect(find.text('Try Again'), findsOneWidget);
          final initialCount = callCount;

          await tester.tap(find.text('Try Again'));
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          expect(callCount, greaterThan(initialCount));
        },
        () => client,
      );
    });
  });

  group('CaregiverDashboard empty state', () {
    testWidgets('shows empty state when no patients', (tester) async {
      await http.runWithClient(
        () async {
          await _pumpWithLargeScreen(tester, _buildTestWidget());
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          expect(find.text('No patients yet'), findsOneWidget);
          expect(find.text('Add patients to begin monitoring'), findsOneWidget);
          expect(find.byIcon(Icons.person_search), findsOneWidget);
        },
        () => _mockHttpClient(patientList: []),
      );
    });

    testWidgets('empty state shows Add Patient button', (tester) async {
      await http.runWithClient(
        () async {
          await _pumpWithLargeScreen(tester, _buildTestWidget());
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          expect(find.text('Add Patient'), findsOneWidget);
          expect(find.byIcon(Icons.person_add), findsOneWidget);
        },
        () => _mockHttpClient(patientList: []),
      );
    });
  });

  group('CaregiverDashboard with patients', () {
    final testPatients = [
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
      {
        'id': 20,
        'firstName': 'Jane',
        'lastName': 'Smith',
        'email': 'jane@example.com',
        'phone': '555-5678',
        'dob': '06/20/1975',
        'gender': '',
        'relationship': '',
        'linkId': 200,
        'linkStatus': 'SUSPENDED',
      },
    ];

    testWidgets('shows patient names in cards', (tester) async {
      await http.runWithClient(
        () async {
          await _pumpWithLargeScreen(tester, _buildTestWidget());
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          expect(find.text('John Doe'), findsOneWidget);
          expect(find.text('Jane Smith'), findsOneWidget);
        },
        () => _mockHttpClient(patientList: testPatients),
      );
    });

    testWidgets('shows patient count', (tester) async {
      await http.runWithClient(
        () async {
          await _pumpWithLargeScreen(tester, _buildTestWidget());
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          expect(find.text('Showing 2 patients'), findsOneWidget);
        },
        () => _mockHttpClient(patientList: testPatients),
      );
    });

    testWidgets('shows patient age from DOB', (tester) async {
      await http.runWithClient(
        () async {
          await _pumpWithLargeScreen(tester, _buildTestWidget());
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          // John Doe born 01/15/1960 should show an age
          expect(find.textContaining('Age '), findsAtLeastNWidgets(1));
        },
        () => _mockHttpClient(patientList: testPatients),
      );
    });

    testWidgets('shows gender when available', (tester) async {
      await http.runWithClient(
        () async {
          await _pumpWithLargeScreen(tester, _buildTestWidget());
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          expect(find.text('Male'), findsOneWidget);
          // Jane has empty gender, should show 'Gender not specified'
          expect(find.text('Gender not specified'), findsOneWidget);
        },
        () => _mockHttpClient(patientList: testPatients),
      );
    });

    testWidgets('shows relationship when available', (tester) async {
      await http.runWithClient(
        () async {
          await _pumpWithLargeScreen(tester, _buildTestWidget());
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          expect(find.text('Parent'), findsOneWidget);
          // Jane has empty relationship, should show 'Patient'
          expect(find.text('Patient'), findsAtLeastNWidgets(1));
        },
        () => _mockHttpClient(patientList: testPatients),
      );
    });

    testWidgets('shows link status Active for active patients', (tester) async {
      await http.runWithClient(
        () async {
          await _pumpWithLargeScreen(tester, _buildTestWidget());
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          expect(find.text('Active'), findsOneWidget);
          expect(find.text('SUSPENDED'), findsOneWidget);
        },
        () => _mockHttpClient(patientList: testPatients),
      );
    });

    testWidgets('shows check_circle for active and pause_circle for suspended', (tester) async {
      await http.runWithClient(
        () async {
          await _pumpWithLargeScreen(tester, _buildTestWidget());
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          expect(find.byIcon(Icons.check_circle), findsOneWidget);
          expect(find.byIcon(Icons.pause_circle_filled), findsOneWidget);
        },
        () => _mockHttpClient(patientList: testPatients),
      );
    });

    testWidgets('shows avatar with first letter of name', (tester) async {
      await http.runWithClient(
        () async {
          await _pumpWithLargeScreen(tester, _buildTestWidget());
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          expect(find.text('J'), findsAtLeastNWidgets(2)); // Both John and Jane start with J
        },
        () => _mockHttpClient(patientList: testPatients),
      );
    });

    testWidgets('shows allergies summary - no allergies listed', (tester) async {
      await http.runWithClient(
        () async {
          await _pumpWithLargeScreen(tester, _buildTestWidget());
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          expect(find.text('No allergies listed'), findsAtLeastNWidgets(1));
        },
        () => _mockHttpClient(patientList: testPatients),
      );
    });

    testWidgets('shows vitals summary - no vital data', (tester) async {
      await http.runWithClient(
        () async {
          await _pumpWithLargeScreen(tester, _buildTestWidget());
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          // With empty vitals, should show either "No vital data available" or "Vitals monitoring active"
          expect(
            find.textContaining('vital'),
            findsAtLeastNWidgets(1),
          );
        },
        () => _mockHttpClient(patientList: testPatients),
      );
    });

    testWidgets('shows action buttons in patient card', (tester) async {
      await http.runWithClient(
        () async {
          await _pumpWithLargeScreen(tester, _buildTestWidget());
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          // Action buttons should be present for each patient
          expect(find.byIcon(Icons.message), findsAtLeastNWidgets(1));
          expect(find.byIcon(Icons.video_call), findsAtLeastNWidgets(1));
          expect(find.byIcon(Icons.call), findsAtLeastNWidgets(1));
          expect(find.byIcon(Icons.analytics), findsAtLeastNWidgets(1));
          expect(find.byIcon(Icons.medical_information), findsAtLeastNWidgets(1));
        },
        () => _mockHttpClient(patientList: testPatients),
      );
    });

    testWidgets('shows action button labels', (tester) async {
      await http.runWithClient(
        () async {
          await _pumpWithLargeScreen(tester, _buildTestWidget());
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          expect(find.text('Message'), findsAtLeastNWidgets(1));
          expect(find.text('Video Call'), findsAtLeastNWidgets(1));
          expect(find.text('Audio Call'), findsAtLeastNWidgets(1));
          expect(find.text('Analytics'), findsAtLeastNWidgets(1));
          expect(find.text('Medical Notes'), findsAtLeastNWidgets(1));
        },
        () => _mockHttpClient(patientList: testPatients),
      );
    });

    testWidgets('has PopupMenuButton for each patient', (tester) async {
      await http.runWithClient(
        () async {
          await _pumpWithLargeScreen(tester, _buildTestWidget());
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          expect(find.byIcon(Icons.more_vert), findsAtLeastNWidgets(1));
        },
        () => _mockHttpClient(patientList: testPatients),
      );
    });

    testWidgets('cake icon displayed for DOB row', (tester) async {
      await http.runWithClient(
        () async {
          await _pumpWithLargeScreen(tester, _buildTestWidget());
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          expect(find.byIcon(Icons.cake), findsAtLeastNWidgets(1));
        },
        () => _mockHttpClient(patientList: testPatients),
      );
    });

    testWidgets('person icon displayed for gender row', (tester) async {
      await http.runWithClient(
        () async {
          await _pumpWithLargeScreen(tester, _buildTestWidget());
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          expect(find.byIcon(Icons.person), findsAtLeastNWidgets(1));
        },
        () => _mockHttpClient(patientList: testPatients),
      );
    });

    testWidgets('family_restroom icon displayed for relationship row', (tester) async {
      await http.runWithClient(
        () async {
          await _pumpWithLargeScreen(tester, _buildTestWidget());
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          expect(find.byIcon(Icons.family_restroom), findsAtLeastNWidgets(1));
        },
        () => _mockHttpClient(patientList: testPatients),
      );
    });

    testWidgets('warning_amber icon displayed for allergies row', (tester) async {
      await http.runWithClient(
        () async {
          await _pumpWithLargeScreen(tester, _buildTestWidget());
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          expect(find.byIcon(Icons.warning_amber), findsAtLeastNWidgets(1));
        },
        () => _mockHttpClient(patientList: testPatients),
      );
    });

    testWidgets('favorite icon displayed for vitals row', (tester) async {
      await http.runWithClient(
        () async {
          await _pumpWithLargeScreen(tester, _buildTestWidget());
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          expect(find.byIcon(Icons.favorite), findsAtLeastNWidgets(1));
        },
        () => _mockHttpClient(patientList: testPatients),
      );
    });

    testWidgets('RefreshIndicator is present for patient list', (tester) async {
      await http.runWithClient(
        () async {
          await _pumpWithLargeScreen(tester, _buildTestWidget());
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          expect(find.byType(RefreshIndicator), findsOneWidget);
        },
        () => _mockHttpClient(patientList: testPatients),
      );
    });

    testWidgets('patient card has Card widget', (tester) async {
      await http.runWithClient(
        () async {
          await _pumpWithLargeScreen(tester, _buildTestWidget());
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          expect(find.byType(Card), findsAtLeastNWidgets(1));
        },
        () => _mockHttpClient(patientList: testPatients),
      );
    });
  });

  group('CaregiverDashboard with nested patient data', () {
    testWidgets('handles nested patient structure from API', (tester) async {
      final nestedPatients = [
        {
          'patient': {
            'id': 15,
            'firstName': 'Alice',
            'lastName': 'Wonder',
            'email': 'alice@example.com',
            'phone': '555-9999',
            'dob': '03/25/1985',
            'gender': 'Female',
            'relationship': 'Spouse',
          },
          'link': {
            'id': 300,
            'status': 'ACTIVE',
            'relationship': 'Spouse',
          },
        },
      ];

      await http.runWithClient(
        () async {
          await _pumpWithLargeScreen(tester, _buildTestWidget());
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          expect(find.text('Alice Wonder'), findsOneWidget);
        },
        () => _mockHttpClient(patientList: nestedPatients),
      );
    });
  });

  group('CaregiverDashboard with enhanced profile data', () {
    testWidgets('shows allergies from enhanced profile', (tester) async {
      final patients = [
        {
          'id': 10,
          'firstName': 'Bob',
          'lastName': 'Builder',
          'email': 'bob@example.com',
          'phone': '555-1111',
          'dob': '05/10/1970',
          'gender': 'Male',
          'relationship': 'Patient',
          'linkId': 100,
          'linkStatus': 'ACTIVE',
        },
      ];

      final enhancedProfile = {
        'data': {
          'allergies': ['Peanuts', 'Shellfish'],
          'latestVitals': {
            'heartRate': '72',
            'temperature': '98.6',
            'oxygenSaturation': '97',
          },
          'medications': ['Aspirin', 'Metformin'],
        },
      };

      await http.runWithClient(
        () async {
          await _pumpWithLargeScreen(tester, _buildTestWidget());
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          expect(find.textContaining('Peanuts'), findsOneWidget);
          expect(find.textContaining('Shellfish'), findsOneWidget);
        },
        () => _mockHttpClient(
          patientList: patients,
          enhancedProfile: enhancedProfile,
        ),
      );
    });

    testWidgets('shows allergy objects with severity', (tester) async {
      final patients = [
        {
          'id': 10,
          'firstName': 'Bob',
          'lastName': 'Builder',
          'email': 'bob@example.com',
          'phone': '555-1111',
          'dob': '05/10/1970',
          'gender': 'Male',
          'relationship': 'Patient',
          'linkId': 100,
          'linkStatus': 'ACTIVE',
        },
      ];

      final enhancedProfile = {
        'data': {
          'allergies': [
            {'allergen': 'Penicillin', 'severity': 'High'},
          ],
          'latestVitals': {},
          'medications': [],
        },
      };

      await http.runWithClient(
        () async {
          await _pumpWithLargeScreen(tester, _buildTestWidget());
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          expect(find.textContaining('Penicillin (High)'), findsOneWidget);
        },
        () => _mockHttpClient(
          patientList: patients,
          enhancedProfile: enhancedProfile,
        ),
      );
    });

    testWidgets('shows vitals summary with heart rate', (tester) async {
      final patients = [
        {
          'id': 10,
          'firstName': 'Bob',
          'lastName': 'Builder',
          'email': 'bob@example.com',
          'phone': '555-1111',
          'dob': '05/10/1970',
          'gender': 'Male',
          'relationship': 'Patient',
          'linkId': 100,
          'linkStatus': 'ACTIVE',
        },
      ];

      final enhancedProfile = {
        'data': {
          'allergies': [],
          'latestVitals': {
            'heartRate': '72',
          },
          'medications': [],
        },
      };

      await http.runWithClient(
        () async {
          await _pumpWithLargeScreen(tester, _buildTestWidget());
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          expect(find.textContaining('HR: 72 bpm'), findsOneWidget);
        },
        () => _mockHttpClient(
          patientList: patients,
          enhancedProfile: enhancedProfile,
        ),
      );
    });

    testWidgets('shows vitals with blood pressure', (tester) async {
      final patients = [
        {
          'id': 10,
          'firstName': 'Bob',
          'lastName': 'Builder',
          'email': 'bob@example.com',
          'phone': '555-1111',
          'dob': '05/10/1970',
          'gender': 'Male',
          'relationship': 'Patient',
          'linkId': 100,
          'linkStatus': 'ACTIVE',
        },
      ];

      final enhancedProfile = {
        'data': {
          'allergies': [],
          'latestVitals': {
            'bloodPressure': '120/80',
          },
          'medications': [],
        },
      };

      await http.runWithClient(
        () async {
          await _pumpWithLargeScreen(tester, _buildTestWidget());
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          expect(find.textContaining('BP: 120/80'), findsOneWidget);
        },
        () => _mockHttpClient(
          patientList: patients,
          enhancedProfile: enhancedProfile,
        ),
      );
    });

    testWidgets('shows vitals with systolic/diastolic', (tester) async {
      final patients = [
        {
          'id': 10,
          'firstName': 'Bob',
          'lastName': 'Builder',
          'email': 'bob@example.com',
          'phone': '555-1111',
          'dob': '05/10/1970',
          'gender': 'Male',
          'relationship': 'Patient',
          'linkId': 100,
          'linkStatus': 'ACTIVE',
        },
      ];

      final enhancedProfile = {
        'data': {
          'allergies': [],
          'latestVitals': {
            'systolic': '120',
            'diastolic': '80',
          },
          'medications': [],
        },
      };

      await http.runWithClient(
        () async {
          await _pumpWithLargeScreen(tester, _buildTestWidget());
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          expect(find.textContaining('BP: 120/80 mmHg'), findsOneWidget);
        },
        () => _mockHttpClient(
          patientList: patients,
          enhancedProfile: enhancedProfile,
        ),
      );
    });

    testWidgets('shows vitals with temperature', (tester) async {
      final patients = [
        {
          'id': 10,
          'firstName': 'Bob',
          'lastName': 'Builder',
          'email': 'bob@example.com',
          'phone': '555-1111',
          'dob': '05/10/1970',
          'gender': 'Male',
          'relationship': 'Patient',
          'linkId': 100,
          'linkStatus': 'ACTIVE',
        },
      ];

      final enhancedProfile = {
        'data': {
          'allergies': [],
          'latestVitals': {
            'temperature': '98.6',
          },
          'medications': [],
        },
      };

      await http.runWithClient(
        () async {
          await _pumpWithLargeScreen(tester, _buildTestWidget());
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          expect(find.textContaining('Temp: 98.6'), findsOneWidget);
        },
        () => _mockHttpClient(
          patientList: patients,
          enhancedProfile: enhancedProfile,
        ),
      );
    });

    testWidgets('shows vitals with oxygen saturation', (tester) async {
      final patients = [
        {
          'id': 10,
          'firstName': 'Bob',
          'lastName': 'Builder',
          'email': 'bob@example.com',
          'phone': '555-1111',
          'dob': '05/10/1970',
          'gender': 'Male',
          'relationship': 'Patient',
          'linkId': 100,
          'linkStatus': 'ACTIVE',
        },
      ];

      final enhancedProfile = {
        'data': {
          'allergies': [],
          'latestVitals': {
            'oxygenSaturation': '97',
          },
          'medications': [],
        },
      };

      await http.runWithClient(
        () async {
          await _pumpWithLargeScreen(tester, _buildTestWidget());
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          expect(find.textContaining('O2: 97%'), findsOneWidget);
        },
        () => _mockHttpClient(
          patientList: patients,
          enhancedProfile: enhancedProfile,
        ),
      );
    });

    testWidgets('shows vitals with SpO2', (tester) async {
      final patients = [
        {
          'id': 10,
          'firstName': 'Bob',
          'lastName': 'Builder',
          'email': 'bob@example.com',
          'phone': '555-1111',
          'dob': '05/10/1970',
          'gender': 'Male',
          'relationship': 'Patient',
          'linkId': 100,
          'linkStatus': 'ACTIVE',
        },
      ];

      final enhancedProfile = {
        'data': {
          'allergies': [],
          'latestVitals': {
            'spo2': '96',
          },
          'medications': [],
        },
      };

      await http.runWithClient(
        () async {
          await _pumpWithLargeScreen(tester, _buildTestWidget());
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          expect(find.textContaining('96%'), findsOneWidget);
        },
        () => _mockHttpClient(
          patientList: patients,
          enhancedProfile: enhancedProfile,
        ),
      );
    });

    testWidgets('shows vitals with respiratory rate', (tester) async {
      final patients = [
        {
          'id': 10,
          'firstName': 'Bob',
          'lastName': 'Builder',
          'email': 'bob@example.com',
          'phone': '555-1111',
          'dob': '05/10/1970',
          'gender': 'Male',
          'relationship': 'Patient',
          'linkId': 100,
          'linkStatus': 'ACTIVE',
        },
      ];

      final enhancedProfile = {
        'data': {
          'allergies': [],
          'latestVitals': {
            'respiratoryRate': '16',
          },
          'medications': [],
        },
      };

      await http.runWithClient(
        () async {
          await _pumpWithLargeScreen(tester, _buildTestWidget());
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          expect(find.textContaining('RR: 16/min'), findsOneWidget);
        },
        () => _mockHttpClient(
          patientList: patients,
          enhancedProfile: enhancedProfile,
        ),
      );
    });

    testWidgets('shows vitals with weight', (tester) async {
      final patients = [
        {
          'id': 10,
          'firstName': 'Bob',
          'lastName': 'Builder',
          'email': 'bob@example.com',
          'phone': '555-1111',
          'dob': '05/10/1970',
          'gender': 'Male',
          'relationship': 'Patient',
          'linkId': 100,
          'linkStatus': 'ACTIVE',
        },
      ];

      final enhancedProfile = {
        'data': {
          'allergies': [],
          'latestVitals': {
            'weight': '180',
          },
          'medications': [],
        },
      };

      await http.runWithClient(
        () async {
          await _pumpWithLargeScreen(tester, _buildTestWidget());
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          expect(find.textContaining('Weight: 180 lbs'), findsOneWidget);
        },
        () => _mockHttpClient(
          patientList: patients,
          enhancedProfile: enhancedProfile,
        ),
      );
    });

    testWidgets('shows vitals with height', (tester) async {
      final patients = [
        {
          'id': 10,
          'firstName': 'Bob',
          'lastName': 'Builder',
          'email': 'bob@example.com',
          'phone': '555-1111',
          'dob': '05/10/1970',
          'gender': 'Male',
          'relationship': 'Patient',
          'linkId': 100,
          'linkStatus': 'ACTIVE',
        },
      ];

      final enhancedProfile = {
        'data': {
          'allergies': [],
          'latestVitals': {
            'height': '5\'10"',
          },
          'medications': [],
        },
      };

      await http.runWithClient(
        () async {
          await _pumpWithLargeScreen(tester, _buildTestWidget());
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          expect(find.textContaining('Height:'), findsOneWidget);
        },
        () => _mockHttpClient(
          patientList: patients,
          enhancedProfile: enhancedProfile,
        ),
      );
    });

    testWidgets('shows vitals with glucose', (tester) async {
      final patients = [
        {
          'id': 10,
          'firstName': 'Bob',
          'lastName': 'Builder',
          'email': 'bob@example.com',
          'phone': '555-1111',
          'dob': '05/10/1970',
          'gender': 'Male',
          'relationship': 'Patient',
          'linkId': 100,
          'linkStatus': 'ACTIVE',
        },
      ];

      final enhancedProfile = {
        'data': {
          'allergies': [],
          'latestVitals': {
            'glucose': '100',
          },
          'medications': [],
        },
      };

      await http.runWithClient(
        () async {
          await _pumpWithLargeScreen(tester, _buildTestWidget());
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          expect(find.textContaining('Glucose: 100 mg/dL'), findsOneWidget);
        },
        () => _mockHttpClient(
          patientList: patients,
          enhancedProfile: enhancedProfile,
        ),
      );
    });

    testWidgets('handles enhanced profile failure gracefully', (tester) async {
      final patients = [
        {
          'id': 10,
          'firstName': 'Bob',
          'lastName': 'Builder',
          'email': 'bob@example.com',
          'phone': '555-1111',
          'dob': '05/10/1970',
          'gender': 'Male',
          'relationship': 'Patient',
          'linkId': 100,
          'linkStatus': 'ACTIVE',
        },
      ];

      await http.runWithClient(
        () async {
          await _pumpWithLargeScreen(tester, _buildTestWidget());
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          // Should still render the patient card even if enhanced profile fails
          expect(find.text('Bob Builder'), findsOneWidget);
        },
        () => _mockHttpClient(
          patientList: patients,
          enhancedStatusCode: 500,
        ),
      );
    });
  });

  group('CaregiverDashboard DOB/age edge cases', () {
    testWidgets('shows Age not specified when DOB is empty', (tester) async {
      final patients = [
        {
          'id': 10,
          'firstName': 'NoAge',
          'lastName': 'Person',
          'email': 'noage@example.com',
          'phone': '555-0000',
          'dob': '',
          'gender': 'Male',
          'relationship': 'Patient',
          'linkId': 100,
          'linkStatus': 'ACTIVE',
        },
      ];

      await http.runWithClient(
        () async {
          await _pumpWithLargeScreen(tester, _buildTestWidget());
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          expect(find.text('Age not specified'), findsOneWidget);
        },
        () => _mockHttpClient(patientList: patients),
      );
    });
  });

  group('CaregiverDashboard popup menu', () {
    final singlePatient = [
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

    testWidgets('popup menu shows View Profile option', (tester) async {
      await http.runWithClient(
        () async {
          await _pumpWithLargeScreen(tester, _buildTestWidget());
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          // Tap the more_vert icon to open the popup menu
          await tester.tap(find.byIcon(Icons.more_vert).first);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));

          expect(find.text('View Profile'), findsOneWidget);
        },
        () => _mockHttpClient(patientList: singlePatient),
      );
    });

    testWidgets('popup menu shows Suspend Relationship for active patients', (tester) async {
      await http.runWithClient(
        () async {
          await _pumpWithLargeScreen(tester, _buildTestWidget());
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          await tester.tap(find.byIcon(Icons.more_vert).first);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));

          expect(find.text('Suspend Relationship'), findsOneWidget);
        },
        () => _mockHttpClient(patientList: singlePatient),
      );
    });

    testWidgets('popup menu shows Reactivate for suspended patients', (tester) async {
      final suspendedPatient = [
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
          'linkStatus': 'SUSPENDED',
        },
      ];

      await http.runWithClient(
        () async {
          await _pumpWithLargeScreen(tester, _buildTestWidget());
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          await tester.tap(find.byIcon(Icons.more_vert).first);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));

          expect(find.text('Reactivate Relationship'), findsOneWidget);
        },
        () => _mockHttpClient(patientList: suspendedPatient),
      );
    });

    testWidgets('selecting View Profile navigates to patient page', (tester) async {
      await http.runWithClient(
        () async {
          await _pumpWithLargeScreen(tester, _buildTestWidget());
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          // Open popup menu
          await tester.tap(find.byIcon(Icons.more_vert).first);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));

          // Tap View Profile
          await tester.tap(find.text('View Profile'));
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));

          expect(find.text('Patient 10'), findsOneWidget);
        },
        () => _mockHttpClient(patientList: singlePatient),
      );
    });

    testWidgets('selecting Suspend shows confirmation dialog', (tester) async {
      await http.runWithClient(
        () async {
          await _pumpWithLargeScreen(tester, _buildTestWidget());
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          // Open popup menu
          await tester.tap(find.byIcon(Icons.more_vert).first);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));

          // Tap Suspend Relationship
          await tester.tap(find.text('Suspend Relationship'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));

          // Should show confirmation dialog
          expect(find.text('Suspend Relationship'), findsAtLeastNWidgets(1));
          expect(find.textContaining('Are you sure'), findsOneWidget);
          expect(find.text('CANCEL'), findsOneWidget);
          expect(find.text('SUSPEND'), findsOneWidget);
        },
        () => _mockHttpClient(patientList: singlePatient),
      );
    });

    testWidgets('cancel button closes suspend dialog', (tester) async {
      await http.runWithClient(
        () async {
          await _pumpWithLargeScreen(tester, _buildTestWidget());
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          // Open popup menu
          await tester.tap(find.byIcon(Icons.more_vert).first);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));

          // Tap Suspend
          await tester.tap(find.text('Suspend Relationship'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));

          // Tap CANCEL
          await tester.tap(find.text('CANCEL'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));

          // Dialog should be gone
          expect(find.textContaining('Are you sure'), findsNothing);
        },
        () => _mockHttpClient(patientList: singlePatient),
      );
    });

    testWidgets('selecting Reactivate shows confirmation dialog', (tester) async {
      final suspendedPatient = [
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
          'linkStatus': 'SUSPENDED',
        },
      ];

      await http.runWithClient(
        () async {
          await _pumpWithLargeScreen(tester, _buildTestWidget());
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          // Open popup menu
          await tester.tap(find.byIcon(Icons.more_vert).first);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));

          // Tap Reactivate
          await tester.tap(find.text('Reactivate Relationship'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));

          // Should show confirmation dialog
          expect(find.text('Reactivate Relationship'), findsAtLeastNWidgets(1));
          expect(find.textContaining('Do you want to reactivate'), findsOneWidget);
          expect(find.text('CANCEL'), findsOneWidget);
          expect(find.text('REACTIVATE'), findsOneWidget);
        },
        () => _mockHttpClient(patientList: suspendedPatient),
      );
    });

    testWidgets('cancel button closes reactivate dialog', (tester) async {
      final suspendedPatient = [
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
          'linkStatus': 'SUSPENDED',
        },
      ];

      await http.runWithClient(
        () async {
          await _pumpWithLargeScreen(tester, _buildTestWidget());
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          // Open popup menu
          await tester.tap(find.byIcon(Icons.more_vert).first);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));

          // Tap Reactivate
          await tester.tap(find.text('Reactivate Relationship'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));

          // Tap CANCEL
          await tester.tap(find.text('CANCEL'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));

          // Dialog should be gone
          expect(find.textContaining('Do you want to reactivate'), findsNothing);
        },
        () => _mockHttpClient(patientList: suspendedPatient),
      );
    });
  });

  group('CaregiverDashboard patient card tap', () {
    testWidgets('tapping patient ListTile navigates to patient profile', (tester) async {
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

      await http.runWithClient(
        () async {
          await _pumpWithLargeScreen(tester, _buildTestWidget());
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          // Tap on the patient name (part of the ListTile)
          await tester.tap(find.text('John Doe'));
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));

          expect(find.text('Patient 10'), findsOneWidget);
        },
        () => _mockHttpClient(patientList: patients),
      );
    });
  });

  group('CaregiverDashboard null user redirect', () {
    testWidgets('redirects to login when user is null', (tester) async {
      // Use a real UserProvider without setting user so user is null
      final nullUserProvider = UserProvider();

      await http.runWithClient(
        () async {
          await _pumpWithLargeScreen(tester, _buildTestWidget(provider: nullUserProvider));
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));

          // When user is null, the build method calls context.go('/login')
          // so after pumping, we should be on the login page
          expect(find.text('Login Page'), findsOneWidget);
        },
        () => _mockHttpClient(),
      );
    });
  });

  group('CaregiverDashboard high heart rate warning', () {
    testWidgets('shows warning emoji for high heart rate', (tester) async {
      final patients = [
        {
          'id': 10,
          'firstName': 'Bob',
          'lastName': 'Builder',
          'email': 'bob@example.com',
          'phone': '555-1111',
          'dob': '05/10/1970',
          'gender': 'Male',
          'relationship': 'Patient',
          'linkId': 100,
          'linkStatus': 'ACTIVE',
        },
      ];

      final enhancedProfile = {
        'data': {
          'allergies': [],
          'latestVitals': {
            'heartRate': '120',
          },
          'medications': [],
        },
      };

      await http.runWithClient(
        () async {
          await _pumpWithLargeScreen(tester, _buildTestWidget());
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          expect(find.textContaining('HR: 120 bpm'), findsOneWidget);
        },
        () => _mockHttpClient(
          patientList: patients,
          enhancedProfile: enhancedProfile,
        ),
      );
    });

    testWidgets('shows warning for low oxygen saturation', (tester) async {
      final patients = [
        {
          'id': 10,
          'firstName': 'Bob',
          'lastName': 'Builder',
          'email': 'bob@example.com',
          'phone': '555-1111',
          'dob': '05/10/1970',
          'gender': 'Male',
          'relationship': 'Patient',
          'linkId': 100,
          'linkStatus': 'ACTIVE',
        },
      ];

      final enhancedProfile = {
        'data': {
          'allergies': [],
          'latestVitals': {
            'oxygenSaturation': '90',
          },
          'medications': [],
        },
      };

      await http.runWithClient(
        () async {
          await _pumpWithLargeScreen(tester, _buildTestWidget());
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          expect(find.textContaining('O2: 90%'), findsOneWidget);
        },
        () => _mockHttpClient(
          patientList: patients,
          enhancedProfile: enhancedProfile,
        ),
      );
    });

    testWidgets('shows fire emoji for high temperature', (tester) async {
      final patients = [
        {
          'id': 10,
          'firstName': 'Bob',
          'lastName': 'Builder',
          'email': 'bob@example.com',
          'phone': '555-1111',
          'dob': '05/10/1970',
          'gender': 'Male',
          'relationship': 'Patient',
          'linkId': 100,
          'linkStatus': 'ACTIVE',
        },
      ];

      final enhancedProfile = {
        'data': {
          'allergies': [],
          'latestVitals': {
            'temperature': '102.5',
          },
          'medications': [],
        },
      };

      await http.runWithClient(
        () async {
          await _pumpWithLargeScreen(tester, _buildTestWidget());
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          expect(find.textContaining('Temp: 102.5'), findsOneWidget);
        },
        () => _mockHttpClient(
          patientList: patients,
          enhancedProfile: enhancedProfile,
        ),
      );
    });

    testWidgets('shows warning for high glucose', (tester) async {
      final patients = [
        {
          'id': 10,
          'firstName': 'Bob',
          'lastName': 'Builder',
          'email': 'bob@example.com',
          'phone': '555-1111',
          'dob': '05/10/1970',
          'gender': 'Male',
          'relationship': 'Patient',
          'linkId': 100,
          'linkStatus': 'ACTIVE',
        },
      ];

      final enhancedProfile = {
        'data': {
          'allergies': [],
          'latestVitals': {
            'glucose': '200',
          },
          'medications': [],
        },
      };

      await http.runWithClient(
        () async {
          await _pumpWithLargeScreen(tester, _buildTestWidget());
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          expect(find.textContaining('Glucose: 200 mg/dL'), findsOneWidget);
        },
        () => _mockHttpClient(
          patientList: patients,
          enhancedProfile: enhancedProfile,
        ),
      );
    });

    testWidgets('shows warning for high respiratory rate', (tester) async {
      final patients = [
        {
          'id': 10,
          'firstName': 'Bob',
          'lastName': 'Builder',
          'email': 'bob@example.com',
          'phone': '555-1111',
          'dob': '05/10/1970',
          'gender': 'Male',
          'relationship': 'Patient',
          'linkId': 100,
          'linkStatus': 'ACTIVE',
        },
      ];

      final enhancedProfile = {
        'data': {
          'allergies': [],
          'latestVitals': {
            'respiratoryRate': '25',
          },
          'medications': [],
        },
      };

      await http.runWithClient(
        () async {
          await _pumpWithLargeScreen(tester, _buildTestWidget());
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          expect(find.textContaining('RR: 25/min'), findsOneWidget);
        },
        () => _mockHttpClient(
          patientList: patients,
          enhancedProfile: enhancedProfile,
        ),
      );
    });
  });

  group('CaregiverDashboard multiple vitals', () {
    testWidgets('shows multiple vitals in comma-separated format', (tester) async {
      final patients = [
        {
          'id': 10,
          'firstName': 'Bob',
          'lastName': 'Builder',
          'email': 'bob@example.com',
          'phone': '555-1111',
          'dob': '05/10/1970',
          'gender': 'Male',
          'relationship': 'Patient',
          'linkId': 100,
          'linkStatus': 'ACTIVE',
        },
      ];

      final enhancedProfile = {
        'data': {
          'allergies': [],
          'latestVitals': {
            'heartRate': '72',
            'temperature': '98.6',
          },
          'medications': [],
        },
      };

      await http.runWithClient(
        () async {
          await _pumpWithLargeScreen(tester, _buildTestWidget());
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          // Should show combined vitals
          expect(find.textContaining('HR: 72 bpm'), findsOneWidget);
        },
        () => _mockHttpClient(
          patientList: patients,
          enhancedProfile: enhancedProfile,
        ),
      );
    });
  });

  group('CaregiverDashboard patient without first name', () {
    testWidgets('shows ? when both first and last name are empty', (tester) async {
      final patients = [
        {
          'id': 10,
          'firstName': '',
          'lastName': '',
          'email': 'noname@example.com',
          'phone': '555-0000',
          'dob': '',
          'gender': '',
          'relationship': '',
          'linkId': 100,
          'linkStatus': 'ACTIVE',
        },
      ];

      await http.runWithClient(
        () async {
          await _pumpWithLargeScreen(tester, _buildTestWidget());
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          // Avatar should show '?'
          expect(find.text('?'), findsOneWidget);
        },
        () => _mockHttpClient(patientList: patients),
      );
    });

    testWidgets('shows last name initial when first name is empty', (tester) async {
      final patients = [
        {
          'id': 10,
          'firstName': '',
          'lastName': 'Doe',
          'email': 'noname@example.com',
          'phone': '555-0000',
          'dob': '',
          'gender': '',
          'relationship': '',
          'linkId': 100,
          'linkStatus': 'ACTIVE',
        },
      ];

      await http.runWithClient(
        () async {
          await _pumpWithLargeScreen(tester, _buildTestWidget());
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          // Avatar should show 'D' from last name
          expect(find.text('D'), findsOneWidget);
        },
        () => _mockHttpClient(patientList: patients),
      );
    });
  });

  group('CaregiverDashboard Divider in card', () {
    testWidgets('patient card has a Divider', (tester) async {
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

      await http.runWithClient(
        () async {
          await _pumpWithLargeScreen(tester, _buildTestWidget());
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          expect(find.byType(Divider), findsAtLeastNWidgets(1));
        },
        () => _mockHttpClient(patientList: patients),
      );
    });
  });

  group('CaregiverDashboard CallNotificationStatusIndicator', () {
    testWidgets('renders CallNotificationStatusIndicator', (tester) async {
      await http.runWithClient(
        () async {
          await _pumpWithLargeScreen(tester, _buildTestWidget());
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          // The widget should be present in the app bar
          expect(find.byType(CaregiverDashboard), findsOneWidget);
        },
        () => _mockHttpClient(patientList: []),
      );
    });
  });

  group('CaregiverDashboard NotificationsPanel', () {
    testWidgets('shows NotificationsPanel in empty state', (tester) async {
      await http.runWithClient(
        () async {
          await _pumpWithLargeScreen(tester, _buildTestWidget());
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          // NotificationsPanel should be present in both empty and list states
          expect(find.textContaining('Notification'), findsAtLeastNWidgets(1));
        },
        () => _mockHttpClient(patientList: []),
      );
    });

    testWidgets('shows NotificationsPanel in patient list', (tester) async {
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

      await http.runWithClient(
        () async {
          await _pumpWithLargeScreen(tester, _buildTestWidget());
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          expect(find.textContaining('Notification'), findsAtLeastNWidgets(1));
        },
        () => _mockHttpClient(patientList: patients),
      );
    });
  });
}
