// Tests for NavigationHelper
// (lib/config/navigation/navigation_helper.dart).
//
// Coverage strategy:
//   getTabIndexFromName     — pure static, no platform channel dependency.
//   _getTabNameFromIndex    — private, tested indirectly via navigateToMainScreen.
//   getMainScreenConfig     — reads from UserRoleStorageService (SharedPreferences
//                             mock), testable for all role branches.
//   isAuthenticated         — delegates to UserRoleStorageService.isLoggedIn().
//   navigateToMainScreen    — widget test with GoRouter to verify navigation.
//   navigateToTab           — widget test with GoRouter.
//   logout                  — widget test with GoRouter + UserProvider.
//   NavigationContextExtension — extension methods on BuildContext.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/config/navigation/navigation_helper.dart';
import 'package:care_connect_app/config/navigation/bottom_nav_config.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/user_role_storage_service.dart';

/// Records which route was navigated to via GoRouter.
class _RouteTracker {
  String? lastRoute;
  String? lastMethod; // 'go' or 'push'
}

/// Creates a GoRouter that tracks navigation to /dashboard and /login.
GoRouter _buildRouter(_RouteTracker tracker, {Widget? homeChild}) {
  return GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(
        path: '/home',
        builder: (context, state) => homeChild ?? const SizedBox(),
      ),
      GoRoute(
        path: '/dashboard',
        builder: (context, state) {
          tracker.lastRoute =
              '/dashboard${state.uri.query.isNotEmpty ? '?${state.uri.query}' : ''}';
          tracker.lastMethod ??= 'go';
          return const SizedBox();
        },
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) {
          tracker.lastRoute = '/login';
          return const SizedBox();
        },
      ),
    ],
  );
}

