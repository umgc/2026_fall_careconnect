import 'package:care_connect_app/config/router/app_router.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/pages/epic_linked_return_page.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/screens/main_screen.dart';
import 'package:care_connect_app/services/pending_oracle_health_launch.dart';
import 'package:care_connect_app/services/user_role_storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _secure = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
const _connectivity = MethodChannel('dev.fluttercommunity.plus/connectivity');

GoRoute? _findRoute(List<RouteBase> routes, String target,
    [String prefix = '']) {
  for (final route in routes) {
    if (route is GoRoute) {
      final full = route.path.startsWith('/')
          ? route.path
          : (prefix.isEmpty ? route.path : '$prefix/${route.path}');
      if (full == target) return route;
      final nested = _findRoute(route.routes, target, full);
      if (nested != null) return nested;
    }
  }
  return null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_secure, (call) async {
      if (call.method == 'readAll') return <String, String>{};
      if (call.method == 'containsKey') return false;
      return null;
    });
    messenger.setMockMethodCallHandler(_connectivity, (call) async {
      if (call.method == 'check') return ['wifi'];
      return null;
    });
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_secure, null);
    messenger.setMockMethodCallHandler(_connectivity, null);
    PendingOracleHealthLaunch.clear();
  });

  testWidgets('dashboard builder maps each stored role to a config',
      (tester) async {
    final dashboard = _findRoute(appRouter.configuration.routes, '/dashboard')!;
    final results = <Widget>[];
    const roles = [
      UserData(role: 'PATIENT', userId: 3, patientId: 3, isLoggedIn: true),
      UserData(role: 'FAMILY_LINK', userId: 4, patientId: 3, isLoggedIn: true),
      UserData(role: 'ADMIN', userId: 5, isLoggedIn: true),
      UserData(role: 'ROBOT', userId: 6, isLoggedIn: true),
    ];
    final router = GoRouter(initialLocation: '/dashboard', routes: [
      GoRoute(
        path: '/dashboard',
        builder: (context, state) {
          final page =
              dashboard.builder!(context, state) as FutureBuilder<UserData?>;
          for (final data in roles) {
            results.add(page.builder(
              context,
              AsyncSnapshot<UserData?>.withData(ConnectionState.done, data),
            ));
          }
          return const Text('stub dashboard');
        },
      ),
      GoRoute(
        path: '/login',
        builder: (_, __) => const Text('login stub'),
      ),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(results[0], isA<MainScreen>());
    expect((results[0] as MainScreen).config?.userRole, 'PATIENT');
    expect(results[1], isA<MainScreen>());
    expect((results[2] as MainScreen).config?.appBarTitle, 'Admin Dashboard');
    expect(results[3], isA<Scaffold>());
    expect(find.text('login stub'), findsOneWidget);
  });

  testWidgets('epic-linked route builds the return page', (tester) async {
    final router = GoRouter(
      initialLocation: '/epic-linked?status=ok',
      routes: appRouter.configuration.routes,
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<UserProvider>.value(
        value: UserProvider(),
        child: MaterialApp.router(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(EpicLinkedReturnPage), findsOneWidget);
    expect(find.text('Epic connected'), findsOneWidget);
    // Unmount before the auto-redirect fires; dispose cancels the timer.
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('navigateToDashboard resumes a pending Oracle Health launch',
      (tester) async {
    PendingOracleHealthLaunch.set(
      issuer: 'https://fhir-ehr-code.cerner.com/r4/test',
      launch: 'abc',
    );
    late BuildContext ctx;
    final router = GoRouter(initialLocation: '/', routes: [
      GoRoute(
        path: '/',
        builder: (context, _) {
          ctx = context;
          return const Text('home stub');
        },
      ),
      GoRoute(
        path: '/oracle-health-launch',
        builder: (_, __) => const Text('oracle stub'),
      ),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await navigateToDashboard(ctx);
    await tester.pumpAndSettle();
    expect(find.text('oracle stub'), findsOneWidget);
  });

  testWidgets('navigateToDashboard checks the daily brief gate for patients',
      (tester) async {
    final provider = UserProvider();
    provider.setUser(UserSession(
      id: 3,
      email: 'p@test.com',
      role: 'PATIENT',
      token: 't',
      name: 'Pat',
      patientId: 3,
    ));
    late BuildContext ctx;
    final router = GoRouter(initialLocation: '/', routes: [
      GoRoute(
        path: '/',
        builder: (context, _) {
          ctx = context;
          return const Text('home stub');
        },
      ),
      GoRoute(path: '/login', builder: (_, __) => const Text('login stub')),
      GoRoute(
          path: '/dashboard', builder: (_, __) => const Text('dash stub')),
      GoRoute(
          path: '/stml/brief', builder: (_, __) => const Text('brief stub')),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<UserProvider>.value(
        value: provider,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    await navigateToDashboard(ctx, routePatientToDailyBrief: true);
    await tester.pumpAndSettle();
    expect(find.text('home stub'), findsNothing);
  });
}
