// Tests for RoleBasedDrawer
// (lib/widgets/role_based_drawer.dart).
//
// RoleBasedDrawer is a StatelessWidget using Consumer<UserProvider>.
// When userSession is null it shows "Not logged in" fallback.
// No API calls in initState.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:care_connect_app/widgets/role_based_drawer.dart';
import 'package:care_connect_app/providers/user_provider.dart';

import '../mock_user_provider.dart';

// Wraps the drawer inside a Scaffold so it can be opened.
Widget _wrap({UserProvider? provider, GlobalKey<NavigatorState>? navKey}) {
  final p = provider ?? MockUserProvider(mockUser: MockUser());
  return MaterialApp(
    navigatorKey: navKey,
    routes: {
      '/dashboard': (_) => const Scaffold(body: Text('Dashboard Page')),
      '/admin/users': (_) => const Scaffold(body: Text('User Mgmt Page')),
      '/patients': (_) => const Scaffold(body: Text('Patients Page')),
      '/patients/add': (_) => const Scaffold(body: Text('Add Patient Page')),
      '/tasks': (_) => const Scaffold(body: Text('Tasks Page')),
      '/health-data': (_) => const Scaffold(body: Text('Health Page')),
      '/analytics': (_) => const Scaffold(body: Text('Analytics Page')),
      '/messages': (_) => const Scaffold(body: Text('Messages Page')),
      '/settings': (_) => const Scaffold(body: Text('Settings Page')),
      '/login': (_) => const Scaffold(body: Text('Login Page')),
    },
    home: ChangeNotifierProvider<UserProvider>.value(
      value: p,
      child: Scaffold(
        drawer: const RoleBasedDrawer(),
        body: Builder(
          builder: (ctx) => TextButton(
            onPressed: () => Scaffold.of(ctx).openDrawer(),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
}

// GoRouter variant for drawer items that navigate with context.go().
Widget _wrapRouter({required UserProvider provider}) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => Scaffold(
          drawer: const RoleBasedDrawer(),
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => Scaffold.of(ctx).openDrawer(),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/admin/users',
        builder: (_, __) => const Scaffold(body: Text('User Mgmt Page')),
      ),
      // As app_router.dart has it: the app's Health Data screen.
      GoRoute(
        path: '/health-data',
        builder: (context, _) => Scaffold(
          body: Column(children: [
            const Text('Health Page'),
            TextButton(
              onPressed: () => context.pop(),
              child: const Text('Back'),
            ),
          ]),
        ),
      ),
    ],
  );
  return ChangeNotifierProvider<UserProvider>.value(
    value: provider,
    child: MaterialApp.router(routerConfig: router),
  );
}

class _SessionUserProvider extends MockUserProvider {
  _SessionUserProvider({
    required String name,
    required String email,
    required String role,
  }) : super(mockUser: MockUser(name: name, email: email, role: role)) {
    userSession = _FakeSession(name: name, email: email, role: role);
  }
}

class _FakeSession {
  final String name;
  final String email;
  final String role;
  _FakeSession({required this.name, required this.email, required this.role});
}

void main() {
  // Mock flutter_secure_storage and connectivity method channels
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel =
        MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      if (methodCall.method == 'read') return null;
      if (methodCall.method == 'write') return null;
      if (methodCall.method == 'delete') return null;
      if (methodCall.method == 'deleteAll') return null;
      return null;
    });
  });

  group('RoleBasedDrawer – null userSession', () {
    testWidgets('TC-RBD-001: renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byType(Drawer), findsOneWidget);
    });

    testWidgets('TC-RBD-002: shows "Not logged in" when userSession is null',
        (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Not logged in'), findsOneWidget);
    });
  });

  group('RoleBasedDrawer – logged-in user', () {
    testWidgets('TC-RBD-003: shows user name and email for PATIENT', (tester) async {
      final provider = _SessionUserProvider(
        name: 'Alice',
        email: 'alice@test.com',
        role: 'PATIENT',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('alice@test.com'), findsOneWidget);
    });

    testWidgets('TC-RBD-004: shows Dashboard for all roles', (tester) async {
      final provider = _SessionUserProvider(
        name: 'Bob',
        email: 'bob@test.com',
        role: 'PATIENT',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Dashboard'), findsOneWidget);
    });

    testWidgets('TC-RBD-005: shows Health Data for all roles', (tester) async {
      final provider = _SessionUserProvider(
        name: 'Bob',
        email: 'b@t.com',
        role: 'PATIENT',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Health Data'), findsOneWidget);
    });

    testWidgets('TC-RBD-006: shows Messages for all roles', (tester) async {
      final provider = _SessionUserProvider(
        name: 'Bob',
        email: 'b@t.com',
        role: 'PATIENT',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Messages'), findsOneWidget);
    });

    testWidgets('TC-RBD-007: shows role badge text for Patient', (tester) async {
      final provider = _SessionUserProvider(
        name: 'Bob',
        email: 'b@t.com',
        role: 'PATIENT',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Patient'), findsOneWidget);
    });

    testWidgets('TC-RBD-008: does NOT show Administration for PATIENT', (tester) async {
      final provider = _SessionUserProvider(
        name: 'Bob',
        email: 'b@t.com',
        role: 'PATIENT',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Administration'), findsNothing);
    });

    testWidgets('TC-RBD-009: does NOT show Tasks for FAMILY_MEMBER', (tester) async {
      final provider = _SessionUserProvider(
        name: 'Carol',
        email: 'c@t.com',
        role: 'FAMILY_MEMBER',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Tasks'), findsNothing);
    });

    testWidgets('TC-RBD-010: shows Tasks for CAREGIVER', (tester) async {
      final provider = _SessionUserProvider(
        name: 'Dan',
        email: 'd@t.com',
        role: 'CAREGIVER',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Tasks'), findsOneWidget);
    });

    testWidgets('TC-RBD-011: shows Administration for ADMIN', (tester) async {
      final provider = _SessionUserProvider(
        name: 'Admin',
        email: 'a@t.com',
        role: 'ADMIN',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Administration'), findsOneWidget);
    });

    testWidgets('TC-RBD-012: shows Analytics for CAREGIVER', (tester) async {
      final provider = _SessionUserProvider(
        name: 'Dan',
        email: 'd@t.com',
        role: 'CAREGIVER',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Analytics'), findsOneWidget);
    });

    testWidgets('TC-RBD-013: shows Patient Management for CAREGIVER', (tester) async {
      final provider = _SessionUserProvider(
        name: 'Dan',
        email: 'd@t.com',
        role: 'CAREGIVER',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Patient Management'), findsOneWidget);
    });

    testWidgets('TC-RBD-014: shows Logout for all logged-in users', (tester) async {
      final provider = _SessionUserProvider(
        name: 'Bob',
        email: 'b@t.com',
        role: 'PATIENT',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Logout'), findsOneWidget);
    });

    testWidgets('TC-RBD-015: shows Settings for all logged-in users', (tester) async {
      final provider = _SessionUserProvider(
        name: 'Bob',
        email: 'b@t.com',
        role: 'PATIENT',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('TC-RBD-016: role badge shows Caregiver for CAREGIVER role',
        (tester) async {
      final provider = _SessionUserProvider(
        name: 'Dan',
        email: 'd@t.com',
        role: 'CAREGIVER',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Caregiver'), findsOneWidget);
    });

    testWidgets('TC-RBD-017: role badge shows Administrator for ADMIN role',
        (tester) async {
      final provider = _SessionUserProvider(
        name: 'Admin',
        email: 'a@t.com',
        role: 'ADMIN',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Administrator'), findsOneWidget);
    });

    testWidgets('TC-RBD-018: role badge shows Family Member for FAMILY_MEMBER role',
        (tester) async {
      final provider = _SessionUserProvider(
        name: 'Fam',
        email: 'f@t.com',
        role: 'FAMILY_MEMBER',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Family Member'), findsOneWidget);
    });
  });

  group('RoleBasedDrawer – drawer structure and icons', () {
    testWidgets('TC-RBD-019: drawer contains UserAccountsDrawerHeader', (tester) async {
      final provider = _SessionUserProvider(
        name: 'Alice',
        email: 'a@t.com',
        role: 'PATIENT',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byType(UserAccountsDrawerHeader), findsOneWidget);
    });

    testWidgets('TC-RBD-020: header shows first letter of name in avatar', (tester) async {
      final provider = _SessionUserProvider(
        name: 'Zach',
        email: 'z@t.com',
        role: 'PATIENT',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Z'), findsOneWidget);
    });

    testWidgets('TC-RBD-021: header shows ? for empty name', (tester) async {
      final provider = _SessionUserProvider(
        name: '',
        email: 'e@t.com',
        role: 'PATIENT',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('?'), findsOneWidget);
    });

    testWidgets('TC-RBD-022: drawer has dashboard icon', (tester) async {
      final provider = _SessionUserProvider(
        name: 'Test',
        email: 't@t.com',
        role: 'PATIENT',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.dashboard), findsOneWidget);
    });

    testWidgets('TC-RBD-023: drawer has health_and_safety icon', (tester) async {
      final provider = _SessionUserProvider(
        name: 'Test',
        email: 't@t.com',
        role: 'PATIENT',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.health_and_safety), findsOneWidget);
    });

    testWidgets('TC-RBD-024: drawer has message icon', (tester) async {
      final provider = _SessionUserProvider(
        name: 'Test',
        email: 't@t.com',
        role: 'PATIENT',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.message), findsOneWidget);
    });

    testWidgets('TC-RBD-025: drawer has settings icon', (tester) async {
      final provider = _SessionUserProvider(
        name: 'Test',
        email: 't@t.com',
        role: 'PATIENT',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.settings), findsOneWidget);
    });

    testWidgets('TC-RBD-026: drawer has logout icon', (tester) async {
      final provider = _SessionUserProvider(
        name: 'Test',
        email: 't@t.com',
        role: 'PATIENT',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.logout), findsOneWidget);
    });

    testWidgets('TC-RBD-027: drawer has task icon for PATIENT', (tester) async {
      final provider = _SessionUserProvider(
        name: 'Test',
        email: 't@t.com',
        role: 'PATIENT',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.task), findsOneWidget);
    });

    testWidgets('TC-RBD-028: drawer has analytics icon for ADMIN', (tester) async {
      final provider = _SessionUserProvider(
        name: 'Test',
        email: 't@t.com',
        role: 'ADMIN',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.analytics), findsOneWidget);
    });

    testWidgets('TC-RBD-029: ADMIN drawer has admin_panel_settings icon', (tester) async {
      final provider = _SessionUserProvider(
        name: 'Test',
        email: 't@t.com',
        role: 'ADMIN',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.admin_panel_settings), findsOneWidget);
    });

    testWidgets(
        'TC-RBD-030: CAREGIVER drawer has people_outline icon for Patient Management',
        (tester) async {
      final provider = _SessionUserProvider(
        name: 'Test',
        email: 't@t.com',
        role: 'CAREGIVER',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.people_outline), findsOneWidget);
    });

    testWidgets('TC-RBD-031: Dividers present in drawer', (tester) async {
      final provider = _SessionUserProvider(
        name: 'Test',
        email: 't@t.com',
        role: 'PATIENT',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byType(Divider), findsAtLeastNWidgets(2));
    });
  });

  group('RoleBasedDrawer – role-specific menu visibility', () {
    testWidgets('TC-RBD-032: PATIENT does NOT see Patient Management', (tester) async {
      final provider = _SessionUserProvider(
        name: 'Pat',
        email: 'p@t.com',
        role: 'PATIENT',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Patient Management'), findsNothing);
    });

    testWidgets('TC-RBD-033: PATIENT does NOT see Analytics', (tester) async {
      final provider = _SessionUserProvider(
        name: 'Pat',
        email: 'p@t.com',
        role: 'PATIENT',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Analytics'), findsNothing);
    });

    testWidgets('TC-RBD-034: PATIENT sees Tasks', (tester) async {
      final provider = _SessionUserProvider(
        name: 'Pat',
        email: 'p@t.com',
        role: 'PATIENT',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Tasks'), findsOneWidget);
    });

    testWidgets('TC-RBD-035: FAMILY_MEMBER does NOT see Analytics', (tester) async {
      final provider = _SessionUserProvider(
        name: 'Fam',
        email: 'f@t.com',
        role: 'FAMILY_MEMBER',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Analytics'), findsNothing);
    });

    testWidgets('TC-RBD-036: FAMILY_MEMBER does NOT see Patient Management',
        (tester) async {
      final provider = _SessionUserProvider(
        name: 'Fam',
        email: 'f@t.com',
        role: 'FAMILY_MEMBER',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Patient Management'), findsNothing);
    });

    testWidgets('TC-RBD-037: FAMILY_MEMBER does NOT see Administration', (tester) async {
      final provider = _SessionUserProvider(
        name: 'Fam',
        email: 'f@t.com',
        role: 'FAMILY_MEMBER',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Administration'), findsNothing);
    });

    testWidgets('TC-RBD-038: FAMILY_MEMBER sees Dashboard, Health Data, Messages, Settings',
        (tester) async {
      final provider = _SessionUserProvider(
        name: 'Fam',
        email: 'f@t.com',
        role: 'FAMILY_MEMBER',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('Health Data'), findsOneWidget);
      expect(find.text('Messages'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets(
        'TC-RBD-039: ADMIN sees Administration, Patient Management, Tasks, Analytics',
        (tester) async {
      final provider = _SessionUserProvider(
        name: 'Admin',
        email: 'a@t.com',
        role: 'ADMIN',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Administration'), findsOneWidget);
      expect(find.text('Patient Management'), findsOneWidget);
      expect(find.text('Tasks'), findsOneWidget);
      expect(find.text('Analytics'), findsOneWidget);
    });

    testWidgets('TC-RBD-040: FAMILY_LINK sees Patient Management and Analytics',
        (tester) async {
      final provider = _SessionUserProvider(
        name: 'Link',
        email: 'l@t.com',
        role: 'FAMILY_LINK',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Patient Management'), findsOneWidget);
      expect(find.text('Analytics'), findsOneWidget);
    });

    testWidgets('TC-RBD-041: FAMILY_LINK role badge shows Family Link', (tester) async {
      final provider = _SessionUserProvider(
        name: 'Link',
        email: 'l@t.com',
        role: 'FAMILY_LINK',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Family Link'), findsOneWidget);
    });

    testWidgets('TC-RBD-042: unknown role shows raw role text', (tester) async {
      final provider = _SessionUserProvider(
        name: 'Unknown',
        email: 'u@t.com',
        role: 'CUSTOM_ROLE',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('CUSTOM_ROLE'), findsOneWidget);
    });
  });

  group('RoleBasedDrawer – menu item navigation', () {
    testWidgets('TC-RBD-043: tapping Dashboard navigates to /dashboard', (tester) async {
      final provider = _SessionUserProvider(
        name: 'Test',
        email: 't@t.com',
        role: 'PATIENT',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Dashboard'));
      await tester.pumpAndSettle();

      expect(find.text('Dashboard Page'), findsOneWidget);
    });

    testWidgets(
        'TC-RBD-044: tapping Health Data opens /health-data in the app '
        'GoRouter (DEF-MCR-38)', (tester) async {
      final provider = _SessionUserProvider(
        name: 'Test',
        email: 't@t.com',
        role: 'PATIENT',
      );
      // The app is a MaterialApp.router: a plain MaterialApp with a routes:
      // table hid that Navigator.pushNamed throws there.
      await tester.pumpWidget(_wrapRouter(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Health Data'));
      await tester.pumpAndSettle();

      expect(find.text('Health Page'), findsOneWidget);
    });

    testWidgets('TC-RBD-045: tapping Messages navigates to /messages', (tester) async {
      final provider = _SessionUserProvider(
        name: 'Test',
        email: 't@t.com',
        role: 'PATIENT',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Messages'));
      await tester.pumpAndSettle();

      expect(find.text('Messages Page'), findsOneWidget);
    });

    testWidgets('TC-RBD-046: tapping Settings navigates to /settings', (tester) async {
      final provider = _SessionUserProvider(
        name: 'Test',
        email: 't@t.com',
        role: 'PATIENT',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      expect(find.text('Settings Page'), findsOneWidget);
    });

    testWidgets('TC-RBD-047: tapping Tasks navigates to /tasks', (tester) async {
      final provider = _SessionUserProvider(
        name: 'Test',
        email: 't@t.com',
        role: 'PATIENT',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Tasks'));
      await tester.pumpAndSettle();

      expect(find.text('Tasks Page'), findsOneWidget);
    });

    testWidgets('TC-RBD-048: tapping Analytics navigates to /analytics for CAREGIVER',
        (tester) async {
      final provider = _SessionUserProvider(
        name: 'Dan',
        email: 'd@t.com',
        role: 'CAREGIVER',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Analytics'));
      await tester.pumpAndSettle();

      expect(find.text('Analytics Page'), findsOneWidget);
    });

    testWidgets('TC-RBD-049: tapping My Patients navigates to /patients for CAREGIVER',
        (tester) async {
      final provider = _SessionUserProvider(
        name: 'Dan',
        email: 'd@t.com',
        role: 'CAREGIVER',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Expand Patient Management
      await tester.tap(find.text('Patient Management'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('My Patients'));
      await tester.pumpAndSettle();

      expect(find.text('Patients Page'), findsOneWidget);
    });

    testWidgets('TC-RBD-050: tapping Add Patient navigates to /patients/add for CAREGIVER',
        (tester) async {
      final provider = _SessionUserProvider(
        name: 'Dan',
        email: 'd@t.com',
        role: 'CAREGIVER',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Expand Patient Management
      await tester.tap(find.text('Patient Management'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Patient'));
      await tester.pumpAndSettle();

      expect(find.text('Add Patient Page'), findsOneWidget);
    });

    testWidgets('TC-RBD-051: tapping User Management navigates to /admin/users for ADMIN',
        (tester) async {
      final provider = _SessionUserProvider(
        name: 'Admin',
        email: 'a@t.com',
        role: 'ADMIN',
      );
      // User Management navigates with context.go(), so it needs a GoRouter.
      await tester.pumpWidget(_wrapRouter(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Expand Administration
      await tester.tap(find.text('Administration'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('User Management'));
      await tester.pumpAndSettle();

      expect(find.text('User Mgmt Page'), findsOneWidget);
    });

    // ---- PR #428 review (2026-10-25), Testing Lead ----

    testWidgets(
        'TC-RBD-056: an ADMIN on an admin page opens Health Data from the '
        'menu, and Back returns to that page (DEF-MCR-38)', (tester) async {
      final provider = _SessionUserProvider(
        name: 'Admin',
        email: 'a@t.com',
        role: 'ADMIN',
      );
      await tester.pumpWidget(_wrapRouter(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Health Data'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Health Page'), findsOneWidget);
      expect(find.byType(Drawer), findsNothing);

      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Open'), findsOneWidget);
    });
  });

  group('RoleBasedDrawer – logout functionality', () {
    testWidgets('TC-RBD-052: tapping Logout shows confirmation dialog', (tester) async {
      final provider = _SessionUserProvider(
        name: 'Test',
        email: 't@t.com',
        role: 'PATIENT',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Logout'));
      await tester.pumpAndSettle();

      // Confirmation dialog should appear
      expect(find.text('Are you sure you want to logout?'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      // Both the menu item "Logout" (behind the dialog) and the dialog button "Logout"
      expect(find.text('Logout'), findsAtLeastNWidgets(1));
    });

    testWidgets('TC-RBD-053: cancelling logout dialog does not navigate away',
        (tester) async {
      final provider = _SessionUserProvider(
        name: 'Test',
        email: 't@t.com',
        role: 'PATIENT',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Logout'));
      await tester.pumpAndSettle();

      // Cancel the dialog
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Should still be on the home page (dialog dismissed)
      expect(find.text('Are you sure you want to logout?'), findsNothing);
      // The drawer may have closed, so we may not see its items
      expect(find.text('Login Page'), findsNothing);
    });
  });

  group('RoleBasedDrawer – ExpansionTile children visibility', () {
    testWidgets(
        'TC-RBD-054: Administration ExpansionTile has User Management and no dead Role Management link',
        (tester) async {
      final provider = _SessionUserProvider(
        name: 'Admin',
        email: 'a@t.com',
        role: 'ADMIN',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Expand
      await tester.tap(find.text('Administration'));
      await tester.pumpAndSettle();

      expect(find.text('User Management'), findsOneWidget);
      expect(find.byIcon(Icons.people), findsOneWidget);
      // No /admin/roles route exists, so the drawer must not link to it.
      expect(find.text('Role Management'), findsNothing);
      expect(find.byIcon(Icons.security), findsNothing);
    });

    testWidgets(
        'TC-RBD-055: Patient Management ExpansionTile has My Patients and Add Patient',
        (tester) async {
      final provider = _SessionUserProvider(
        name: 'Care',
        email: 'c@t.com',
        role: 'CAREGIVER',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Expand
      await tester.tap(find.text('Patient Management'));
      await tester.pumpAndSettle();

      expect(find.text('My Patients'), findsOneWidget);
      expect(find.text('Add Patient'), findsOneWidget);
      expect(find.byIcon(Icons.person_search), findsOneWidget);
      expect(find.byIcon(Icons.person_add), findsOneWidget);
    });
  });
}
