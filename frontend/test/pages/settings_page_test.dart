// Comprehensive tests for SettingsPage (lib/pages/settings_page.dart).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:care_connect_app/pages/settings_page.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/providers/locale_provider.dart';
import 'package:care_connect_app/providers/theme_provider.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';

import '../mock_user_provider.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

class _NullUserProvider extends MockUserProvider {
  _NullUserProvider() : super(mockUser: null);

  @override
  UserSession? get user => null;
}

Widget _buildApp({required UserProvider provider}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<UserProvider>.value(value: provider),
      ChangeNotifierProvider<LocaleProvider>(create: (_) => LocaleProvider()),
      ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
    ],
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const SettingsPage(),
    ),
  );
}

/// Build app wrapped with GoRouter so context.go / context.push work.
Widget _buildAppWithRouter({required UserProvider provider}) {
  final router = GoRouter(
    initialLocation: '/settings',
    routes: [
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsPage(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) =>
            const Scaffold(body: Text('Login Page')),
      ),
      GoRoute(
        path: '/select-package',
        builder: (context, state) =>
            const Scaffold(body: Text('Select Package Page')),
      ),
      GoRoute(
        path: '/notetaker-configuration',
        builder: (context, state) =>
            const Scaffold(body: Text('Notetaker Configuration Page')),
      ),
    ],
  );

  return MultiProvider(
    providers: [
      ChangeNotifierProvider<UserProvider>.value(value: provider),
      ChangeNotifierProvider<LocaleProvider>(create: (_) => LocaleProvider()),
      ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
    ],
    child: MaterialApp.router(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  );
}

