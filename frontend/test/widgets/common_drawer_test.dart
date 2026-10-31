// Tests for CommonDrawer
// (lib/widgets/common_drawer.dart).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:care_connect_app/widgets/common_drawer.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/providers/theme_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../mock_user_provider.dart';

class _NullUserProvider extends MockUserProvider {
  _NullUserProvider() : super(mockUser: null);

  @override
  UserSession? get user => null;
}

/// Mock that returns offline so _loadProfilePicture() skips HTTP.
class _OfflineMockUserProvider extends MockUserProvider {
  _OfflineMockUserProvider({required UserSession mockUser})
      : super(mockUser: mockUser);

  @override
  bool get isDeviceOnline => false;
}

Widget _wrapNull() {
  final provider = _NullUserProvider();
  return MaterialApp(
    home: ChangeNotifierProvider<UserProvider>.value(
      value: provider,
      child: Scaffold(
        drawer: const CommonDrawer(currentRoute: '/dashboard'),
        body: const SizedBox(),
      ),
    ),
  );
}

Widget _wrapWithUser({
  String role = 'PATIENT',
  String currentRoute = '/dashboard',
}) {
  final user = MockUser(
    id: 1,
    name: 'Jane',
    email: 'j@e.com',
    role: role,
    patientId: 1,
    caregiverId: role == 'CAREGIVER' ? 10 : null,
  );
  final provider = _OfflineMockUserProvider(mockUser: user);
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<UserProvider>.value(value: provider),
      ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
    ],
    child: MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(size: Size(800, 1200)),
        child: Scaffold(
          drawer: CommonDrawer(currentRoute: currentRoute),
          body: const SizedBox(),
        ),
      ),
    ),
  );
}

