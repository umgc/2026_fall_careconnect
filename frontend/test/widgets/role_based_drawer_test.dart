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
      '/admin/roles': (_) => const Scaffold(body: Text('Role Mgmt Page')),
      '/patients': (_) => const Scaffold(body: Text('Patients Page')),
      '/patients/add': (_) => const Scaffold(body: Text('Add Patient Page')),
      '/tasks': (_) => const Scaffold(body: Text('Tasks Page')),
      '/health': (_) => const Scaffold(body: Text('Health Page')),
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
    const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
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
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byType(Drawer), findsOneWidget);
    });

    testWidgets('shows "Not logged in" when userSession is null', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Not logged in'), findsOneWidget);
    });
  });

  group('RoleBasedDrawer – logged-in user', () {
    testWidgets('shows user name and email for PATIENT', (tester) async {
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

    testWidgets('shows Dashboard for all roles', (tester) async {
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

    testWidgets('shows Health Data for all roles', (tester) async {
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

    testWidgets('shows Messages for all roles', (tester) async {
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

    testWidgets('shows role badge text for Patient', (tester) async {
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

    testWidgets('does NOT show Administration for PATIENT', (tester) async {
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

    testWidgets('does NOT show Tasks for FAMILY_MEMBER', (tester) async {
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

    testWidgets('shows Tasks for CAREGIVER', (tester) async {
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

    testWidgets('shows Administration for ADMIN', (tester) async {
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

    testWidgets('shows Analytics for CAREGIVER', (tester) async {
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

    testWidgets('shows Patient Management for CAREGIVER', (tester) async {
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

    testWidgets('shows Logout for all logged-in users', (tester) async {
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

    testWidgets('shows Settings for all logged-in users', (tester) async {
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

    testWidgets('role badge shows Caregiver for CAREGIVER role', (tester) async {
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

    testWidgets('role badge shows Administrator for ADMIN role', (tester) async {
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

    testWidgets('role badge shows Family Member for FAMILY_MEMBER role', (tester) async {
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
    testWidgets('drawer contains UserAccountsDrawerHeader', (tester) async {
      final provider = _SessionUserProvider(
        name: 'Alice', email: 'a@t.com', role: 'PATIENT',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byType(UserAccountsDrawerHeader), findsOneWidget);
    });

    testWidgets('header shows first letter of name in avatar', (tester) async {
      final provider = _SessionUserProvider(
        name: 'Zach', email: 'z@t.com', role: 'PATIENT',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Z'), findsOneWidget);
    });

    testWidgets('header shows ? for empty name', (tester) async {
      final provider = _SessionUserProvider(
        name: '', email: 'e@t.com', role: 'PATIENT',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('?'), findsOneWidget);
    });

    testWidgets('drawer has dashboard icon', (tester) async {
      final provider = _SessionUserProvider(
        name: 'Test', email: 't@t.com', role: 'PATIENT',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.dashboard), findsOneWidget);
    });

    testWidgets('drawer has health_and_safety icon', (tester) async {
      final provider = _SessionUserProvider(
        name: 'Test', email: 't@t.com', role: 'PATIENT',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.health_and_safety), findsOneWidget);
    });

    testWidgets('drawer has message icon', (tester) async {
      final provider = _SessionUserProvider(
        name: 'Test', email: 't@t.com', role: 'PATIENT',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.message), findsOneWidget);
    });

    testWidgets('drawer has settings icon', (tester) async {
      final provider = _SessionUserProvider(
        name: 'Test', email: 't@t.com', role: 'PATIENT',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.settings), findsOneWidget);
    });

    testWidgets('drawer has logout icon', (tester) async {
      final provider = _SessionUserProvider(
        name: 'Test', email: 't@t.com', role: 'PATIENT',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.logout), findsOneWidget);
    });

    testWidgets('drawer has task icon for PATIENT', (tester) async {
      final provider = _SessionUserProvider(
        name: 'Test', email: 't@t.com', role: 'PATIENT',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.task), findsOneWidget);
    });

    testWidgets('drawer has analytics icon for ADMIN', (tester) async {
      final provider = _SessionUserProvider(
        name: 'Test', email: 't@t.com', role: 'ADMIN',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.analytics), findsOneWidget);
    });

    testWidgets('ADMIN drawer has admin_panel_settings icon', (tester) async {
      final provider = _SessionUserProvider(
        name: 'Test', email: 't@t.com', role: 'ADMIN',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.admin_panel_settings), findsOneWidget);
    });

    testWidgets('CAREGIVER drawer has people_outline icon for Patient Management', (tester) async {
      final provider = _SessionUserProvider(
        name: 'Test', email: 't@t.com', role: 'CAREGIVER',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.people_outline), findsOneWidget);
    });

    testWidgets('Dividers present in drawer', (tester) async {
      final provider = _SessionUserProvider(
        name: 'Test', email: 't@t.com', role: 'PATIENT',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byType(Divider), findsAtLeastNWidgets(2));
    });
  });

  group('RoleBasedDrawer – role-specific menu visibility', () {
    testWidgets('PATIENT does NOT see Patient Management', (tester) async {
      final provider = _SessionUserProvider(
        name: 'Pat', email: 'p@t.com', role: 'PATIENT',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Patient Management'), findsNothing);
    });

    testWidgets('PATIENT does NOT see Analytics', (tester) async {
      final provider = _SessionUserProvider(
        name: 'Pat', email: 'p@t.com', role: 'PATIENT',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Analytics'), findsNothing);
    });

    testWidgets('PATIENT sees Tasks', (tester) async {
      final provider = _SessionUserProvider(
        name: 'Pat', email: 'p@t.com', role: 'PATIENT',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Tasks'), findsOneWidget);
    });

    testWidgets('FAMILY_MEMBER does NOT see Analytics', (tester) async {
      final provider = _SessionUserProvider(
        name: 'Fam', email: 'f@t.com', role: 'FAMILY_MEMBER',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Analytics'), findsNothing);
    });

    testWidgets('FAMILY_MEMBER does NOT see Patient Management', (tester) async {
      final provider = _SessionUserProvider(
        name: 'Fam', email: 'f@t.com', role: 'FAMILY_MEMBER',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Patient Management'), findsNothing);
    });

    testWidgets('FAMILY_MEMBER does NOT see Administration', (tester) async {
      final provider = _SessionUserProvider(
        name: 'Fam', email: 'f@t.com', role: 'FAMILY_MEMBER',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Administration'), findsNothing);
    });

    testWidgets('FAMILY_MEMBER sees Dashboard, Health Data, Messages, Settings', (tester) async {
      final provider = _SessionUserProvider(
        name: 'Fam', email: 'f@t.com', role: 'FAMILY_MEMBER',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('Health Data'), findsOneWidget);
      expect(find.text('Messages'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('ADMIN sees Administration, Patient Management, Tasks, Analytics', (tester) async {
      final provider = _SessionUserProvider(
        name: 'Admin', email: 'a@t.com', role: 'ADMIN',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Administration'), findsOneWidget);
      expect(find.text('Patient Management'), findsOneWidget);
      expect(find.text('Tasks'), findsOneWidget);
      expect(find.text('Analytics'), findsOneWidget);
    });

    testWidgets('FAMILY_LINK sees Patient Management and Analytics', (tester) async {
      final provider = _SessionUserProvider(
        name: 'Link', email: 'l@t.com', role: 'FAMILY_LINK',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Patient Management'), findsOneWidget);
      expect(find.text('Analytics'), findsOneWidget);
    });

    testWidgets('FAMILY_LINK role badge shows Family Link', (tester) async {
      final provider = _SessionUserProvider(
        name: 'Link', email: 'l@t.com', role: 'FAMILY_LINK',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Family Link'), findsOneWidget);
    });

    testWidgets('unknown role shows raw role text', (tester) async {
      final provider = _SessionUserProvider(
        name: 'Unknown', email: 'u@t.com', role: 'CUSTOM_ROLE',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('CUSTOM_ROLE'), findsOneWidget);
    });
  });

  group('RoleBasedDrawer – menu item navigation', () {
    testWidgets('tapping Dashboard navigates to /dashboard', (tester) async {
      final provider = _SessionUserProvider(
        name: 'Test', email: 't@t.com', role: 'PATIENT',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Dashboard'));
      await tester.pumpAndSettle();

      expect(find.text('Dashboard Page'), findsOneWidget);
    });

    testWidgets('tapping Health Data navigates to /health', (tester) async {
      final provider = _SessionUserProvider(
        name: 'Test', email: 't@t.com', role: 'PATIENT',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Health Data'));
      await tester.pumpAndSettle();

      expect(find.text('Health Page'), findsOneWidget);
    });

    testWidgets('tapping Messages navigates to /messages', (tester) async {
      final provider = _SessionUserProvider(
        name: 'Test', email: 't@t.com', role: 'PATIENT',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Messages'));
      await tester.pumpAndSettle();

      expect(find.text('Messages Page'), findsOneWidget);
    });

    testWidgets('tapping Settings navigates to /settings', (tester) async {
      final provider = _SessionUserProvider(
        name: 'Test', email: 't@t.com', role: 'PATIENT',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      expect(find.text('Settings Page'), findsOneWidget);
    });

    testWidgets('tapping Tasks navigates to /tasks', (tester) async {
      final provider = _SessionUserProvider(
        name: 'Test', email: 't@t.com', role: 'PATIENT',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Tasks'));
      await tester.pumpAndSettle();

      expect(find.text('Tasks Page'), findsOneWidget);
    });

    testWidgets('tapping Analytics navigates to /analytics for CAREGIVER', (tester) async {
      final provider = _SessionUserProvider(
        name: 'Dan', email: 'd@t.com', role: 'CAREGIVER',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Analytics'));
      await tester.pumpAndSettle();

      expect(find.text('Analytics Page'), findsOneWidget);
    });

    testWidgets('tapping My Patients navigates to /patients for CAREGIVER', (tester) async {
      final provider = _SessionUserProvider(
        name: 'Dan', email: 'd@t.com', role: 'CAREGIVER',
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

    testWidgets('tapping Add Patient navigates to /patients/add for CAREGIVER', (tester) async {
      final provider = _SessionUserProvider(
        name: 'Dan', email: 'd@t.com', role: 'CAREGIVER',
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

    testWidgets('tapping User Management navigates to /admin/users for ADMIN', (tester) async {
      final provider = _SessionUserProvider(
        name: 'Admin', email: 'a@t.com', role: 'ADMIN',
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

    testWidgets('tapping Role Management navigates to /admin/roles for ADMIN', (tester) async {
      final provider = _SessionUserProvider(
        name: 'Admin', email: 'a@t.com', role: 'ADMIN',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Expand Administration
      await tester.tap(find.text('Administration'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Role Management'));
      await tester.pumpAndSettle();

      expect(find.text('Role Mgmt Page'), findsOneWidget);
    });
  });

  group('RoleBasedDrawer – logout functionality', () {
    testWidgets('tapping Logout shows confirmation dialog', (tester) async {
      final provider = _SessionUserProvider(
        name: 'Test', email: 't@t.com', role: 'PATIENT',
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

    testWidgets('cancelling logout dialog does not navigate away', (tester) async {
      final provider = _SessionUserProvider(
        name: 'Test', email: 't@t.com', role: 'PATIENT',
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
    testWidgets('Administration ExpansionTile has User Management and Role Management', (tester) async {
      final provider = _SessionUserProvider(
        name: 'Admin', email: 'a@t.com', role: 'ADMIN',
      );
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Expand
      await tester.tap(find.text('Administration'));
      await tester.pumpAndSettle();

      expect(find.text('User Management'), findsOneWidget);
      expect(find.text('Role Management'), findsOneWidget);
      expect(find.byIcon(Icons.people), findsOneWidget);
      expect(find.byIcon(Icons.security), findsOneWidget);
    });

    testWidgets('Patient Management ExpansionTile has My Patients and Add Patient', (tester) async {
      final provider = _SessionUserProvider(
        name: 'Care', email: 'c@t.com', role: 'CAREGIVER',
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
