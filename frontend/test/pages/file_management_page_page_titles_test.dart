// Page-title tests for FileManagementPage (lib/pages/file_management_page.dart).
// Setup copied from file_management_page_test.dart; adds the page-title
// checks (WCAG 2.4.2) for this PR's TitledMaterialPageRoute changes.

import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:care_connect_app/pages/file_management_page.dart';
import 'package:care_connect_app/providers/user_provider.dart';

import '../mock_user_provider.dart';
import '../helpers/titled_route_probe.dart';

// FileManagementPage.didChangeDependencies reads GoRouterState.of(context), so
// the page must be hosted under a GoRouter (MaterialApp.router), not a plain
// MaterialApp with named routes.
Widget _hostRouter(UserProvider provider) {
  final router = GoRouter(
    observers: [probe],
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => ChangeNotifierProvider<UserProvider>.value(
          value: provider,
          child: const FileManagementPage(),
        ),
      ),
      GoRoute(
        path: '/login',
        builder: (_, __) => const Scaffold(body: Text('Login Page')),
      ),
      GoRoute(
        path: '/care-circle/invite',
        builder: (_, __) => const Scaffold(body: Text('Invite Page')),
      ),
    ],
  );
  return MaterialApp.router(
    routerConfig: router,
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
  );
}

/// Wraps FileManagementPage with a MockUserProvider that has a valid user.
Widget _wrap({String role = 'PATIENT', int id = 1}) {
  return _hostRouter(MockUserProvider(mockUser: MockUser(id: id, role: role)));
}

void _setupChannelMocks() {
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
}

/// Helper to pump and wait until loading completes.
Future<void> _pumpUntilLoaded(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pump();
}

TitledRouteProbe probe = TitledRouteProbe();

void main() {
  setUp(() {
    _setupChannelMocks();
    probe = TitledRouteProbe();
  });

  testWidgets(
      'a caregiver\'s compliance button opens a page titled '
      '"Compliance Dashboard"', (tester) async {
    await tester.pumpWidget(_wrap(role: 'CAREGIVER'));
    await _pumpUntilLoaded(tester);
    expect(await probe.tapAndReadTitle(tester, find.byIcon(Icons.fact_check)),
        'Compliance Dashboard');
  });
}
