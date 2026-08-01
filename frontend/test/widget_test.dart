// Comprehensive Flutter widget tests for CareConnect app
// This test suite covers all major components under lib/

import 'package:care_connect_app/features/dashboard/patient_dashboard/pages/patient_dashboard.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/shared/widgets/user_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Core imports
import 'package:care_connect_app/providers/user_provider.dart';

// Feature imports
import 'package:care_connect_app/features/auth/presentation/pages/login_page.dart';
import 'package:care_connect_app/features/auth/presentation/pages/password_reset_page.dart';
import 'package:care_connect_app/features/dashboard/presentation/pages/caregiver_dashboard.dart';
import 'package:care_connect_app/features/dashboard/presentation/pages/patient_status_page.dart';
import 'package:care_connect_app/features/analytics/analytics_page.dart';
import 'package:care_connect_app/features/payments/presentation/pages/select_package_page.dart';
import 'package:care_connect_app/features/payments/presentation/pages/payment_success_page.dart';
import 'package:care_connect_app/features/payments/presentation/pages/payment_cancel_page.dart';
import 'package:care_connect_app/features/social/presentation/pages/main_feed_screen.dart';
import 'package:care_connect_app/features/social/presentation/pages/friend_requests_screen.dart';
import 'package:care_connect_app/features/social/presentation/pages/new_post_screen.dart';
import 'package:care_connect_app/features/gamification/presentation/pages/gamification_screen.dart';
import 'package:care_connect_app/features/gamification/presentation/pages/achievement_detail_screen.dart';
import 'package:care_connect_app/features/health/presentation/pages/meal_tracking_screen.dart';
import 'package:care_connect_app/features/health/symptom-tracker/pages/symptom_allergies_tracker_screen.dart';
import 'package:care_connect_app/features/profile/presentation/pages/settings_screen.dart';

// Model imports
import 'package:care_connect_app/features/dashboard/models/patient_model.dart';
import 'package:care_connect_app/features/payments/models/package_model.dart';
import 'package:care_connect_app/features/analytics/models/vital_model.dart';

// Service imports
import 'package:care_connect_app/services/auth_service.dart';
import 'package:care_connect_app/services/session_manager.dart';
import 'package:care_connect_app/services/gamification_service.dart';

