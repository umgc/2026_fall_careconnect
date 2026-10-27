// Guards that the Epic SMART-on-FHIR connect tile is wired into the real
// Settings screen (SettingsPage) under a "Connected Services" section.
//
// Regression context: the tile originally lived in an orphan `SettingsScreen`
// that nothing navigated to, so it was invisible. It now belongs in
// `lib/pages/settings_page.dart` (the screen reached from the app header/menu).
//
// Harness mirrors the project pattern (see caregiver_dashboard_test.dart):
// mock the secure-storage + connectivity method channels, provide UserProvider
// and LocaleProvider, and pump (not pumpAndSettle) to avoid infinite timers.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/pages/settings_page.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/providers/locale_provider.dart';
import 'package:care_connect_app/providers/theme_provider.dart';
import 'package:care_connect_app/widgets/epic_connect_tile.dart';
import 'package:care_connect_app/features/health/health_data/services/athena_connect_service.dart';
import 'package:care_connect_app/features/health/health_data/widgets/athena_connect_tile.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Opt out of telemetry so no dialog is shown and no events are sent.
    SharedPreferences.setMockInitialValues(<String, Object>{
      'telemetry_opted_out': true,
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

  // Tall surface so the whole ListView (Epic tile included) is laid out
  // without needing to scroll.
  Widget wrap({String? role}) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>(create: (_) {
          final users = UserProvider();
          if (role != null) {
            users.setUser(UserSession(
                id: 1, email: 'user@example.com', role: role, token: 't'));
          }
          return users;
        }),
        ChangeNotifierProvider<LocaleProvider>(create: (_) => LocaleProvider()),
        ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const SettingsPage(),
      ),
    );
  }

  testWidgets('SettingsPage shows the Epic connect tile under Connected Services',
      (tester) async {
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(wrap());
    await tester.pump(); // let localizations + initState async begin
    await tester.pump(const Duration(seconds: 1)); // let status()/loads resolve

    expect(find.byType(EpicConnectTile), findsOneWidget);
    expect(find.text('Connected Services'), findsOneWidget);
    // Tile title is constant regardless of connected/loading state.
    expect(find.text('Epic (MyChart)'), findsOneWidget);
  });

  group('athenahealth row', () {
    late AthenaConnectService original;
    setUp(() {
      original = AthenaConnectService.instance;
      AthenaConnectService.instance = _NotConnectedAthena();
    });
    tearDown(() => AthenaConnectService.instance = original);

    Future<void> pumpAs(WidgetTester tester, String? role) async {
      tester.view.physicalSize = const Size(800, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(wrap(role: role));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('a patient sees it under Connected Services, styled like '
        'the Epic row', (tester) async {
      await pumpAs(tester, 'PATIENT');
      final athena = find.byType(AthenaConnectTile);
      expect(athena, findsOneWidget);
      expect(tester.widget<AthenaConnectTile>(athena).compact, isTrue);
      final row = find.descendant(of: athena, matching: find.byType(ListTile));
      expect(row, findsOneWidget);
      expect(find.descendant(of: row, matching: find.text('athenahealth')),
          findsOneWidget);
      expect(find.descendant(of: athena, matching: find.byType(Card)),
          findsOneWidget);
      // Same building blocks as EpicConnectTile.
      expect(
          find.descendant(
              of: find.byType(EpicConnectTile), matching: find.byType(ListTile)),
          findsOneWidget);
    });

    testWidgets('other roles don\'t see it (the API accepts patients only)',
        (tester) async {
      await pumpAs(tester, 'CAREGIVER');
      expect(find.byType(AthenaConnectTile), findsNothing);
      expect(find.byType(EpicConnectTile), findsOneWidget);
    });
  });
}

class _NotConnectedAthena extends AthenaConnectService {
  @override
  Future<AthenaStatus?> status() async => const AthenaStatus(
      connected: false, reason: AthenaNotConnectedReason.notConsented);
}
