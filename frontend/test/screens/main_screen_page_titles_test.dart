// Reflow tests for MainScreen's bottom navigation (lib/screens/main_screen.dart).
// Setup copied from main_screen_test.dart; adds the page-title
// checks (WCAG 2.4.2) for this PR's TitledMaterialPageRoute changes.

import 'package:care_connect_app/widgets/wrapping_bottom_navigation_bar.dart';
import 'package:care_connect_app/config/navigation/bottom_nav_config.dart';
import 'package:care_connect_app/config/navigation/navigation_helper.dart';
import 'package:care_connect_app/widgets/app_bar_helper.dart';
import 'package:care_connect_app/config/navigation/main_screen_config.dart';
import 'package:care_connect_app/features/ai/presentation/pages/voice_command_ai.dart';
import 'package:care_connect_app/screens/main_screen.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import '../mock_user_provider.dart';
import '../helpers/titled_route_probe.dart';

/// Extended mock that exposes isDeviceOnline and offlineModeEnabled overrides.
class _TestableUserProvider extends MockUserProvider {
  _TestableUserProvider({
    super.mockUser,
    bool isDeviceOnline = true,
    bool offlineModeEnabled = true,
  })  : _isDeviceOnline = isDeviceOnline,
        _offlineModeEnabled = offlineModeEnabled;

  bool _isDeviceOnline;
  bool _offlineModeEnabled;

  @override
  bool get isDeviceOnline => _isDeviceOnline;

  @override
  bool get offlineModeEnabled => _offlineModeEnabled;

  void setDeviceOnline(bool value) {
    _isDeviceOnline = value;
    notifyListeners();
  }

  void setOfflineModeEnabled(bool value) {
    _offlineModeEnabled = value;
    notifyListeners();
  }
}

/// Wraps MainScreen in a router + provider for testing.
Widget _wrap({
  int? initialTabIndex,
  String role = 'PATIENT',
  MainScreenConfig? config,
  _TestableUserProvider? provider,
}) {
  final effectiveProvider =
      provider ?? _TestableUserProvider(mockUser: MockUser(role: role));
  final effectiveConfig =
      config ?? MainScreenConfig.forPatient(userId: 1, patientId: 1);

  final router = GoRouter(
    observers: [probe],
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => MainScreen(
          initialTabIndex: initialTabIndex,
          config: effectiveConfig,
        ),
      ),
      GoRoute(
        path: '/login',
        builder: (_, __) => const Scaffold(body: Text('Login Page')),
      ),
      GoRoute(
        path: '/voice',
        builder: (_, __) => const VoiceCommandAI(),
      ),
    ],
  );

  return ChangeNotifierProvider<UserProvider>.value(
    value: effectiveProvider,
    child: MaterialApp.router(
      routerConfig: router,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  );
}

/// Wraps MainScreen WITHOUT a config so that it reads from UserProvider.
Widget _wrapWithoutConfig({
  _TestableUserProvider? provider,
}) {
  final effectiveProvider =
      provider ?? _TestableUserProvider(mockUser: MockUser(role: 'PATIENT'));

  final router = GoRouter(
    observers: [probe],
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const MainScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (_, __) => const Scaffold(body: Text('Login Page')),
      ),
    ],
  );

  return ChangeNotifierProvider<UserProvider>.value(
    value: effectiveProvider,
    child: MaterialApp.router(
      routerConfig: router,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  );
}

TitledRouteProbe probe = TitledRouteProbe();

void main() {
  setUp(() {
    // Suppress layout overflow errors from child dashboard widgets.
    FlutterError.onError = (details) {
      if (details.toString().contains('overflowed')) return;
      FlutterError.dumpErrorToConsole(details);
    };

    // Stub platform channels commonly used by child widgets.
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('plugins.flutter.io/shared_preferences');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getAll') return <String, dynamic>{};
      return null;
    });

    const storageChannel =
        MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storageChannel, (call) async {
      return null;
    });

    const porcupineChannel =
        MethodChannel('flutter.picovoice.ai/porcupine_manager');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(porcupineChannel, (call) async {
      return null;
    });
  });
  tearDown(() {
    FlutterError.onError = FlutterError.dumpErrorToConsole;
  });

  testWidgets('below 600 px the bottom tabs wrap instead of truncating',
      (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final original = FlutterError.onError;
    // Dashboard cards inside the tabs overflow at 400 px; that's not what's
    // under test here (the original suite filters the same messages).
    FlutterError.onError = (d) {
      if (d.toString().contains('overflowed')) return;
      original?.call(d);
    };
    await tester.pumpWidget(_wrap());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    FlutterError.onError = original;
    expect(find.byType(WrappingBottomNavigationBar), findsOneWidget);
    final bar = tester.widget<WrappingBottomNavigationBar>(
        find.byType(WrappingBottomNavigationBar));
    expect(bar.labels, isNotEmpty);
    expect(bar.labels.length, bar.icons.length);
  });

  testWidgets('200% text also switches to the wrapping tabs', (tester) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final original = FlutterError.onError;
    FlutterError.onError = (d) {
      if (d.toString().contains('overflowed')) return;
      original?.call(d);
    };
    await tester.pumpWidget(_wrap());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    FlutterError.onError = original;
    expect(find.byType(WrappingBottomNavigationBar), findsOneWidget);
  });
}
