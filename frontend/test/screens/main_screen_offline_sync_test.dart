// Offline-queue banner and sync-cycle tests for MainScreen
// (lib/screens/main_screen.dart). The queue lives in the real local DB
// (LocalDbTestBindings); replays go through a FakeHttpOverrides HttpClient
// installed before the OfflineSyncService singleton is created.

import 'dart:io';

import 'package:care_connect_app/config/navigation/bottom_nav_config.dart';
import 'package:care_connect_app/config/navigation/main_screen_config.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/screens/main_screen.dart';
import 'package:care_connect_app/services/local_db/offline_sync_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_http_overrides.dart';
import '../mock_user_provider.dart';
import '../test_support/local_db_test_bindings.dart';

class _NetProvider extends MockUserProvider {
  _NetProvider() : super(mockUser: MockUser(role: 'ADMIN'));
  bool online = true;

  @override
  bool get isDeviceOnline => online;

  void setOnline(bool value) {
    online = value;
    notifyListeners();
  }
}

final _config = MainScreenConfig(
  userRole: 'ADMIN',
  userId: 1,
  enablePageAnimation: false,
  customNavItems: [
    BottomNavItem(
      label: 'Home',
      labelKey: 'nav_home',
      icon: Icons.home,
      routeName: 'home',
      screen: const Scaffold(body: Text('Home Shell')),
    ),
    BottomNavItem(
      label: 'Settings',
      icon: Icons.settings,
      routeName: 'settings',
      screen: const Scaffold(body: Text('Settings Shell')),
    ),
  ],
);

Widget _wrap(UserProvider provider) {
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, __) => MainScreen(config: _config)),
  ]);
  return ChangeNotifierProvider<UserProvider>.value(
    value: provider,
    child: MaterialApp.router(
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  );
}

late OfflineSyncService _service;
HttpOverrides? _previousOverrides;

Future<void> _clearQueue() async {
  for (final item in await _service.getPendingQueue(limit: 2000)) {
    await _service.deleteQueuedRequestById(item.id);
  }
}

Future<void> _enqueue(String path) => _service.enqueueRequest(
      method: 'POST',
      uri: Uri.parse('https://api.example.test$path'),
      headers: const {'Content-Type': 'application/json'},
      body: '{"title":"Synthetic $path"}',
    );

Future<void> _pumpFor(WidgetTester tester, Duration total) async {
  const step = Duration(seconds: 1);
  var elapsed = Duration.zero;
  while (elapsed < total) {
    await tester.pump(step);
    elapsed += step;
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    _previousOverrides = HttpOverrides.current;
    // Replays to a "/fail" path are rejected; everything else succeeds.
    HttpOverrides.global = FakeHttpOverrides((method, uri) =>
        uri.path.contains('/fail')
            ? FakeResponse(500, 'nope')
            : FakeResponse(200, '{}'));
    await LocalDbTestBindings.install();
    _service = OfflineSyncService.instance();
    await _service.initialize();
  });

  tearDownAll(() async {
    HttpOverrides.global = _previousOverrides;
    await LocalDbTestBindings.uninstall();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await _clearQueue();
  });

  testWidgets('queued items show a banner, a sheet, and sync after reconnect',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final t = lookupAppLocalizations(const Locale('en'));

    await tester.runAsync(() async {
      await _enqueue('/v1/api/tasks/a');
      await _enqueue('/v1/api/tasks/fail');
      await _enqueue('/v1/api/tasks/c');
    });

    final provider = _NetProvider();
    await tester.pumpWidget(_wrap(provider));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Blue queued-sync banner with a spinning icon.
    expect(find.byIcon(Icons.sync), findsOneWidget);
    await tester.tap(find.byIcon(Icons.sync));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text(t.mainscreen_queueSyncItem), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsNWidgets(3));

    // Delete the last queued item from the sheet.
    await tester.tap(find.byIcon(Icons.delete_outline).last);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byIcon(Icons.delete_outline), findsNWidgets(2));
    Navigator.of(tester.element(find.text(t.mainscreen_queueSyncItem))).pop();
    await tester.pump(const Duration(seconds: 1));

    // Going offline cancels the pending sync; coming back schedules it.
    provider.setOnline(false);
    await tester.pump();
    expect(find.byIcon(Icons.wifi_off), findsOneWidget);
    provider.setOnline(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // First run after 10s, then one item per 10s; the failing item retries
    // until it is marked dead and drops out of the queue.
    var sawComplete = false;
    for (var i = 0; i < 120 && !sawComplete; i++) {
      await tester.pump(const Duration(seconds: 1));
      sawComplete = find.text(t.mainscreen_syncComplete).evaluate().isNotEmpty;
    }
    expect(sawComplete, isTrue);
    await _pumpFor(tester, const Duration(seconds: 6));
    expect(find.text(t.mainscreen_syncComplete), findsNothing);
    expect(find.byIcon(Icons.sync), findsNothing);
  });

  testWidgets('an empty queue shows no banner and an empty sheet is never '
      'reachable', (tester) async {
    tester.view.physicalSize = const Size(1440, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final provider = _NetProvider();
    await tester.pumpWidget(_wrap(provider));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byIcon(Icons.sync), findsNothing);
    expect(find.text('Home Shell'), findsOneWidget);
  });
}
