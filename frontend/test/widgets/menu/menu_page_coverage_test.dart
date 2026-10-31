import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/providers/locale_provider.dart';
import 'package:care_connect_app/providers/theme_provider.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:care_connect_app/widgets/menu/menu_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _connectivity = MethodChannel('dev.fluttercommunity.plus/connectivity');

Widget _app({UserSession? session, LocaleProvider? localeProvider}) {
  final userProvider = UserProvider();
  if (session != null) userProvider.setUser(session);
  Widget stub(String label) => Scaffold(body: Text(label));
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, __) => const MenuPage()),
    GoRoute(path: '/login', builder: (_, __) => stub('login stub')),
    GoRoute(path: '/profile', builder: (_, __) => stub('profile stub')),
    GoRoute(path: '/social-feed', builder: (_, __) => stub('social stub')),
    GoRoute(
        path: '/admin/analytics', builder: (_, __) => stub('analytics stub')),
    GoRoute(path: '/admin/users', builder: (_, __) => stub('users stub')),
  ]);
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<UserProvider>.value(value: userProvider),
      ChangeNotifierProvider<LocaleProvider>.value(
          value: localeProvider ?? LocaleProvider()),
      ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
    ),
  );
}

UserSession _session(String role) => UserSession(
      id: 7,
      email: 'u@test.com',
      role: role,
      token: 't',
      name: 'Menu User',
      patientId: role == 'PATIENT' ? 7 : null,
      caregiverId: role == 'CAREGIVER' ? 7 : null,
    );

Future<void> _scrollTap(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final en = lookupAppLocalizations(const Locale('en'));

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    ApiService.debugSetHttpClient(
      MockClient((_) async => http.Response('[]', 200)),
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_connectivity, (call) async => ['wifi']);
  });

  tearDown(() {
    ApiService.debugResetHttpClient();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_connectivity, null);
  });

  testWidgets('logged-out prompt login button goes to /login',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    expect(find.text(en.pleaseLogIn), findsOneWidget);
    await tester.tap(find.widgetWithText(ElevatedButton, en.login));
    await tester.pumpAndSettle();
    expect(find.text('login stub'), findsOneWidget);
  });

  testWidgets('profile chevron and tile open profile', (tester) async {
    await tester.pumpWidget(_app(session: _session('PATIENT')));
    await tester.pumpAndSettle();
    expect(find.text('Menu User'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.chevron_right).first);
    await tester.pumpAndSettle();
    expect(find.text('profile stub'), findsOneWidget);
  });

  testWidgets('profile tile tap opens profile', (tester) async {
    await tester.pumpWidget(_app(session: _session('PATIENT')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Menu User'));
    await tester.pumpAndSettle();
    expect(find.text('profile stub'), findsOneWidget);
  });

  testWidgets('social feed tile pushes social route', (tester) async {
    await tester.pumpWidget(_app(session: _session('CAREGIVER')));
    await tester.pumpAndSettle();
    await _scrollTap(tester, find.text(en.socialFeed));
    expect(find.text('social stub'), findsOneWidget);
  });

  testWidgets('admin tools open analytics and user management',
      (tester) async {
    await tester.pumpWidget(_app(session: _session('ADMIN')));
    await tester.pumpAndSettle();
    await _scrollTap(tester, find.text('Product Analytics'));
    expect(find.text('analytics stub'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_app(session: _session('ADMIN')));
    await tester.pumpAndSettle();
    await _scrollTap(tester, find.text('User Management'));
    expect(find.text('users stub'), findsOneWidget);
  });

  testWidgets('narrow layout with a chosen locale, language picker, logout',
      (tester) async {
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final localeProvider = LocaleProvider();
    await localeProvider.setLocale(const Locale('es'));
    await tester.pumpWidget(
      _app(session: _session('PATIENT'), localeProvider: localeProvider),
    );
    await tester.pumpAndSettle();

    await _scrollTap(tester, find.text(en.language));
    // Dismiss the language picker sheet.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    await _scrollTap(tester, find.text(en.logout));
    expect(find.byType(MenuPage), findsOneWidget);
  });
}
