// The PR's three routes on the production route table:
// /medicare-connect, /health-data and /dob-confirm.

import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/config/router/app_router.dart';
import 'package:care_connect_app/features/health/health_data/pages/medicare_connect_page.dart';
import 'package:care_connect_app/features/health/health_data/services/medicare_connect_service.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_client.dart';
import 'package:care_connect_app/services/user_role_storage_service.dart';

import 'health_data_test_support.dart';

class _NotConnected extends MedicareConnectService {
  @override
  Future<MedicareStatus?> status() async =>
      const MedicareStatus(connected: false);
}

const _secure = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
const _connectivity = MethodChannel('dev.fluttercommunity.plus/connectivity');
const _connectivityStatus =
    EventChannel('dev.fluttercommunity.plus/connectivity_status');

Future<GoRouter> _open(WidgetTester t, String location,
    {required bool signedIn}) async {
  if (signedIn) {
    await UserRoleStorageService.instance
        .setUserData(role: 'PATIENT', userId: 1, patientId: 1);
  } else {
    await UserRoleStorageService.instance.clearUserData();
  }
  final router = GoRouter(
    initialLocation: location,
    routes: appRouter.configuration.routes,
  );
  await t.pumpWidget(ChangeNotifierProvider<UserProvider>.value(
    value: UserProvider(),
    child: MaterialApp.router(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  ));
  for (var i = 0; i < 20; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pump(const Duration(milliseconds: 50));
  }
  return router;
}

String _path(GoRouter r) => r.routerDelegate.currentConfiguration.uri.path;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late HttpClientAdapter original;
  late MedicareConnectService originalConnect;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secure, (call) async {
      if (call.method == 'readAll') return <String, String>{};
      if (call.method == 'containsKey') return false;
      return null;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_connectivity,
            (call) async => call.method == 'check' ? ['wifi'] : null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(_connectivityStatus,
            MockStreamHandler.inline(onListen: (_, __) {}));
    original = ApiClient.instance.debugHttpClientAdapter;
    // Health Data reads fail fast; nothing reaches the network.
    ApiClient.instance.debugSetHttpClientAdapter(RouteAdapter(const {}));
    originalConnect = MedicareConnectService.instance;
    MedicareConnectService.instance = _NotConnected();
    MedicareConnectPage.returnHandled = false;
    MedicareConnectPage.pendingResult = null;
  });

  tearDown(() {
    ApiClient.instance.debugSetHttpClientAdapter(original);
    MedicareConnectService.instance = originalConnect;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secure, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_connectivity, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(_connectivityStatus, null);
  });

  testWidgets('TC-MCR-CONN-024: /medicare-connect?medicare=cancelled opens '
      'the Connect Medicare page with the cancelled message', (t) async {
    await t.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final r = await _open(t, '/medicare-connect?medicare=cancelled',
        signedIn: true);
    expect(_path(r), '/medicare-connect');
    expect(find.text('Connect Medicare'), findsOneWidget);
    expect(find.textContaining('didn\'t finish connecting'), findsOneWidget);
    expect(find.text('Not connected'), findsOneWidget);
  });

  testWidgets('TC-MCR-CONN-025: Back on a page reached by redirect, with '
      'nothing to go back to, opens Health Data', (t) async {
    await t.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final r = await _open(t, '/medicare-connect?medicare=connected',
        signedIn: true);
    await t.tap(find.byTooltip('Back to Health Data'));
    for (var i = 0; i < 40; i++) {
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await t.pump(const Duration(milliseconds: 50));
    }
    expect(_path(r), '/health-data');
    expect(find.text('Health Data'), findsOneWidget);
  });

  for (final c in const [
    ('TC-MCR-CONN-026', '/medicare-connect'),
    ('TC-HDATA-016', '/health-data'),
    ('TC-EHR-REC-041', '/dob-confirm'),
  ]) {
    testWidgets('${c.$1}: ${c.$2} without signing in goes to the login page',
        (t) async {
      // Only where the router lands is under test. The inherited login page
      // overflows its Rows with the test font; that layout error is ignored.
      final previous = FlutterError.onError;
      FlutterError.onError = (d) {
        final overflow = d.exceptionAsString().contains('RenderFlex overflowed');
        if (!overflow) previous?.call(d);
      };
      addTearDown(() => FlutterError.onError = previous);
      final r = await _open(t, c.$2, signedIn: false);
      FlutterError.onError = previous;
      expect(_path(r), '/login');
    });
  }

  testWidgets('TC-EHR-REC-040: the /dob-confirm route does not show the '
      'built-in sample conflict to a signed-in patient', (t) async {
    final r = await _open(t, '/dob-confirm', signedIn: true);
    expect(_path(r), '/dob-confirm');
    expect(find.text('Which date of birth is correct?'), findsNothing);
    expect(find.text('05/14/1985'), findsNothing);
  });

  testWidgets('a ?medicare= result is kept through the sign-in guard and shown '
      'after signing in (#263 review)', (t) async {
    await t.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final previous = FlutterError.onError;
    FlutterError.onError = (d) {
      final overflow = d.exceptionAsString().contains('RenderFlex overflowed');
      if (!overflow) previous?.call(d);
    };
    addTearDown(() => FlutterError.onError = previous);

    final r = await _open(t, '/medicare-connect?medicare=cancelled',
        signedIn: false);
    expect(_path(r), '/login');
    expect(MedicareConnectPage.pendingResult, MedicareConnectResult.cancelled);

    await UserRoleStorageService.instance
        .setUserData(role: 'PATIENT', userId: 1, patientId: 1);
    r.go('/medicare-connect');
    for (var i = 0; i < 20; i++) {
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await t.pump(const Duration(milliseconds: 50));
    }
    FlutterError.onError = previous;
    expect(_path(r), '/medicare-connect');
    expect(find.textContaining('didn\'t finish connecting'), findsOneWidget);
    expect(MedicareConnectPage.pendingResult, isNull);
  });
}
