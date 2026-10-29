// Page-title tests for MenuPage (lib/widgets/menu/menu_page.dart): the menu
// items that push a page open it in a titled page (WCAG 2.4.2).
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/providers/locale_provider.dart';
import 'package:care_connect_app/providers/theme_provider.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/widgets/menu/menu_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/titled_route_probe.dart';

void main() {
  late TitledRouteProbe probe;

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpMenu(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    probe = TitledRouteProbe();
    final userProvider = UserProvider()
      ..setUser(UserSession(
        id: 1,
        email: 'pt@example.com',
        role: 'PATIENT',
        token: 'test-token',
        name: 'Pat Patient',
      ));
    final router = GoRouter(observers: [probe], routes: [
      GoRoute(path: '/', builder: (_, __) => const MenuPage()),
    ]);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>.value(value: userProvider),
        ChangeNotifierProvider<LocaleProvider>(create: (_) => LocaleProvider()),
        ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
      ),
    ));
    await tester.pumpAndSettle();
  }

  const items = {
    'Invoice Assistant': 'Invoice Assistant',
    'Patient Report': 'Patient Reports',
    'Medication Tracker': 'Medication Tracker',
  };

  for (final entry in items.entries) {
    testWidgets(
        'TC-MENU-007: "${entry.key}" opens a page titled "${entry.value}"',
        (tester) async {
      await pumpMenu(tester);
      final item = find.text(entry.key, skipOffstage: false).first;
      await tester.ensureVisible(item);
      await tester.pump();
      expect(await probe.tapAndReadTitle(tester, item), entry.value);
    });
  }
}
