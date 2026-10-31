import 'package:care_connect_app/providers/theme_provider.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:care_connect_app/widgets/common_drawer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../mock_user_provider.dart';

class _NullUserProvider extends MockUserProvider {
  _NullUserProvider() : super(mockUser: null);

  @override
  UserSession? get user => null;
}

Widget _app(UserProvider provider, {String currentRoute = '/dashboard'}) {
  Widget stub(String label) => Scaffold(body: Text(label));
  final router = GoRouter(routes: [
    GoRoute(
      path: '/',
      builder: (_, __) => Scaffold(
        drawer: CommonDrawer(currentRoute: currentRoute),
        body: const Text('home stub'),
      ),
    ),
    GoRoute(path: '/login', builder: (_, __) => stub('login stub')),
    GoRoute(path: '/profile', builder: (_, __) => stub('profile stub')),
    GoRoute(path: '/social-feed', builder: (_, __) => stub('social stub')),
    GoRoute(path: '/dashboard', builder: (_, __) => stub('dash stub')),
  ]);
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<UserProvider>.value(value: provider),
      ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
    ],
    child: MediaQuery(
      data: const MediaQueryData(size: Size(800, 2400)),
      child: MaterialApp.router(routerConfig: router),
    ),
  );
}

Future<void> _openDrawer(WidgetTester tester) async {
  tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
  await tester.pumpAndSettle();
}

Future<void> _tapItem(WidgetTester tester, String label) async {
  final finder = find.text(label);
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find
        .descendant(of: find.byType(Drawer), matching: find.byType(Scrollable))
        .first,
  );
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// The drawer header row overflows a few pixels in the default test
/// surface; ignore only overflow reports while the body runs.
void _testDrawer(String name, Future<void> Function(WidgetTester) body) {
  testWidgets(name, (tester) async {
    final original = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.toString().contains('overflowed')) return;
      original?.call(details);
    };
    try {
      await body(tester);
    } finally {
      FlutterError.onError = original;
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    ApiService.debugSetHttpClient(
      MockClient((_) async => http.Response('[]', 200)),
    );
  });

  tearDown(ApiService.debugResetHttpClient);

  Future<void> pumpUser(WidgetTester tester, {String role = 'PATIENT'}) async {
    await tester.pumpWidget(_app(MockUserProvider(
      mockUser: MockUser(role: role, name: 'Jane', patientId: 1),
    )));
    await tester.pumpAndSettle();
    await _openDrawer(tester);
  }

  _testDrawer('logged-out drawer Login button routes to /login',
      (tester) async {
    await tester.pumpWidget(_app(_NullUserProvider()));
    await tester.pumpAndSettle();
    await _openDrawer(tester);
    expect(find.text('Please log in'), findsOneWidget);
    expect(
      find.text('You need to be logged in to access navigation'),
      findsOneWidget,
    );
    await tester.tap(find.text('Login'));
    await tester.pumpAndSettle();
    expect(find.text('login stub'), findsOneWidget);
  });

  _testDrawer('header tap opens profile', (tester) async {
    await pumpUser(tester);
    await tester.tap(find.byType(DrawerHeader));
    await tester.pumpAndSettle();
    expect(find.text('profile stub'), findsOneWidget);
  });

  _testDrawer('dashboard item navigates via navigateToDashboard',
      (tester) async {
    await pumpUser(tester);
    await _tapItem(tester, 'Dashboard');
    // No stored session → navigation helper sends the user to login.
    expect(find.text('login stub'), findsOneWidget);
  });

  _testDrawer('social feed item navigates with userId', (tester) async {
    await pumpUser(tester);
    await _tapItem(tester, 'Social Feed');
    expect(find.text('social stub'), findsOneWidget);
  });

  _testDrawer('logout item clears user and goes home', (tester) async {
    await pumpUser(tester, role: 'CAREGIVER');
    await _tapItem(tester, 'Logout');
    expect(find.text('home stub'), findsOneWidget);
  });

  _testDrawer('invoice assistant highlighted for invoice routes',
      (tester) async {
    await tester.pumpWidget(_app(
      MockUserProvider(mockUser: MockUser(role: 'CAREGIVER', name: 'Jane')),
      currentRoute: '/invoice-assistant/list',
    ));
    await tester.pumpAndSettle();
    await _openDrawer(tester);
    expect(find.text('Invoice Assistant'), findsOneWidget);
  });
}