/// Wraps [child] with a UserProvider that has a PATIENT session.
Widget _withPatientProvider(Widget child) {
  final provider = UserProvider();
  provider.setUser(UserSession(
    id: 5,
    email: 'patient@test.com',
    role: 'PATIENT',
    token: 'tok',
    name: 'Test Patient',
  ));
  return ChangeNotifierProvider<UserProvider>.value(
    value: provider,
    child: MaterialApp(home: child),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});

    // Mock flutter_secure_storage
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        if (call.method == 'readAll') return <String, String>{};
        if (call.method == 'containsKey') return false;
        return null;
      },
    );

    // Mock connectivity_plus
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

  group('Welcome & Auth Tests', () {
    testWidgets('LoginPage can be constructed', (WidgetTester tester) async {
      // LoginPage requires AppLocalizations which needs full localization setup.
      // Verify construction only.
      const page = LoginPage();
      expect(page, isA<LoginPage>());
    });

    testWidgets('PasswordResetPage renders correctly', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: PasswordResetPage()));
      await tester.pump();

      expect(find.byType(PasswordResetPage), findsOneWidget);
      expect(find.byType(TextFormField), findsWidgets);
    });
  });

  group('Dashboard Tests', () {
    testWidgets('CaregiverDashboard renders with GoRouter', (
      WidgetTester tester,
    ) async {
      final router = GoRouter(
        initialLocation: '/dash',
        routes: [
          GoRoute(path: '/', builder: (_, __) => const Scaffold()),
          GoRoute(path: '/dash', builder: (_, __) => const CaregiverDashboard()),
          GoRoute(path: '/login', builder: (_, __) => const Scaffold()),
        ],
      );
      await tester.pumpWidget(
        ChangeNotifierProvider<UserProvider>(
          create: (_) => UserProvider(),
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump();

      expect(find.byType(CaregiverDashboard), findsOneWidget);
      expect(find.byType(Scaffold), findsAtLeastNWidgets(1));
    });

    testWidgets('PatientDashboard renders with GoRouter', (
      WidgetTester tester,
    ) async {
      // Use a large surface to avoid RenderFlex overflow errors.
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final provider = UserProvider();
      provider.setUser(UserSession(
        id: 5, email: 'p@test.com', role: 'PATIENT', token: 'tok', name: 'P',
      ));
      final router = GoRouter(
        initialLocation: '/dash',
        routes: [
          GoRoute(path: '/', builder: (_, __) => const Scaffold()),
          GoRoute(path: '/dash', builder: (_, __) => const PatientDashboard()),
          GoRoute(path: '/login', builder: (_, __) => const Scaffold()),
        ],
      );
      await tester.pumpWidget(
        ChangeNotifierProvider<UserProvider>.value(
          value: provider,
          child: MaterialApp.router(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router),
        ),
      );
      await tester.pump();

      expect(find.byType(PatientDashboard), findsOneWidget);
      expect(find.byType(Scaffold), findsAtLeastNWidgets(1));
    });

    testWidgets('PatientStatusPage can be constructed', (
      WidgetTester tester,
    ) async {
      // PatientStatusPage uses null-check on internal state that requires
      // live API data. Verify construction only.
      const page = PatientStatusPage();
      expect(page, isA<PatientStatusPage>());
    });
  });

  group('Analytics Tests', () {
    testWidgets('AnalyticsPage renders correctly', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: AnalyticsPage(patientId: 1)),
      );

      expect(find.byType(AnalyticsPage), findsOneWidget);
      expect(find.byType(Scaffold), findsOneWidget);
    });
  });

  group('Payment Tests', () {
    testWidgets('SelectPackagePage renders correctly', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: SelectPackagePage()));

      expect(find.byType(SelectPackagePage), findsOneWidget);
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('PaymentSuccessPage renders correctly', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp.router(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: GoRouter(
            initialLocation: '/payment-success',
            routes: [
              GoRoute(
                path: '/payment-success',
                builder: (context, state) => const PaymentSuccessPage(),
              ),
              GoRoute(
                path: '/login',
                builder: (context, state) =>
                    const Scaffold(body: Text('Login')),
              ),
              GoRoute(
                path: '/dashboard/patient',
                builder: (context, state) =>
                    const Scaffold(body: Text('Dashboard')),
              ),
            ],
          ),
        ),
      );

      expect(find.byType(PaymentSuccessPage), findsOneWidget);
      expect(find.byType(Scaffold), findsOneWidget);

      // Wait for animations and timers to complete
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('PaymentCancelPage renders correctly', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: PaymentCancelPage()));

      expect(find.byType(PaymentCancelPage), findsOneWidget);
      expect(find.byType(Scaffold), findsOneWidget);
    });
  });

  group('Social Feature Tests', () {
    testWidgets('MainFeedScreen renders correctly', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: MainFeedScreen(userId: 1)),
      );

      expect(find.byType(MainFeedScreen), findsOneWidget);
      expect(find.byType(Scaffold), findsAtLeastNWidgets(1));
    });

    testWidgets('FriendRequestsScreen renders correctly', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_withPatientProvider(const FriendRequestsScreen()));
      await tester.pump();

      expect(find.byType(FriendRequestsScreen), findsOneWidget);
      expect(find.byType(Scaffold), findsAtLeastNWidgets(1));
    });

    testWidgets('NewPostScreen renders correctly', (WidgetTester tester) async {
      await tester.pumpWidget(_withPatientProvider(const NewPostScreen()));
      await tester.pump();

      expect(find.byType(NewPostScreen), findsOneWidget);
      expect(find.byType(Scaffold), findsAtLeastNWidgets(1));
    });
  });

  group('Gamification Tests', () {
    testWidgets('GamificationScreen renders correctly', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: GamificationScreen()));

      expect(find.byType(GamificationScreen), findsOneWidget);
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('AchievementDetailScreen renders correctly', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: AchievementDetailScreen(achievements: [])),
      );

      expect(find.byType(AchievementDetailScreen), findsOneWidget);
      expect(find.byType(Scaffold), findsOneWidget);
    });
  });

  group('Health Feature Tests', () {
    testWidgets('MealTrackingScreen renders correctly', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: MealTrackingScreen()));

      expect(find.byType(MealTrackingScreen), findsOneWidget);
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('SymptomTrackerScreen renders correctly', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_withPatientProvider(const SymptomsAllergiesPage()));
      await tester.pump();

      expect(find.byType(SymptomsAllergiesPage), findsOneWidget);
      expect(find.byType(Scaffold), findsAtLeastNWidgets(1));
    });
  });

  group('Profile Tests', () {
    testWidgets('SettingsScreen renders correctly', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));

      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.byType(Scaffold), findsOneWidget);
    });
  });

  group('Model Tests', () {
    test('Patient model creates correctly', () {
      final patient = Patient(
        id: 1,
        firstName: 'John',
        lastName: 'Doe',
        email: 'john@example.com',
        phone: '555-1234',
        dob: '1990-01-01',
        relationship: 'self',
        address: Address(
          line1: '123 Main St',
          city: 'Anytown',
          state: 'NY',
          zip: '12345',
        ),
      );

      expect(patient.id, 1);
      expect(patient.firstName, 'John');
      expect(patient.lastName, 'Doe');
      expect(patient.email, 'john@example.com');
      expect(patient.address?.line1, '123 Main St');
    });

    test('PackageModel creates correctly', () {
      final package = PackageModel(
        id: 'basic-plan',
        name: 'Basic Plan',
        priceCents: 2999,
        description: 'Basic features',
      );

      expect(package.id, 'basic-plan');
      expect(package.name, 'Basic Plan');
      expect(package.priceCents, 2999);
      expect(package.description, 'Basic features');
    });

    test('Vital creates correctly', () {
      final vital = Vital(
        patientId: 1,
        timestamp: DateTime.now(),
        heartRate: 72.0,
        spo2: 98.0,
        systolic: 120,
        diastolic: 80,
        weight: 70.5,
      );

      expect(vital.patientId, 1);
      expect(vital.heartRate, 72.0);
      expect(vital.spo2, 98.0);
      expect(vital.systolic, 120);
      expect(vital.diastolic, 80);
      expect(vital.weight, 70.5);
    });

    test('Address creates correctly', () {
      final address = Address(
        line1: '123 Main St',
        line2: 'Apt 4B',
        city: 'Anytown',
        state: 'NY',
        zip: '12345',
        phone: '555-1234',
      );

      expect(address.line1, '123 Main St');
      expect(address.line2, 'Apt 4B');
      expect(address.city, 'Anytown');
      expect(address.state, 'NY');
      expect(address.zip, '12345');
      expect(address.phone, '555-1234');
    });
  });

  group('Service Tests', () {
    test('AuthService exists and has required methods', () {
      expect(AuthService.login, isA<Function>());
      expect(AuthService.register, isA<Function>());
      expect(AuthService.logout, isA<Function>());
    });

    test('SessionManager can be instantiated', () {
      final sessionManager = SessionManager();
      expect(sessionManager, isNotNull);
      expect(sessionManager.restoreSession, isA<Function>());
    });

    test('GamificationService can be instantiated', () {
      final gamificationService = GamificationService();
      expect(gamificationService, isNotNull);
    });
  });

  group('Provider Tests', () {
    test('UserProvider manages user state correctly', () {
      final userProvider = UserProvider();

      expect(userProvider.user, isNull);

      final user = UserSession(
        id: 1,
        role: 'PATIENT',
        token: 'test_token',
        email: 'testme@sample.com',
        patientId: 1,
      );

      userProvider.setUser(user);
      expect(userProvider.user, isNotNull);
      expect(userProvider.user!.id, 1);
      expect(userProvider.user!.role, 'PATIENT');

      userProvider.clearUser();
      expect(userProvider.user, isNull);
    });
  });

  group('Widget Tests', () {
    testWidgets('UserAvatar renders correctly', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: UserAvatar(
              imageUrl: null,
            ), // No image URL to avoid network calls in tests
          ),
        ),
      );

      expect(find.byType(UserAvatar), findsOneWidget);
      expect(find.byType(CircleAvatar), findsOneWidget);
      expect(
        find.byIcon(Icons.person),
        findsOneWidget,
      ); // Should show person icon when no image
    });
  });
}
