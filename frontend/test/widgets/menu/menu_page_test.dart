// Tests for MenuPage
// (lib/widgets/menu/menu_page.dart).
//
// Coverage strategy:
//   MenuPage has two top-level branches in its build method:
//     - user == null  → renders _LoggedOutPrompt (tested here fully).
//     - user != null  → renders the full menu grid; this path requires
//                       GoRouter and LocaleProvider in the widget tree.
//
//   Branches tested:
//     null-user build    — _LoggedOutPrompt is rendered; shows 'Menu' appbar
//                          title and the login button from AppLocalizations.
//     logged-in build    — menu scaffold renders with the Tools section header
//                          and at least one tool tile.
//
//   Note: interactive callbacks (context.push, context.go) are NOT triggered
//   in these tests, so GoRouter is only needed for the logged-in tree.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/providers/locale_provider.dart';
import 'package:care_connect_app/providers/theme_provider.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/widgets/menu/menu_page.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Wraps [child] with all providers and localization needed by MenuPage.
/// [session] is set on the UserProvider when provided.
Widget _buildApp({UserSession? session, Widget? child}) {
  final userProvider = UserProvider();
  if (session != null) userProvider.setUser(session);

  // Minimal router: only the shell route for MenuPage.
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => child ?? const MenuPage(),
      ),
      GoRoute(path: '/login', builder: (_, __) => const SizedBox()),
      GoRoute(path: '/profile', builder: (_, __) => const SizedBox()),
      GoRoute(path: '/subscription', builder: (_, __) => const SizedBox()),
    ],
  );

  return MultiProvider(
    providers: [
      ChangeNotifierProvider<UserProvider>.value(value: userProvider),
      ChangeNotifierProvider<LocaleProvider>(create: (_) => LocaleProvider()),
      ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // ─── Null-user (logged-out) branch ───────────────────────────────────────

  group('MenuPage – null user', () {
    testWidgets('renders the Menu app bar title', (tester) async {
      // Verifies the scaffold app bar appears with the localised title.
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      // AppBar title comes from AppLocalizations.menuTitle → 'Menu'.
      expect(find.text('Menu'), findsOneWidget);
    });

    testWidgets('renders the login button', (tester) async {
      // Verifies _LoggedOutPrompt's ElevatedButton is present.
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      // The English localisation for login is 'Sign In' or 'Login'.
      expect(find.byType(ElevatedButton), findsOneWidget);
    });
  });

  // ─── Logged-in user branch ────────────────────────────────────────────────

  group('MenuPage – logged-in CAREGIVER', () {
    late UserSession caregiverSession;

    setUp(() {
      caregiverSession = UserSession(
        id: 1,
        email: 'cg@example.com',
        role: 'CAREGIVER',
        token: 'test-token',
        name: 'Care Giver',
      );
    });

    testWidgets('Team C smoke: renders logged-in menu integration surfaces',
        (tester) async {
      await tester.pumpWidget(_buildApp(session: caregiverSession));
      await tester.pumpAndSettle();

      expect(find.text('Menu'), findsOneWidget);
      expect(find.text('Care Giver'), findsOneWidget);
      expect(find.text('CAREGIVER'), findsOneWidget);
      expect(find.text('Tools'), findsOneWidget);
      expect(find.byType(Card), findsWidgets);
      expect(find.byIcon(Icons.logout, skipOffstage: false), findsOneWidget);
      expect(find.text('Preferences', skipOffstage: false), findsOneWidget);
    });

    testWidgets('renders the Tools section header', (tester) async {
      // Verifies that the grid section header for Tools is present.
      await tester.pumpWidget(_buildApp(session: caregiverSession));
      await tester.pumpAndSettle();

      // The 'Tools' section header comes from AppLocalizations.tools.
      expect(find.text('Tools'), findsOneWidget);
    });

    testWidgets('renders the Preferences section header', (tester) async {
      // Verifies the Preferences section header appears.
      await tester.pumpWidget(_buildApp(session: caregiverSession));
      await tester.pumpAndSettle();

      // 'Preferences' may be scrolled off the initial viewport.
      expect(find.text('Preferences', skipOffstage: false), findsOneWidget);
    });

    testWidgets('renders at least one tool tile', (tester) async {
      // Verifies that the nav-item grid is populated with at least one card.
      await tester.pumpWidget(_buildApp(session: caregiverSession));
      await tester.pumpAndSettle();

      // Each tool tile is a Card inside an InkWell.
      expect(find.byType(Card), findsWidgets);
    });
  });
}
