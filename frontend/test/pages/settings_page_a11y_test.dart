// Accessibility test for SettingsPage: each switch has a name (WCAG 4.1.2).
// Setup copied from settings_page_test.dart.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
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
      (call) async => call.method == 'check' ? ['wifi'] : null,
    );
  });

  testWidgets('every Settings switch reads the title of its card',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_buildApp(provider: _NullUserProvider()));
    await _pumpReady(tester);

    final switches = find.byType(Switch, skipOffstage: false);
    expect(switches, findsWidgets);
    for (final element in switches.evaluate()) {
      final data = tester
          .getSemantics(find.byWidget(element.widget))
          .getSemanticsData();
      expect(data.label, isNotEmpty,
          reason: 'WCAG 4.1.2: a switch read as just "switch, off" has no name');
    }
    handle.dispose();
  });

  testWidgets('a signed-in user\'s notification switches read their titles',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final handle = tester.ensureSemantics();
    // Notification settings come from the backend for a signed-in user.
    await http.runWithClient(() async {
      await tester.pumpWidget(_buildApp(
          provider: MockUserProvider(mockUser: MockUser(id: 1, role: 'PATIENT'))));
      await _pumpReady(tester);
    },
        () => MockClient((_) async => http.Response(
            '{"id": 1, "userId": 1, "gamification": true, "emergency": true}',
            200)));

    final emergency = find.ancestor(
        of: find.text('Emergency Alerts'), matching: find.byType(ListTile));
    expect(emergency, findsOneWidget);
    final data = tester
        .getSemantics(find.descendant(of: emergency, matching: find.byType(Switch)))
        .getSemanticsData();
    expect(data.label, contains('Emergency Alerts'));
    handle.dispose();
  });
}