/// The app is a MaterialApp.router: a drawer item that navigates with
/// context.go needs a GoRouter above it (PR #428 review).
Widget _wrapRouter({String role = 'PATIENT'}) {
  final user = MockUser(
    id: 1,
    name: 'Jane',
    email: 'j@e.com',
    role: role,
    patientId: 1,
  );
  final router = GoRouter(routes: [
    GoRoute(
      path: '/',
      builder: (_, __) => const Scaffold(
        drawer: CommonDrawer(currentRoute: '/dashboard'),
        body: SizedBox(),
      ),
    ),
    GoRoute(
      path: '/health-data',
      builder: (_, __) => const Scaffold(body: Text('Health Data Page')),
    ),
  ]);
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<UserProvider>.value(
          value: _OfflineMockUserProvider(mockUser: user)),
      ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('CommonDrawer – null user', () {
    testWidgets('TC-DRW-001: renders without crashing', (tester) async {
      await tester.pumpWidget(_wrapNull());
      await tester.pump();
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('TC-DRW-002: opens drawer and shows "Please log in"', (tester) async {
      await tester.pumpWidget(_wrapNull());
      await tester.pump();
      final ScaffoldState scaffold = tester.state(find.byType(Scaffold));
      scaffold.openDrawer();
      await tester.pump();
      expect(find.text('Please log in'), findsOneWidget);
    });
  });

  group('CommonDrawer – logged-in PATIENT', () {
    Future<void> openDrawer(WidgetTester tester, {String role = 'PATIENT', String currentRoute = '/dashboard'}) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      final origOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.toString().contains('overflowed')) return;
        origOnError?.call(details);
      };
      addTearDown(() {
        FlutterError.onError = origOnError;
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(_wrapWithUser(role: role, currentRoute: currentRoute));
      await tester.pump();
      final ScaffoldState scaffold = tester.state(find.byType(Scaffold));
      scaffold.openDrawer();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('TC-DRW-003: shows user name in drawer header', (tester) async {
      await openDrawer(tester);
      expect(find.text('Jane'), findsOneWidget);
    });

    testWidgets('TC-DRW-004: shows Dashboard item', (tester) async {
      await openDrawer(tester);
      expect(find.text('Dashboard'), findsAtLeastNWidgets(1));
    });

    testWidgets('TC-DRW-005: shows Calendar Assistant', (tester) async {
      await openDrawer(tester);
      expect(find.text('Calendar Assistant'), findsOneWidget);
    });

    testWidgets('TC-HDATA-049: a patient sees Health Data in the menu',
        (tester) async {
      await openDrawer(tester);
      expect(find.text('Health Data'), findsOneWidget);
      expect(find.byIcon(Icons.health_and_safety), findsOneWidget);
    });

    for (final role in ['CAREGIVER', 'FAMILY_MEMBER', 'ADMIN']) {
      testWidgets('TC-HDATA-050: a $role does not see Health Data in the menu',
          (tester) async {
        await openDrawer(tester, role: role);
        expect(find.text('Health Data'), findsNothing);
      });
    }

    testWidgets('TC-DRW-006: shows Medication Management', (tester) async {
      await openDrawer(tester);
      expect(find.text('Medication Management'), findsOneWidget);
    });

    testWidgets('TC-DRW-007: shows Gamification', (tester) async {
      await openDrawer(tester);
      expect(find.text('Gamification'), findsOneWidget);
    });

    testWidgets('TC-DRW-008: shows Wearables', (tester) async {
      await openDrawer(tester);
      expect(find.text('Wearables'), findsOneWidget);
    });

    testWidgets('TC-DRW-009: shows Logout', (tester) async {
      await openDrawer(tester);
      expect(find.text('Logout'), findsOneWidget);
    });

    testWidgets('TC-DRW-010: does NOT show Add Patient for PATIENT role', (tester) async {
      await openDrawer(tester, role: 'PATIENT');
      expect(find.text('Add Patient'), findsNothing);
    });

    testWidgets('TC-DRW-011: shows role text', (tester) async {
      await openDrawer(tester);
      expect(find.text('PATIENT'), findsOneWidget);
    });

    testWidgets('TC-DRW-012: shows View Profile text', (tester) async {
      await openDrawer(tester);
      expect(find.text(' View Profile'), findsOneWidget);
    });

    // ---- PR #428 review (2026-10-25), Testing Lead ----

    testWidgets(
        'TC-DRW-015: tapping Health Data closes the menu and opens '
        '/health-data', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      final origOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.toString().contains('overflowed')) return;
        origOnError?.call(details);
      };
      addTearDown(() {
        FlutterError.onError = origOnError;
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(_wrapRouter());
      await tester.pump();
      final ScaffoldState scaffold = tester.state(find.byType(Scaffold));
      scaffold.openDrawer();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.text('Health Data'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Health Data Page'), findsOneWidget);
      expect(find.byType(Drawer), findsNothing);
    });

    for (final route in ['/health-data', '/health-data/event']) {
      testWidgets(
          'TC-DRW-016: on $route the Health Data item is marked as the '
          'current page, and on /dashboard it is not', (tester) async {
        TextStyle? styleOf() =>
            tester.widget<Text>(find.text('Health Data')).style;
        await openDrawer(tester, currentRoute: route);
        expect(styleOf()?.fontWeight, FontWeight.bold);
        final active = styleOf()?.color;
        await openDrawer(tester);
        expect(styleOf()?.fontWeight, FontWeight.normal);
        expect(styleOf()?.color, isNot(active));
      });
    }

    testWidgets(
        'TC-DRW-017: Health Data comes right after Medication Management',
        (tester) async {
      await openDrawer(tester);
      double top(String text) => tester.getTopLeft(find.text(text)).dy;
      final tiles = tester
          .widgetList<ListTile>(find.byType(ListTile))
          .map((t) => t.title)
          .whereType<Text>()
          .map((t) => t.data)
          .toList();
      final i = tiles.indexOf('Medication Management');
      expect(i, isNonNegative);
      expect(tiles[i + 1], 'Health Data');
      expect(top('Health Data'), greaterThan(top('Medication Management')));
    });

    testWidgets(
        'TC-DRW-018: a lower-case "patient" role still sees Health Data',
        (tester) async {
      await openDrawer(tester, role: 'patient');
      expect(find.text('Health Data'), findsOneWidget);
    });
  });

  group('CommonDrawer – logged-in CAREGIVER', () {
    Future<void> openDrawer(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      final origOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.toString().contains('overflowed')) return;
        origOnError?.call(details);
      };
      addTearDown(() {
        FlutterError.onError = origOnError;
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(_wrapWithUser(role: 'CAREGIVER'));
      await tester.pump();
      final ScaffoldState scaffold = tester.state(find.byType(Scaffold));
      scaffold.openDrawer();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('TC-DRW-013: shows Add Patient for CAREGIVER role', (tester) async {
      await openDrawer(tester);
      expect(find.text('Add Patient'), findsOneWidget);
    });

    testWidgets('TC-DRW-014: shows Invoice Assistant expansion tile', (tester) async {
      await openDrawer(tester);
      expect(find.text('Invoice Assistant'), findsOneWidget);
    });
  });
}