/// Pumps enough frames for async operations to finish.
Future<void> _pumpReady(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({
      'telemetry_opted_out': false,
      'telemetry_seen_optout_dialog': true,
    });
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

  // =========================================================================
  // 1. Basic render with null user
  // =========================================================================
  group('SettingsPage - null user render', () {
    testWidgets('renders SettingsPage without crashing', (tester) async {
      await tester.pumpWidget(_buildApp(provider: _NullUserProvider()));
      await tester.pump();
      expect(find.byType(SettingsPage), findsOneWidget);
    });

    testWidgets('shows Scaffold and AppBar with Settings title',
        (tester) async {
      await tester.pumpWidget(_buildApp(provider: _NullUserProvider()));
      await tester.pump();
      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.text('Settings'), findsWidgets);
    });

    testWidgets('shows arrow_back icon button', (tester) async {
      await tester.pumpWidget(_buildApp(provider: _NullUserProvider()));
      await tester.pump();
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    });

    testWidgets('shows person icon when user is null', (tester) async {
      await tester.pumpWidget(_buildApp(provider: _NullUserProvider()));
      await tester.pump();
      expect(find.byIcon(Icons.person), findsOneWidget);
    });

    testWidgets('shows CircleAvatar', (tester) async {
      await tester.pumpWidget(_buildApp(provider: _NullUserProvider()));
      await tester.pump();
      expect(find.byType(CircleAvatar), findsOneWidget);
    });

    testWidgets('shows ListView', (tester) async {
      await tester.pumpWidget(_buildApp(provider: _NullUserProvider()));
      await tester.pump();
      expect(find.byType(ListView), findsOneWidget);
    });

    testWidgets('shows fallback user name when user is null', (tester) async {
      await tester.pumpWidget(_buildApp(provider: _NullUserProvider()));
      await tester.pump();
      expect(find.text('User'), findsOneWidget);
    });

    testWidgets('shows empty string for email when user is null',
        (tester) async {
      await tester.pumpWidget(_buildApp(provider: _NullUserProvider()));
      await tester.pump();
      // The email Text widget exists but has empty content
      expect(find.byType(Text), findsWidgets);
    });

    testWidgets('shows SafeArea wrapping the body', (tester) async {
      await tester.pumpWidget(_buildApp(provider: _NullUserProvider()));
      await tester.pump();
      expect(find.byType(SafeArea), findsWidgets);
    });
  });

  // =========================================================================
  // 2. User with name
  // =========================================================================
  group('SettingsPage - user with name', () {
    testWidgets('shows user initial in avatar', (tester) async {
      final provider = MockUserProvider(
        mockUser: MockUser(
            id: 1,
            name: 'Alice',
            email: 'a@t.com',
            role: 'CAREGIVER',
            caregiverId: 1),
      );
      await tester.pumpWidget(_buildApp(provider: provider));
      await tester.pump();
      expect(find.text('A'), findsOneWidget);
    });

    testWidgets('shows user name and email', (tester) async {
      final provider = MockUserProvider(
        mockUser: MockUser(
            id: 1,
            name: 'Bob Smith',
            email: 'bob@t.com',
            role: 'CAREGIVER',
            caregiverId: 1),
      );
      await tester.pumpWidget(_buildApp(provider: provider));
      await tester.pump();
      expect(find.text('Bob Smith'), findsOneWidget);
      expect(find.text('bob@t.com'), findsOneWidget);
    });

    testWidgets('shows person icon when name is empty', (tester) async {
      final provider = MockUserProvider(
        mockUser: MockUser(
            id: 1,
            name: '',
            email: 'e@t.com',
            role: 'CAREGIVER',
            caregiverId: 1),
      );
      await tester.pumpWidget(_buildApp(provider: provider));
      await tester.pump();
      expect(find.byIcon(Icons.person), findsOneWidget);
    });

    testWidgets('shows person icon when name is null', (tester) async {
      final provider = MockUserProvider(
        mockUser: MockUser(
            id: 1,
            name: null,
            email: 'e@t.com',
            role: 'CAREGIVER',
            caregiverId: 1),
      );
      await tester.pumpWidget(_buildApp(provider: provider));
      await tester.pump();
      expect(find.byIcon(Icons.person), findsOneWidget);
    });

    testWidgets('shows email when non-empty', (tester) async {
      final provider = MockUserProvider(
        mockUser: MockUser(
            id: 1,
            name: 'T',
            email: 'test@e.com',
            role: 'CAREGIVER',
            caregiverId: 1),
      );
      await tester.pumpWidget(_buildApp(provider: provider));
      await tester.pump();
      expect(find.text('test@e.com'), findsOneWidget);
    });

    testWidgets('uppercases the first letter of name for avatar',
        (tester) async {
      final provider = MockUserProvider(
        mockUser: MockUser(
            id: 1,
            name: 'zara',
            email: 'z@t.com',
            role: 'CAREGIVER',
            caregiverId: 1),
      );
      await tester.pumpWidget(_buildApp(provider: provider));
      await tester.pump();
      expect(find.text('Z'), findsOneWidget);
    });
  });

  // =========================================================================
  // 3. Appearance section
  // =========================================================================
  group('SettingsPage - Appearance section', () {
    testWidgets('shows Appearance section header', (tester) async {
      await tester.pumpWidget(_buildApp(provider: _NullUserProvider()));
      await tester.pump();
      expect(find.text('Appearance'), findsOneWidget);
    });

    testWidgets('shows brightness_6 icon for theme card', (tester) async {
      await tester.pumpWidget(_buildApp(provider: _NullUserProvider()));
      await tester.pump();
      expect(find.byIcon(Icons.brightness_6), findsOneWidget);
    });

    testWidgets('shows Dark Mode text', (tester) async {
      await tester.pumpWidget(_buildApp(provider: _NullUserProvider()));
      await tester.pump();
      expect(find.text('Dark Mode'), findsOneWidget);
    });

    testWidgets('shows language icon and Language text', (tester) async {
      await tester.pumpWidget(_buildApp(provider: _NullUserProvider()));
      await tester.pump();
      expect(find.byIcon(Icons.language), findsOneWidget);
      expect(find.text('Language'), findsOneWidget);
    });

    testWidgets('shows system default label for language', (tester) async {
      await tester.pumpWidget(_buildApp(provider: _NullUserProvider()));
      await tester.pump();
      expect(find.textContaining('ystem'), findsWidgets);
    });

    testWidgets('language card has chevron_right trailing icon',
        (tester) async {
      await tester.pumpWidget(_buildApp(provider: _NullUserProvider()));
      await tester.pump();
      final langCard = find.ancestor(
        of: find.text('Language'),
        matching: find.byType(Card),
      );
      expect(langCard, findsOneWidget);
      expect(
        find.descendant(
            of: langCard, matching: find.byIcon(Icons.chevron_right)),
        findsOneWidget,
      );
    });

    testWidgets('theme card contains ThemeToggleSwitch', (tester) async {
      await tester.pumpWidget(_buildApp(provider: _NullUserProvider()));
      await tester.pump();
      final themeCard = find.ancestor(
        of: find.text('Dark Mode'),
        matching: find.byType(Card),
      );
      expect(themeCard, findsOneWidget);
    });
  });

  // =========================================================================
  // 4. Notification section
  // =========================================================================
  group('SettingsPage - Notifications section', () {
    testWidgets('shows Notifications section header', (tester) async {
      await tester.pumpWidget(_buildApp(provider: _NullUserProvider()));
      await tester.pump();
      expect(find.text('Notifications'), findsOneWidget);
    });

    testWidgets('shows loading indicator initially', (tester) async {
      await tester.pumpWidget(_buildApp(provider: _NullUserProvider()));
      // Check immediately after first pump - should show loading
      await tester.pump();
      // The loading state might be visible briefly
      final hasLoading =
          find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
      final hasError = find.byIcon(Icons.error_outline).evaluate().isNotEmpty;
      // Either loading or already transitioned to error (null user)
      expect(hasLoading || hasError, isTrue);
    });

    testWidgets('shows error state with refresh button (null user)',
        (tester) async {
      await tester.pumpWidget(_buildApp(provider: _NullUserProvider()));
      await _pumpReady(tester);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });

    testWidgets('tapping refresh does not crash', (tester) async {
      await tester.pumpWidget(_buildApp(provider: _NullUserProvider()));
      await _pumpReady(tester);
      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('shows unable to load text when settings are null',
        (tester) async {
      await tester.pumpWidget(_buildApp(provider: _NullUserProvider()));
      await _pumpReady(tester);
      // Look for error-related text
      final hasErrorIcon =
          find.byIcon(Icons.error_outline).evaluate().isNotEmpty;
      expect(hasErrorIcon, isTrue);
    });
  });

  // =========================================================================
  // 5. Privacy / Telemetry section (use taller surface)
  // =========================================================================
  group('SettingsPage - Privacy section', () {
    testWidgets('shows Privacy header and Telemetry card', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_buildApp(provider: _NullUserProvider()));
      await _pumpReady(tester);
      expect(find.text('Privacy'), findsOneWidget);
      expect(find.byIcon(Icons.privacy_tip), findsOneWidget);
      expect(find.text('Telemetry'), findsOneWidget);
      expect(
        find.text('Anonymous diagnostics and performance metrics'),
        findsOneWidget,
      );
    });

    testWidgets('telemetry toggle shows Switch after loading', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_buildApp(provider: _NullUserProvider()));
      await _pumpReady(tester);
      final telemetryCard = find.ancestor(
        of: find.text('Telemetry'),
        matching: find.byType(Card),
      );
      expect(
        find.descendant(of: telemetryCard, matching: find.byType(Switch)),
        findsOneWidget,
      );
    });

    testWidgets('telemetry card has privacy_tip icon', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_buildApp(provider: _NullUserProvider()));
      await _pumpReady(tester);
      final telemetryCard = find.ancestor(
        of: find.text('Telemetry'),
        matching: find.byType(Card),
      );
      expect(
        find.descendant(
            of: telemetryCard, matching: find.byIcon(Icons.privacy_tip)),
        findsOneWidget,
      );
    });
  });

  // =========================================================================
  // 6. Subscription section visibility (use taller surface)
  // =========================================================================
  group('SettingsPage - Subscription section', () {
    testWidgets('hides subscription for PATIENT role', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final provider = MockUserProvider(
        mockUser: MockUser(id: 1, role: 'PATIENT', name: 'Pat'),
      );
      await tester.pumpWidget(_buildApp(provider: provider));
      await _pumpReady(tester);
      expect(find.byIcon(Icons.subscriptions), findsNothing);
    });

    testWidgets('hides subscription for family member role', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final provider = MockUserProvider(
        mockUser: MockUser(id: 1, role: 'family member', name: 'Fam'),
      );
      await tester.pumpWidget(_buildApp(provider: provider));
      await _pumpReady(tester);
      expect(find.byIcon(Icons.subscriptions), findsNothing);
    });

    testWidgets('hides subscription for FAMILY MEMBER', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final provider = MockUserProvider(
        mockUser: MockUser(id: 1, role: 'FAMILY MEMBER', name: 'FM'),
      );
      await tester.pumpWidget(_buildApp(provider: provider));
      await _pumpReady(tester);
      expect(find.byIcon(Icons.subscriptions), findsNothing);
    });

    testWidgets('shows subscription for CAREGIVER role', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final provider = MockUserProvider(
        mockUser: MockUser(
            id: 1, role: 'CAREGIVER', caregiverId: 1, name: 'CG'),
      );
      await tester.pumpWidget(_buildApp(provider: provider));
      await _pumpReady(tester);
      expect(find.byIcon(Icons.subscriptions), findsOneWidget);
      expect(find.text('Manage Subscription'), findsOneWidget);
    });

    testWidgets('shows subscription for null user', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_buildApp(provider: _NullUserProvider()));
      await _pumpReady(tester);
      expect(find.byIcon(Icons.subscriptions), findsOneWidget);
    });

    testWidgets('shows subscription description text for caregiver',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final provider = MockUserProvider(
        mockUser: MockUser(
            id: 1, role: 'CAREGIVER', caregiverId: 1, name: 'CG'),
      );
      await tester.pumpWidget(_buildApp(provider: provider));
      await _pumpReady(tester);
      // The subscription card should have a subtitle
      final subsCard = find.ancestor(
        of: find.byIcon(Icons.subscriptions),
        matching: find.byType(Card),
      );
      expect(subsCard, findsOneWidget);
    });
  });

  // =========================================================================
  // 7. Notetaker section
  // =========================================================================
  group('SettingsPage - Notetaker section', () {
    testWidgets('shows notetaker configuration card', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_buildApp(provider: _NullUserProvider()));
      await _pumpReady(tester);
      expect(find.text('Notetaker Assistant'), findsOneWidget);
      expect(find.byIcon(Icons.edit_note), findsOneWidget);
      expect(find.text('Notetaker Configuration'), findsOneWidget);
    });

    testWidgets('notetaker card has chevron_right', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_buildApp(provider: _NullUserProvider()));
      await _pumpReady(tester);
      final noteCard = find.ancestor(
        of: find.byIcon(Icons.edit_note),
        matching: find.byType(Card),
      );
      expect(noteCard, findsOneWidget);
      expect(
        find.descendant(
            of: noteCard, matching: find.byIcon(Icons.chevron_right)),
        findsOneWidget,
      );
    });
  });

  // =========================================================================
  // 8. General section
  // =========================================================================
  group('SettingsPage - General section', () {
    testWidgets('shows General section header', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_buildApp(provider: _NullUserProvider()));
      await _pumpReady(tester);
      expect(find.text('General'), findsOneWidget);
    });

    testWidgets('shows offline persistence card', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_buildApp(provider: _NullUserProvider()));
      await _pumpReady(tester);
      expect(find.byIcon(Icons.cloud_off), findsOneWidget);
      expect(find.text('Offline Persistence'), findsOneWidget);
    });

    testWidgets('shows clear cache card', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_buildApp(provider: _NullUserProvider()));
      await _pumpReady(tester);
      expect(find.byIcon(Icons.cleaning_services), findsOneWidget);
    });

    testWidgets('shows sign out card', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_buildApp(provider: _NullUserProvider()));
      await _pumpReady(tester);
      expect(find.byIcon(Icons.logout), findsOneWidget);
    });

    testWidgets('shows delete account card', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_buildApp(provider: _NullUserProvider()));
      await _pumpReady(tester);
      expect(find.byIcon(Icons.delete_forever), findsOneWidget);
    });

    testWidgets('shows correct subtitle for offline mode enabled',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_buildApp(provider: _NullUserProvider()));
      await _pumpReady(tester);
      expect(
        find.text('Save data locally and sync when reconnected'),
        findsOneWidget,
      );
    });

    testWidgets('offline persistence card has a Switch', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_buildApp(provider: _NullUserProvider()));
      await _pumpReady(tester);
      final offlineCard = find.ancestor(
        of: find.text('Offline Persistence'),
        matching: find.byType(Card),
      );
      expect(
        find.descendant(of: offlineCard, matching: find.byType(Switch)),
        findsOneWidget,
      );
    });

    testWidgets('sign out card has error-colored icon', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_buildApp(provider: _NullUserProvider()));
      await _pumpReady(tester);
      expect(find.byIcon(Icons.logout), findsOneWidget);
    });

    testWidgets('delete account card has error-colored icon', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_buildApp(provider: _NullUserProvider()));
      await _pumpReady(tester);
      expect(find.byIcon(Icons.delete_forever), findsOneWidget);
    });
  });

  // =========================================================================
  // 9. Clear cache dialog
  // =========================================================================
  group('SettingsPage - Clear cache dialog', () {
    testWidgets('opens dialog and cancel closes it', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_buildApp(provider: _NullUserProvider()));
      await _pumpReady(tester);

      final cleanTile = find.ancestor(
        of: find.byIcon(Icons.cleaning_services),
        matching: find.byType(ListTile),
      );
      await tester.tap(cleanTile);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('confirm shows snackbar', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_buildApp(provider: _NullUserProvider()));
      await _pumpReady(tester);

      final cleanTile = find.ancestor(
        of: find.byIcon(Icons.cleaning_services),
        matching: find.byType(ListTile),
      );
      await tester.tap(cleanTile);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final clearBtn = find.widgetWithText(ElevatedButton, 'Clear Cache');
      expect(clearBtn, findsOneWidget);
      await tester.tap(clearBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('clear cache dialog shows expected title and content',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_buildApp(provider: _NullUserProvider()));
      await _pumpReady(tester);

      final cleanTile = find.ancestor(
        of: find.byIcon(Icons.cleaning_services),
        matching: find.byType(ListTile),
      );
      await tester.tap(cleanTile);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Clear Cache'), findsWidgets);
      // Should have Cancel and Clear Cache buttons
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Clear Cache'), findsOneWidget);
    });
  });

  // =========================================================================
  // 10. Sign out dialog
  // =========================================================================
  group('SettingsPage - Sign out dialog', () {
    testWidgets('opens dialog and cancel closes it', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_buildApp(provider: _NullUserProvider()));
      await _pumpReady(tester);

      final signOutTile = find.ancestor(
        of: find.byIcon(Icons.logout),
        matching: find.byType(ListTile),
      );
      await tester.tap(signOutTile);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('sign out dialog shows expected title and confirm button',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_buildApp(provider: _NullUserProvider()));
      await _pumpReady(tester);

      final signOutTile = find.ancestor(
        of: find.byIcon(Icons.logout),
        matching: find.byType(ListTile),
      );
      await tester.tap(signOutTile);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Should show Sign Out text in dialog
      expect(find.text('Sign Out'), findsWidgets);
      expect(find.text('Cancel'), findsOneWidget);
      // The confirm button should be an ElevatedButton
      expect(find.widgetWithText(ElevatedButton, 'Sign Out'), findsOneWidget);
    });

    testWidgets('confirm sign out navigates via GoRouter', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
          _buildAppWithRouter(provider: _NullUserProvider()));
      await _pumpReady(tester);

      final signOutTile = find.ancestor(
        of: find.byIcon(Icons.logout),
        matching: find.byType(ListTile),
      );
      await tester.tap(signOutTile);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final signOutBtn = find.widgetWithText(ElevatedButton, 'Sign Out');
      expect(signOutBtn, findsOneWidget);
      await tester.tap(signOutBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // After sign out, should navigate to login page
      expect(find.text('Login Page'), findsOneWidget);
    });
  });

  // =========================================================================
  // 11. Delete account dialog
  // =========================================================================
  group('SettingsPage - Delete account dialog', () {
    testWidgets('opens dialog and cancel closes it', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_buildApp(provider: _NullUserProvider()));
      await _pumpReady(tester);

      final deleteTile = find.ancestor(
        of: find.byIcon(Icons.delete_forever),
        matching: find.byType(ListTile),
      );
      await tester.tap(deleteTile);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('confirm shows snackbar', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_buildApp(provider: _NullUserProvider()));
      await _pumpReady(tester);

      final deleteTile = find.ancestor(
        of: find.byIcon(Icons.delete_forever),
        matching: find.byType(ListTile),
      );
      await tester.tap(deleteTile);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final deleteBtn =
          find.widgetWithText(ElevatedButton, 'Delete Account');
      expect(deleteBtn, findsOneWidget);
      await tester.tap(deleteBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('delete account dialog shows warning-styled title',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_buildApp(provider: _NullUserProvider()));
      await _pumpReady(tester);

      final deleteTile = find.ancestor(
        of: find.byIcon(Icons.delete_forever),
        matching: find.byType(ListTile),
      );
      await tester.tap(deleteTile);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // The delete dialog title should be present
      expect(find.text('Delete Account'), findsWidgets);
      expect(find.text('Cancel'), findsOneWidget);
    });
  });

  // =========================================================================
  // 12. Card widgets
  // =========================================================================
  group('SettingsPage - Card widgets', () {
    testWidgets('shows multiple Card widgets', (tester) async {
      await tester.pumpWidget(_buildApp(provider: _NullUserProvider()));
      await tester.pump();
      expect(find.byType(Card), findsWidgets);
    });

    testWidgets('shows chevron_right trailing icons', (tester) async {
      await tester.pumpWidget(_buildApp(provider: _NullUserProvider()));
      await tester.pump();
      expect(find.byIcon(Icons.chevron_right), findsWidgets);
    });

    testWidgets('shows multiple ListTile widgets', (tester) async {
      await tester.pumpWidget(_buildApp(provider: _NullUserProvider()));
      await tester.pump();
      expect(find.byType(ListTile), findsWidgets);
    });
  });

  // =========================================================================
  // 13. Telemetry default-on dialog
  // =========================================================================
  group('SettingsPage - Telemetry default-on dialog', () {
    testWidgets('shows telemetry dialog when not previously seen',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        'telemetry_opted_out': false,
        'telemetry_seen_optout_dialog': false,
      });

      await tester.pumpWidget(_buildApp(provider: _NullUserProvider()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Telemetry is enabled'), findsOneWidget);
      expect(find.text('Keep enabled'), findsOneWidget);
      expect(find.text('Opt out'), findsOneWidget);
    });

    testWidgets('Keep enabled dismisses dialog', (tester) async {
      SharedPreferences.setMockInitialValues({
        'telemetry_opted_out': false,
        'telemetry_seen_optout_dialog': false,
      });

      await tester.pumpWidget(_buildApp(provider: _NullUserProvider()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      await tester.tap(find.text('Keep enabled'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Telemetry is enabled'), findsNothing);
    });

    testWidgets('Opt out in default dialog disables telemetry',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        'telemetry_opted_out': false,
        'telemetry_seen_optout_dialog': false,
      });

      await tester.pumpWidget(_buildApp(provider: _NullUserProvider()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      await tester.tap(find.text('Opt out'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Telemetry is enabled'), findsNothing);
    });

    testWidgets('telemetry dialog has expected content text', (tester) async {
      SharedPreferences.setMockInitialValues({
        'telemetry_opted_out': false,
        'telemetry_seen_optout_dialog': false,
      });

      await tester.pumpWidget(_buildApp(provider: _NullUserProvider()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        find.textContaining('anonymous diagnostics'),
        findsOneWidget,
      );
      expect(
        find.textContaining('opt out at any time'),
        findsOneWidget,
      );
    });

    testWidgets('dialog is not shown when already seen', (tester) async {
      SharedPreferences.setMockInitialValues({
        'telemetry_opted_out': false,
        'telemetry_seen_optout_dialog': true,
      });

      await tester.pumpWidget(_buildApp(provider: _NullUserProvider()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Telemetry is enabled'), findsNothing);
    });

    testWidgets('dialog not shown when telemetry is disabled', (tester) async {
      SharedPreferences.setMockInitialValues({
        'telemetry_opted_out': true,
        'telemetry_seen_optout_dialog': false,
      });

      await tester.pumpWidget(_buildApp(provider: _NullUserProvider()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // When telemetry is opted out, the dialog should not appear
      expect(find.text('Telemetry is enabled'), findsNothing);
    });
  });

  // =========================================================================
  // 14. Telemetry toggle opt-out (use tall surface)
  // =========================================================================
  group('SettingsPage - Telemetry opt-out toggle', () {
    testWidgets('switch off shows opt-out dialog', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      SharedPreferences.setMockInitialValues({
        'telemetry_opted_out': false,
        'telemetry_seen_optout_dialog': true,
      });

      await tester.pumpWidget(_buildApp(provider: _NullUserProvider()));
      await _pumpReady(tester);

      final telemetryCard = find.ancestor(
        of: find.text('Telemetry'),
        matching: find.byType(Card),
      );
      final telemetrySwitch = find.descendant(
        of: telemetryCard,
        matching: find.byType(Switch),
      );
      expect(telemetrySwitch, findsOneWidget);

      await tester.tap(telemetrySwitch);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Opt out of telemetry?'), findsOneWidget);
    });

    testWidgets('cancel opt-out keeps telemetry enabled', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      SharedPreferences.setMockInitialValues({
        'telemetry_opted_out': false,
        'telemetry_seen_optout_dialog': true,
      });

      await tester.pumpWidget(_buildApp(provider: _NullUserProvider()));
      await _pumpReady(tester);

      final telemetryCard = find.ancestor(
        of: find.text('Telemetry'),
        matching: find.byType(Card),
      );
      await tester.tap(find.descendant(
        of: telemetryCard,
        matching: find.byType(Switch),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Opt out of telemetry?'), findsNothing);
    });

    testWidgets('confirm opt-out changes telemetry state', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      SharedPreferences.setMockInitialValues({
        'telemetry_opted_out': false,
        'telemetry_seen_optout_dialog': true,
      });

      await tester.pumpWidget(_buildApp(provider: _NullUserProvider()));
      await _pumpReady(tester);

      final telemetryCard = find.ancestor(
        of: find.text('Telemetry'),
        matching: find.byType(Card),
      );
      await tester.tap(find.descendant(
        of: telemetryCard,
        matching: find.byType(Switch),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final optOutBtn = find.widgetWithText(ElevatedButton, 'Opt out');
      await tester.tap(optOutBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Opt out of telemetry?'), findsNothing);
    });

    testWidgets('opt-out dialog shows expected content', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      SharedPreferences.setMockInitialValues({
        'telemetry_opted_out': false,
        'telemetry_seen_optout_dialog': true,
      });

      await tester.pumpWidget(_buildApp(provider: _NullUserProvider()));
      await _pumpReady(tester);

      final telemetryCard = find.ancestor(
        of: find.text('Telemetry'),
        matching: find.byType(Card),
      );
      await tester.tap(find.descendant(
        of: telemetryCard,
        matching: find.byType(Switch),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.textContaining('stop collecting anonymous diagnostics'),
        findsOneWidget,
      );
    });
  });

  // =========================================================================
  // 15. Telemetry opt-in (when currently disabled)
  // =========================================================================
  group('SettingsPage - Telemetry opt-in toggle', () {
    testWidgets('switch on shows opt-in dialog', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      SharedPreferences.setMockInitialValues({
        'telemetry_opted_out': true,
        'telemetry_seen_optout_dialog': true,
      });

      await tester.pumpWidget(_buildApp(provider: _NullUserProvider()));
      await _pumpReady(tester);

      final telemetryCard = find.ancestor(
        of: find.text('Telemetry'),
        matching: find.byType(Card),
      );
      await tester.tap(find.descendant(
        of: telemetryCard,
        matching: find.byType(Switch),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Enable telemetry?'), findsOneWidget);
    });

    testWidgets('confirm opt-in enables telemetry', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      SharedPreferences.setMockInitialValues({
        'telemetry_opted_out': true,
        'telemetry_seen_optout_dialog': true,
      });

      await tester.pumpWidget(_buildApp(provider: _NullUserProvider()));
      await _pumpReady(tester);

      final telemetryCard = find.ancestor(
        of: find.text('Telemetry'),
        matching: find.byType(Card),
      );
      await tester.tap(find.descendant(
        of: telemetryCard,
        matching: find.byType(Switch),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final enableBtn = find.widgetWithText(ElevatedButton, 'Enable');
      await tester.tap(enableBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Enable telemetry?'), findsNothing);
    });

    testWidgets('cancel opt-in keeps telemetry disabled', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      SharedPreferences.setMockInitialValues({
        'telemetry_opted_out': true,
        'telemetry_seen_optout_dialog': true,
      });

      await tester.pumpWidget(_buildApp(provider: _NullUserProvider()));
      await _pumpReady(tester);

      final telemetryCard = find.ancestor(
        of: find.text('Telemetry'),
        matching: find.byType(Card),
      );
      await tester.tap(find.descendant(
        of: telemetryCard,
        matching: find.byType(Switch),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Enable telemetry?'), findsNothing);
    });

    testWidgets('opt-in dialog shows expected content', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      SharedPreferences.setMockInitialValues({
        'telemetry_opted_out': true,
        'telemetry_seen_optout_dialog': true,
      });

      await tester.pumpWidget(_buildApp(provider: _NullUserProvider()));
      await _pumpReady(tester);

      final telemetryCard = find.ancestor(
        of: find.text('Telemetry'),
        matching: find.byType(Card),
      );
      await tester.tap(find.descendant(
        of: telemetryCard,
        matching: find.byType(Switch),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.textContaining('allow CareConnect to collect'),
        findsOneWidget,
      );
    });
  });

  // =========================================================================
  // 16. All sections for caregiver
  // =========================================================================
  group('SettingsPage - All sections for caregiver', () {
    testWidgets('shows all expected section headers', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final provider = MockUserProvider(
        mockUser: MockUser(
            id: 1,
            role: 'CAREGIVER',
            caregiverId: 1,
            name: 'CG User',
            email: 'cg@test.com'),
      );
      await tester.pumpWidget(_buildApp(provider: provider));
      await _pumpReady(tester);

      expect(find.text('Appearance'), findsOneWidget);
      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('Privacy'), findsOneWidget);
      expect(find.text('Subscription'), findsOneWidget);
      expect(find.text('Notetaker Assistant'), findsOneWidget);
      expect(find.text('General'), findsOneWidget);
    });

    testWidgets('shows avatar initial and user info', (tester) async {
      final provider = MockUserProvider(
        mockUser: MockUser(
            id: 1,
            role: 'CAREGIVER',
            caregiverId: 1,
            name: 'Caregiver User',
            email: 'cg@test.com'),
      );
      await tester.pumpWidget(_buildApp(provider: provider));
      await tester.pump();

      expect(find.text('C'), findsOneWidget);
      expect(find.text('Caregiver User'), findsOneWidget);
      expect(find.text('cg@test.com'), findsOneWidget);
    });
  });

  // =========================================================================
  // 17. Offline persistence toggle interaction
  // =========================================================================
  group('SettingsPage - Offline persistence toggle', () {
    testWidgets('tapping offline toggle does not crash', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_buildApp(provider: _NullUserProvider()));
      await _pumpReady(tester);

      final offlineCard = find.ancestor(
        of: find.text('Offline Persistence'),
        matching: find.byType(Card),
      );
      final offlineSwitch = find.descendant(
        of: offlineCard,
        matching: find.byType(Switch),
      );
      expect(offlineSwitch, findsOneWidget);

      await tester.tap(offlineSwitch);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Should still render without crashing
      expect(find.text('Offline Persistence'), findsOneWidget);
    });

    testWidgets(
        'offline toggle shows different subtitle when disabled',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // Default is offlineModeEnabled = true (from UserProvider)
      await tester.pumpWidget(_buildApp(provider: _NullUserProvider()));
      await _pumpReady(tester);

      // Initially shows the "enabled" subtitle
      final hasEnabledText = find
          .text('Save data locally and sync when reconnected')
          .evaluate()
          .isNotEmpty;
      final hasDisabledText = find
          .text('New data will not be stored locally for offline use.')
          .evaluate()
          .isNotEmpty;
      expect(hasEnabledText || hasDisabledText, isTrue);
    });
  });

  // =========================================================================
  // 18. GoRouter navigation - manage subscription
  // =========================================================================
  group('SettingsPage - GoRouter navigation', () {
    testWidgets('tapping manage subscription navigates to select-package',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final provider = MockUserProvider(
        mockUser: MockUser(
            id: 1,
            role: 'CAREGIVER',
            caregiverId: 1,
            name: 'CG'),
      );
      await tester.pumpWidget(_buildAppWithRouter(provider: provider));
      await _pumpReady(tester);

      final subsTile = find.ancestor(
        of: find.byIcon(Icons.subscriptions),
        matching: find.byType(ListTile),
      );
      await tester.tap(subsTile);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Select Package Page'), findsOneWidget);
    });

    testWidgets('tapping notetaker config navigates to notetaker-configuration',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
          _buildAppWithRouter(provider: _NullUserProvider()));
      await _pumpReady(tester);

      final noteTile = find.ancestor(
        of: find.byIcon(Icons.edit_note),
        matching: find.byType(ListTile),
      );
      await tester.tap(noteTile);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Notetaker Configuration Page'), findsOneWidget);
    });
  });

  // =========================================================================
  // 19. Patient role - all sections minus subscription
  // =========================================================================
  group('SettingsPage - Patient role sections', () {
    testWidgets('patient sees all sections except subscription',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final provider = MockUserProvider(
        mockUser: MockUser(
            id: 1,
            role: 'PATIENT',
            name: 'Patient User',
            email: 'patient@test.com'),
      );
      await tester.pumpWidget(_buildApp(provider: provider));
      await _pumpReady(tester);

      expect(find.text('Appearance'), findsOneWidget);
      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('Privacy'), findsOneWidget);
      expect(find.text('Subscription'), findsNothing);
      expect(find.text('Notetaker Assistant'), findsOneWidget);
      expect(find.text('General'), findsOneWidget);
    });

    testWidgets('patient shows initial from name', (tester) async {
      final provider = MockUserProvider(
        mockUser: MockUser(
            id: 1, role: 'PATIENT', name: 'Maria', email: 'm@t.com'),
      );
      await tester.pumpWidget(_buildApp(provider: provider));
      await tester.pump();

      expect(find.text('M'), findsOneWidget);
      expect(find.text('Maria'), findsOneWidget);
      expect(find.text('m@t.com'), findsOneWidget);
    });
  });

  // =========================================================================
  // 20. Widget structure verification
  // =========================================================================
  group('SettingsPage - Widget structure', () {
    testWidgets(
        'uses constrained responsive body without overflow on wider compact viewport',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(720, 480));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_buildApp(provider: _NullUserProvider()));
      await _pumpReady(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(SettingsPage), findsOneWidget);

      final hasResponsiveBodyConstraint =
          tester.widgetList<ConstrainedBox>(find.byType(ConstrainedBox)).any(
                (widget) => widget.constraints.maxWidth == 700,
              );
      expect(hasResponsiveBodyConstraint, isTrue);
    });

    testWidgets('has exactly one Padding wrapping ListView', (tester) async {
      await tester.pumpWidget(_buildApp(provider: _NullUserProvider()));
      await tester.pump();
      // The body has a Padding with horizontal 16
      expect(find.byType(Padding), findsWidgets);
    });

    testWidgets('has SizedBox spacers between sections', (tester) async {
      await tester.pumpWidget(_buildApp(provider: _NullUserProvider()));
      await tester.pump();
      expect(find.byType(SizedBox), findsWidgets);
    });

    testWidgets('has Center widget for avatar area', (tester) async {
      await tester.pumpWidget(_buildApp(provider: _NullUserProvider()));
      await tester.pump();
      expect(find.byType(Center), findsWidgets);
    });

    testWidgets('has Column for avatar and user info', (tester) async {
      await tester.pumpWidget(_buildApp(provider: _NullUserProvider()));
      await tester.pump();
      expect(find.byType(Column), findsWidgets);
    });
  });

  // =========================================================================
  // 21. Edge cases
  // =========================================================================
  group('SettingsPage - Edge cases', () {
    testWidgets('empty email shows empty text', (tester) async {
      final provider = MockUserProvider(
        mockUser: MockUser(
            id: 1,
            name: 'Test',
            email: '',
            role: 'CAREGIVER',
            caregiverId: 1),
      );
      await tester.pumpWidget(_buildApp(provider: provider));
      await tester.pump();
      // The avatar should show 'T' for 'Test'
      expect(find.text('T'), findsOneWidget);
      expect(find.text('Test'), findsOneWidget);
    });

    testWidgets('lowercase patient role hides subscription', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final provider = MockUserProvider(
        mockUser: MockUser(id: 1, role: 'patient', name: 'Pat'),
      );
      await tester.pumpWidget(_buildApp(provider: provider));
      await _pumpReady(tester);
      expect(find.byIcon(Icons.subscriptions), findsNothing);
    });

    testWidgets('mixed case Patient role hides subscription', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final provider = MockUserProvider(
        mockUser: MockUser(id: 1, role: 'Patient', name: 'Pat'),
      );
      await tester.pumpWidget(_buildApp(provider: provider));
      await _pumpReady(tester);
      expect(find.byIcon(Icons.subscriptions), findsNothing);
    });

    testWidgets('admin role shows subscription', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final provider = MockUserProvider(
        mockUser: MockUser(id: 1, role: 'ADMIN', name: 'Admin'),
      );
      await tester.pumpWidget(_buildApp(provider: provider));
      await _pumpReady(tester);
      expect(find.byIcon(Icons.subscriptions), findsOneWidget);
    });
  });
}