void main() {
  // ─── Setup for tests that need platform channels ──────────────────────────

  late _RouteTracker tracker;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        if (call.method == 'readAll') return <String, String>{};
        if (call.method == 'containsKey') return false;
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
    tracker = _RouteTracker();
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

  // ═══════════════════════════════════════════════════════════════════════════
  test('legacy tab names resolve to their current destinations', () {
    expect(NavigationHelper.getTabIndexFromName('PATIENT', 'health'), 2);
    expect(NavigationHelper.getTabIndexFromName('PATIENT', 'profile'), 4);
    expect(NavigationHelper.getTabIndexFromName('CAREGIVER', 'patients'), 0);
  });

  test('tab URL indices match every rendered navigation item', () {
    for (final role in ['PATIENT', 'CAREGIVER', 'FAMILY_LINK', 'ADMIN']) {
      final items = BottomNavConfig.getNavItemsForRole(role);
      for (var index = 0; index < items.length; index++) {
        expect(
            NavigationHelper.getTabIndexFromName(role, items[index].routeName),
            index);
      }
    }
  });

  // getTabIndexFromName — PATIENT role
  // ═══════════════════════════════════════════════════════════════════════════

  group('getTabIndexFromName – PATIENT role', () {
    test('"home" returns 0', () {
      expect(NavigationHelper.getTabIndexFromName('PATIENT', 'home'), 0);
    });

    test('"check-in" returns 2', () {
      expect(NavigationHelper.getTabIndexFromName('PATIENT', 'check-in'), 2);
    });

    test('"messages" returns the rendered index', () {
      expect(NavigationHelper.getTabIndexFromName('PATIENT', 'messages'), 3);
    });

    test('"menupage" returns 4', () {
      expect(NavigationHelper.getTabIndexFromName('PATIENT', 'menupage'), 4);
    });

    test('unknown tab returns null', () {
      expect(
        NavigationHelper.getTabIndexFromName('PATIENT', 'dashboard'),
        isNull,
      );
    });

    test('role matching is case-insensitive', () {
      expect(NavigationHelper.getTabIndexFromName('patient', 'home'), 0);
    });

    test('tabName matching is case-insensitive', () {
      expect(NavigationHelper.getTabIndexFromName('PATIENT', 'HOME'), 0);
      expect(NavigationHelper.getTabIndexFromName('PATIENT', 'CHECK-IN'), 2);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // getTabIndexFromName — non-PATIENT roles
  // ═══════════════════════════════════════════════════════════════════════════

  group('getTabIndexFromName – CAREGIVER (non-patient) role', () {
    test('"home" returns 0', () {
      expect(NavigationHelper.getTabIndexFromName('CAREGIVER', 'home'), 0);
    });

    test('"tasks" returns 1', () {
      expect(NavigationHelper.getTabIndexFromName('CAREGIVER', 'tasks'), 1);
    });

    test('"analytics" returns 2', () {
      expect(
        NavigationHelper.getTabIndexFromName('CAREGIVER', 'analytics'),
        2,
      );
    });

    test('"messages" returns the rendered index', () {
      expect(NavigationHelper.getTabIndexFromName('CAREGIVER', 'messages'), 4);
    });

    test('"profile" returns 5', () {
      expect(NavigationHelper.getTabIndexFromName('CAREGIVER', 'profile'), 5);
    });

    test('unknown tab returns null', () {
      expect(
        NavigationHelper.getTabIndexFromName('CAREGIVER', 'unknown'),
        isNull,
      );
    });

    test('role matching is case-insensitive for non-patient', () {
      expect(
        NavigationHelper.getTabIndexFromName('caregiver', 'analytics'),
        2,
      );
    });

    test('FAMILY_LINK uses the non-patient branch', () {
      expect(
        NavigationHelper.getTabIndexFromName('FAMILY_LINK', 'tasks'),
        1,
      );
    });

    test('ADMIN uses the non-patient branch', () {
      expect(NavigationHelper.getTabIndexFromName('ADMIN', 'profile'), 5);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // getMainScreenConfig
  // ═══════════════════════════════════════════════════════════════════════════

  group('getMainScreenConfig', () {
    test('returns null when user is not logged in', () async {
      SharedPreferences.setMockInitialValues({});
      await UserRoleStorageService.instance.clearUserData();

      final config = await NavigationHelper.getMainScreenConfig();
      expect(config, isNull);
    });

    test('returns null when userId is 0', () async {
      // Directly set values to simulate userId == 0
      SharedPreferences.setMockInitialValues({
        'user_role': 'PATIENT',
        'user_id': 0,
        'is_logged_in': true,
      });
      // The service already has prefs cached, so we set via service
      await UserRoleStorageService.instance.setUserData(
        role: 'PATIENT',
        userId: 0,
      );

      final config = await NavigationHelper.getMainScreenConfig();
      expect(config, isNull);
    });

    test('returns null when userId is negative', () async {
      await UserRoleStorageService.instance.setUserData(
        role: 'PATIENT',
        userId: -1,
      );

      final config = await NavigationHelper.getMainScreenConfig();
      expect(config, isNull);
    });

    test('returns PATIENT config for PATIENT role', () async {
      await UserRoleStorageService.instance.setUserData(
        role: 'PATIENT',
        userId: 5,
        patientId: 10,
      );

      final config = await NavigationHelper.getMainScreenConfig();
      expect(config, isNotNull);
      expect(config!.userRole, 'PATIENT');
      expect(config.userId, 5);
      expect(config.patientId, 10);
    });

    test('returns CAREGIVER config for CAREGIVER role', () async {
      await UserRoleStorageService.instance.setUserData(
        role: 'CAREGIVER',
        userId: 10,
        caregiverId: 3,
        patientId: 7,
      );

      final config = await NavigationHelper.getMainScreenConfig();
      expect(config, isNotNull);
      expect(config!.userRole, 'CAREGIVER');
      expect(config.userId, 10);
      expect(config.caregiverId, 3);
      expect(config.patientId, 7);
    });

    test('returns FAMILY_LINK config for FAMILY_LINK role', () async {
      await UserRoleStorageService.instance.setUserData(
        role: 'FAMILY_LINK',
        userId: 15,
        patientId: 20,
      );

      final config = await NavigationHelper.getMainScreenConfig();
      expect(config, isNotNull);
      expect(config!.userRole, 'FAMILY_LINK');
      expect(config.userId, 15);
      expect(config.patientId, 20);
    });

    test('returns ADMIN config for ADMIN role', () async {
      await UserRoleStorageService.instance.setUserData(
        role: 'ADMIN',
        userId: 20,
      );

      final config = await NavigationHelper.getMainScreenConfig();
      expect(config, isNotNull);
      expect(config!.userRole, 'ADMIN');
      expect(config.showAppBar, isTrue);
      expect(config.appBarTitle, 'Admin Dashboard');
      expect(config.primaryColor, Colors.red);
    });

    test('returns null for unknown role', () async {
      await UserRoleStorageService.instance.setUserData(
        role: 'UNKNOWN_ROLE',
        userId: 25,
      );

      final config = await NavigationHelper.getMainScreenConfig();
      expect(config, isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // isAuthenticated
  // ═══════════════════════════════════════════════════════════════════════════

  group('isAuthenticated', () {
    test('returns false when user is not logged in', () async {
      await UserRoleStorageService.instance.clearUserData();

      final result = await NavigationHelper.isAuthenticated();
      expect(result, isFalse);
    });

    test('returns true when user is logged in', () async {
      await UserRoleStorageService.instance.setUserData(
        role: 'PATIENT',
        userId: 5,
      );

      final result = await NavigationHelper.isAuthenticated();
      expect(result, isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // navigateToMainScreen
  // ═══════════════════════════════════════════════════════════════════════════

  group('navigateToMainScreen', () {
    testWidgets('redirects to /login when user is not logged in',
        (tester) async {
      await UserRoleStorageService.instance.clearUserData();

      final router = _buildRouter(tracker);

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      // Grab a context from the widget tree
      final context = tester.element(find.byType(SizedBox).first);

      await NavigationHelper.navigateToMainScreen(context);
      await tester.pumpAndSettle();

      expect(tracker.lastRoute, '/login');
    });

    testWidgets('navigates to /dashboard without tab when no tabIndex given',
        (tester) async {
      await UserRoleStorageService.instance.setUserData(
        role: 'PATIENT',
        userId: 5,
        patientId: 10,
      );

      final router = _buildRouter(tracker);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(SizedBox).first);

      await NavigationHelper.navigateToMainScreen(context);
      await tester.pumpAndSettle();

      expect(tracker.lastRoute, '/dashboard');
    });

    testWidgets(
      'navigates to /dashboard?tab=symptoms for PATIENT with tabIndex=1',
      (tester) async {
        await UserRoleStorageService.instance.setUserData(
          role: 'PATIENT',
          userId: 5,
          patientId: 10,
        );

        final router = _buildRouter(tracker);
        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
        await tester.pumpAndSettle();

        final context = tester.element(find.byType(SizedBox).first);

        await NavigationHelper.navigateToMainScreen(context, tabIndex: 1);
        await tester.pumpAndSettle();

        expect(tracker.lastRoute, '/dashboard?tab=symptoms');
      },
    );

    testWidgets('navigates to /dashboard?tab=home for PATIENT with tabIndex=0',
        (tester) async {
      await UserRoleStorageService.instance.setUserData(
        role: 'PATIENT',
        userId: 5,
      );

      final router = _buildRouter(tracker);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(SizedBox).first);

      await NavigationHelper.navigateToMainScreen(context, tabIndex: 0);
      await tester.pumpAndSettle();

      expect(tracker.lastRoute, '/dashboard?tab=home');
    });

    testWidgets(
      'navigates to /dashboard?tab=check-in for PATIENT with tabIndex=2',
      (tester) async {
        await UserRoleStorageService.instance.setUserData(
          role: 'PATIENT',
          userId: 5,
        );

        final router = _buildRouter(tracker);
        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
        await tester.pumpAndSettle();

        final context = tester.element(find.byType(SizedBox).first);

        await NavigationHelper.navigateToMainScreen(context, tabIndex: 2);
        await tester.pumpAndSettle();

        expect(tracker.lastRoute, '/dashboard?tab=check-in');
      },
    );

    testWidgets(
      'navigates to /dashboard?tab=messages for PATIENT with tabIndex=3',
      (tester) async {
        await UserRoleStorageService.instance.setUserData(
          role: 'PATIENT',
          userId: 5,
        );

        final router = _buildRouter(tracker);
        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
        await tester.pumpAndSettle();

        final context = tester.element(find.byType(SizedBox).first);

        await NavigationHelper.navigateToMainScreen(context, tabIndex: 3);
        await tester.pumpAndSettle();

        expect(tracker.lastRoute, '/dashboard?tab=messages');
      },
    );

    testWidgets(
        'navigates to /dashboard without tab for PATIENT with invalid tabIndex',
        (tester) async {
      await UserRoleStorageService.instance.setUserData(
        role: 'PATIENT',
        userId: 5,
      );

      final router = _buildRouter(tracker);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(SizedBox).first);

      await NavigationHelper.navigateToMainScreen(context, tabIndex: 99);
      await tester.pumpAndSettle();

      expect(tracker.lastRoute, '/dashboard');
    });

    testWidgets(
      'navigates to /dashboard?tab=home for CAREGIVER with tabIndex=0',
      (tester) async {
        await UserRoleStorageService.instance.setUserData(
          role: 'CAREGIVER',
          userId: 10,
          caregiverId: 3,
        );

        final router = _buildRouter(tracker);
        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
        await tester.pumpAndSettle();

        final context = tester.element(find.byType(SizedBox).first);

        await NavigationHelper.navigateToMainScreen(context, tabIndex: 0);
        await tester.pumpAndSettle();

        expect(tracker.lastRoute, '/dashboard?tab=home');
      },
    );

    testWidgets(
        'navigates to /dashboard?tab=tasks for CAREGIVER with tabIndex=1',
        (tester) async {
      await UserRoleStorageService.instance.setUserData(
        role: 'CAREGIVER',
        userId: 10,
        caregiverId: 3,
      );

      final router = _buildRouter(tracker);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(SizedBox).first);

      await NavigationHelper.navigateToMainScreen(context, tabIndex: 1);
      await tester.pumpAndSettle();

      expect(tracker.lastRoute, '/dashboard?tab=tasks');
    });

    testWidgets(
        'navigates to /dashboard?tab=analytics for CAREGIVER with tabIndex=2',
        (tester) async {
      await UserRoleStorageService.instance.setUserData(
        role: 'CAREGIVER',
        userId: 10,
        caregiverId: 3,
      );

      final router = _buildRouter(tracker);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(SizedBox).first);

      await NavigationHelper.navigateToMainScreen(context, tabIndex: 2);
      await tester.pumpAndSettle();

      expect(tracker.lastRoute, '/dashboard?tab=analytics');
    });

    testWidgets(
      'navigates to /dashboard?tab=schedule for CAREGIVER with tabIndex=3',
      (tester) async {
        await UserRoleStorageService.instance.setUserData(
          role: 'CAREGIVER',
          userId: 10,
          caregiverId: 3,
        );

        final router = _buildRouter(tracker);
        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
        await tester.pumpAndSettle();

        final context = tester.element(find.byType(SizedBox).first);

        await NavigationHelper.navigateToMainScreen(context, tabIndex: 3);
        await tester.pumpAndSettle();

        expect(tracker.lastRoute, '/dashboard?tab=schedule');
      },
    );

    testWidgets(
      'navigates to /dashboard?tab=messages for CAREGIVER with tabIndex=4',
      (tester) async {
        await UserRoleStorageService.instance.setUserData(
          role: 'CAREGIVER',
          userId: 10,
          caregiverId: 3,
        );

        final router = _buildRouter(tracker);
        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
        await tester.pumpAndSettle();

        final context = tester.element(find.byType(SizedBox).first);

        await NavigationHelper.navigateToMainScreen(context, tabIndex: 4);
        await tester.pumpAndSettle();

        expect(tracker.lastRoute, '/dashboard?tab=messages');
      },
    );

    testWidgets(
        'navigates to /dashboard without tab for CAREGIVER with invalid tabIndex',
        (tester) async {
      await UserRoleStorageService.instance.setUserData(
        role: 'CAREGIVER',
        userId: 10,
        caregiverId: 3,
      );

      final router = _buildRouter(tracker);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(SizedBox).first);

      await NavigationHelper.navigateToMainScreen(context, tabIndex: 99);
      await tester.pumpAndSettle();

      expect(tracker.lastRoute, '/dashboard');
    });

    testWidgets('uses go when clearHistory is true', (tester) async {
      await UserRoleStorageService.instance.setUserData(
        role: 'PATIENT',
        userId: 5,
      );

      final router = _buildRouter(tracker);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(SizedBox).first);

      await NavigationHelper.navigateToMainScreen(
        context,
        clearHistory: true,
      );
      await tester.pumpAndSettle();

      // Verify it navigated to dashboard (go replaces the stack)
      expect(tracker.lastRoute, '/dashboard');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // navigateToTab
  // ═══════════════════════════════════════════════════════════════════════════

  group('navigateToTab', () {
    testWidgets('redirects to /login when user is not logged in',
        (tester) async {
      await UserRoleStorageService.instance.clearUserData();

      final router = _buildRouter(tracker);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(SizedBox).first);

      await NavigationHelper.navigateToTab(context, 'health');
      await tester.pumpAndSettle();

      expect(tracker.lastRoute, '/login');
    });

    testWidgets('navigates to /dashboard?tab=<tabName> when logged in',
        (tester) async {
      await UserRoleStorageService.instance.setUserData(
        role: 'PATIENT',
        userId: 5,
      );

      final router = _buildRouter(tracker);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(SizedBox).first);

      await NavigationHelper.navigateToTab(context, 'health');
      await tester.pumpAndSettle();

      expect(tracker.lastRoute, '/dashboard?tab=health');
    });

    testWidgets('navigates to correct tab for analytics', (tester) async {
      await UserRoleStorageService.instance.setUserData(
        role: 'CAREGIVER',
        userId: 10,
      );

      final router = _buildRouter(tracker);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(SizedBox).first);

      await NavigationHelper.navigateToTab(context, 'analytics');
      await tester.pumpAndSettle();

      expect(tracker.lastRoute, '/dashboard?tab=analytics');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // logout
  // ═══════════════════════════════════════════════════════════════════════════

  group('logout', () {
    testWidgets('clears user data and navigates to /login', (tester) async {
      // Store some user data first
      await UserRoleStorageService.instance.setUserData(
        role: 'PATIENT',
        userId: 5,
        patientId: 10,
      );

      final userProvider = UserProvider();
      final router = _buildRouter(tracker);

      await tester.pumpWidget(
        ChangeNotifierProvider<UserProvider>.value(
          value: userProvider,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(SizedBox).first);

      await NavigationHelper.logout(context);
      await tester.pumpAndSettle();

      // Verify navigation to /login
      expect(tracker.lastRoute, '/login');

      // Verify user data was cleared
      final isLoggedIn = await UserRoleStorageService.instance.isLoggedIn();
      expect(isLoggedIn, isFalse);

      userProvider.dispose();
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // NavigationContextExtension
  // ═══════════════════════════════════════════════════════════════════════════

  group('NavigationContextExtension', () {
    testWidgets('navigateToMainScreen extension delegates correctly',
        (tester) async {
      await UserRoleStorageService.instance.setUserData(
        role: 'PATIENT',
        userId: 5,
      );

      final router = _buildRouter(tracker);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(SizedBox).first);

      await context.navigateToMainScreen(tabIndex: 1);
      await tester.pumpAndSettle();

      expect(tracker.lastRoute, '/dashboard?tab=symptoms');
    });

    testWidgets(
        'navigateToMainScreen extension with clearHistory delegates correctly',
        (tester) async {
      await UserRoleStorageService.instance.setUserData(
        role: 'PATIENT',
        userId: 5,
      );

      final router = _buildRouter(tracker);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(SizedBox).first);

      await context.navigateToMainScreen(clearHistory: true);
      await tester.pumpAndSettle();

      expect(tracker.lastRoute, '/dashboard');
    });

    testWidgets('navigateToTab extension delegates correctly', (tester) async {
      await UserRoleStorageService.instance.setUserData(
        role: 'CAREGIVER',
        userId: 10,
      );

      final router = _buildRouter(tracker);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(SizedBox).first);

      await context.navigateToTab('messages');
      await tester.pumpAndSettle();

      expect(tracker.lastRoute, '/dashboard?tab=messages');
    });

    testWidgets('logoutUser extension delegates correctly', (tester) async {
      await UserRoleStorageService.instance.setUserData(
        role: 'PATIENT',
        userId: 5,
      );

      final userProvider = UserProvider();
      final router = _buildRouter(tracker);

      await tester.pumpWidget(
        ChangeNotifierProvider<UserProvider>.value(
          value: userProvider,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(SizedBox).first);

      await context.logoutUser();
      await tester.pumpAndSettle();

      expect(tracker.lastRoute, '/login');

      userProvider.dispose();
    });

    testWidgets(
        'navigateToMainScreen extension redirects to login when not logged in',
        (tester) async {
      await UserRoleStorageService.instance.clearUserData();

      final router = _buildRouter(tracker);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(SizedBox).first);

      await context.navigateToMainScreen();
      await tester.pumpAndSettle();

      expect(tracker.lastRoute, '/login');
    });

    testWidgets('navigateToTab extension redirects to login when not logged in',
        (tester) async {
      await UserRoleStorageService.instance.clearUserData();

      final router = _buildRouter(tracker);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(SizedBox).first);

      await context.navigateToTab('health');
      await tester.pumpAndSettle();

      expect(tracker.lastRoute, '/login');
    });
  });
}
