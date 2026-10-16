// Tests for SettingsScreen
// (lib/features/profile/presentation/pages/settings_screen.dart).
//
// initState calls loadUserInfo() which uses SharedPreferences (async, no API).
// No API calls, no Provider needed on initial render.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:care_connect_app/features/profile/presentation/pages/settings_screen.dart';

Widget _wrap() => const MaterialApp(home: SettingsScreen());

/// Wraps SettingsScreen in a GoRouter so context.go('/') works in tests.
Widget _wrapWithRouter() {
  final router = GoRouter(
    initialLocation: '/settings',
    routes: [
      GoRoute(path: '/', builder: (_, __) => const Scaffold(body: Text('Welcome'))),
      GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
    ],
  );
  return MaterialApp.router(routerConfig: router);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SettingsScreen – initial render', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(SettingsScreen), findsOneWidget);
    });

    testWidgets('shows "Settings" in AppBar', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('shows Scaffold', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows "Change Password" option', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump(); // let SharedPreferences resolve
      expect(find.text('Change Password'), findsOneWidget);
    });

    testWidgets('does NOT show CircularProgressIndicator', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('SettingsScreen – with user data', () {
    testWidgets('shows user name from SharedPreferences', (tester) async {
      SharedPreferences.setMockInitialValues({'userName': 'Alice'});
      await tester.pumpWidget(_wrap());
      await tester.pump(); // let loadUserInfo async complete
      expect(find.text('Alice'), findsOneWidget);
    });

    testWidgets('shows "User" when no userName is stored', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('User'), findsOneWidget);
    });

    testWidgets('shows Upload Avatar button', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('Upload Avatar'), findsOneWidget);
      expect(find.byIcon(Icons.camera_alt), findsOneWidget);
    });

    testWidgets('shows Logout option', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('Logout'), findsOneWidget);
      expect(find.byIcon(Icons.logout), findsOneWidget);
    });

    testWidgets('shows lock icon for Change Password', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byIcon(Icons.lock), findsOneWidget);
    });

    testWidgets('shows Divider between sections', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byType(Divider), findsOneWidget);
    });

    testWidgets('shows UserAvatar widget', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byType(CircleAvatar), findsOneWidget);
    });

    testWidgets('tapping Change Password does not crash', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      await tester.tap(find.text('Change Password'));
      await tester.pump();
      // No-op tap handler — just verify no crash
      expect(find.byType(SettingsScreen), findsOneWidget);
    });

    testWidgets('shows person icon when no profile image', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byIcon(Icons.person), findsOneWidget);
    });

    testWidgets('shows two ListTiles', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byType(ListTile), findsNWidgets(2));
    });

    testWidgets('shows ElevatedButton for Upload Avatar', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byType(ElevatedButton), findsOneWidget);
    });
  });

  group('SettingsScreen – Logout', () {
    testWidgets('tapping Logout clears SharedPreferences and navigates', (tester) async {
      SharedPreferences.setMockInitialValues({
        'userName': 'TestUser',
      });

      await tester.pumpWidget(_wrapWithRouter());
      await tester.pump(); // let loadUserInfo resolve

      // Verify user name is displayed before logout
      expect(find.text('TestUser'), findsOneWidget);

      // Tap Logout
      await tester.tap(find.text('Logout'));
      await tester.pumpAndSettle();

      // After logout, GoRouter navigates to '/' which shows 'Welcome'
      expect(find.text('Welcome'), findsOneWidget);

      // Verify SharedPreferences was cleared
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('userName'), isNull);
    });

    testWidgets('tapping Logout does not crash when prefs are empty', (tester) async {
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(_wrapWithRouter());
      await tester.pump();

      await tester.tap(find.text('Logout'));
      await tester.pumpAndSettle();

      // Should navigate to welcome without crashing
      expect(find.text('Welcome'), findsOneWidget);
    });
  });
}
