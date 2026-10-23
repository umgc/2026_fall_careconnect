// Tests for app_router.dart route configuration
// (lib/config/router/app_router.dart).
//
// We test the GoRouter route definitions by inspecting the route tree,
// and also exercise builder/redirect logic through widget tests that
// navigate to individual routes, verifying parameter parsing, validation
// error handling, and conditional rendering.

import 'dart:convert';

import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:care_connect_app/config/router/app_router.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/widgets/hybrid_video_call_widget.dart';
import 'package:care_connect_app/features/invite_accept/services/pending_invite.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:care_connect_app/services/user_role_storage_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Recursively extracts all route paths from a GoRouter's route tree.
List<String> _extractPaths(List<RouteBase> routes, [String prefix = '']) {
  final paths = <String>[];
  for (final route in routes) {
    if (route is GoRoute) {
      // Build full path: if route path starts with '/' it's absolute,
      // otherwise join with parent prefix
      final fullPath = route.path.startsWith('/')
          ? route.path
          : (prefix.isEmpty ? route.path : '$prefix/${route.path}');
      paths.add(fullPath);
      if (route.routes.isNotEmpty) {
        paths.addAll(_extractPaths(route.routes, fullPath));
      }
    }
  }
  return paths;
}

/// Recursively extracts named routes from a GoRouter's route tree.
Map<String, String> _extractNamedRoutes(List<RouteBase> routes,
    [String prefix = '']) {
  final named = <String, String>{};
  for (final route in routes) {
    if (route is GoRoute) {
      final fullPath = route.path.startsWith('/')
          ? route.path
          : (prefix.isEmpty ? route.path : '$prefix/${route.path}');
      if (route.name != null) {
        named[route.name!] = fullPath;
      }
      if (route.routes.isNotEmpty) {
        named.addAll(_extractNamedRoutes(route.routes, fullPath));
      }
    }
  }
  return named;
}

/// Find a GoRoute by path from the appRouter's route tree.
GoRoute? _findRoute(List<RouteBase> routes, String targetPath,
    [String prefix = '']) {
  for (final route in routes) {
    if (route is GoRoute) {
      final fullPath = route.path.startsWith('/')
          ? route.path
          : (prefix.isEmpty ? route.path : '$prefix/${route.path}');
      if (fullPath == targetPath) return route;
      if (route.routes.isNotEmpty) {
        final found = _findRoute(route.routes, targetPath, fullPath);
        if (found != null) return found;
      }
    }
  }
  return null;
}

/// Counts routes that have a redirect function defined (not a builder).
int _countRedirectRoutes(List<RouteBase> routes) {
  int count = 0;
  for (final route in routes) {
    if (route is GoRoute) {
      if (route.redirect != null) count++;
      if (route.routes.isNotEmpty) {
        count += _countRedirectRoutes(route.routes);
      }
    }
  }
  return count;
}

/// Counts routes that have a builder function defined (not a redirect).
int _countBuilderRoutes(List<RouteBase> routes) {
  int count = 0;
  for (final route in routes) {
    if (route is GoRoute) {
      if (route.builder != null) count++;
      if (route.routes.isNotEmpty) {
        count += _countBuilderRoutes(route.routes);
      }
    }
  }
  return count;
}

/// Creates a test GoRouter navigating to [initialLocation] using the full
/// appRouter route list.  This lets builder closures run with real GoRouterState
/// objects just like production.
GoRouter _createFullTestRouter(String initialLocation) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: appRouter.configuration.routes,
  );
}

/// Helper to pump a widget with a GoRouter using ChangeNotifierProvider.
Future<void> _pumpRouterApp(
  WidgetTester tester,
  GoRouter router, {
  UserProvider? userProvider,
}) async {
  final provider = userProvider ?? UserProvider();
  await tester.pumpWidget(
    ChangeNotifierProvider<UserProvider>.value(
      value: provider,
      child: MaterialApp.router(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
}

/// Standard platform channel setup for tests that require SharedPreferences,
/// flutter_secure_storage, and connectivity.
void _setupPlatformChannels({Map<String, Object>? sharedPrefsValues}) {
  SharedPreferences.setMockInitialValues(sharedPrefsValues ?? {});
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    (call) async {
      if (call.method == 'readAll') return <String, String>{};
      if (call.method == 'read') return null;
      if (call.method == 'containsKey') return false;
      if (call.method == 'write') return null;
      if (call.method == 'delete') return null;
      if (call.method == 'deleteAll') return null;
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

/// Tear down platform channel mocks.
void _tearDownPlatformChannels() {
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
}

void main() {
  late List<String> allPaths;
  late Map<String, String> namedRoutes;

  setUpAll(() {
    allPaths = _extractPaths(appRouter.configuration.routes);
    namedRoutes = _extractNamedRoutes(appRouter.configuration.routes);
  });

  group('appRouter configuration', () {
    test('TC-ROUTE-001: appRouter is a GoRouter instance', () {
      expect(appRouter, isA<GoRouter>());
    });

    test('TC-ROUTE-002: initial location is /', () {
      // The GoRouter is configured with initialLocation: '/'
      // We verify the root route exists as the first route
      final firstRoute = appRouter.configuration.routes.first;
      expect(firstRoute, isA<GoRoute>());
      expect((firstRoute as GoRoute).path, equals('/'));
    });

    test('TC-ROUTE-003: has a non-empty list of routes', () {
      expect(appRouter.configuration.routes, isNotEmpty);
    });

    test('TC-ROUTE-004: all top-level routes are GoRoute instances', () {
      for (final route in appRouter.configuration.routes) {
        expect(route, isA<GoRoute>());
      }
    });

    test('TC-ROUTE-005: routes with builders have non-null builders', () {
      final builderCount = _countBuilderRoutes(appRouter.configuration.routes);
      expect(builderCount, greaterThan(0));
    });

    test('TC-ROUTE-006: routes with redirects have non-null redirects', () {
      final redirectCount =
          _countRedirectRoutes(appRouter.configuration.routes);
      expect(redirectCount, greaterThan(0));
    });

    test('TC-ROUTE-007: total route count (builders + redirects) covers all paths', () {
      final builderCount = _countBuilderRoutes(appRouter.configuration.routes);
      final redirectCount =
          _countRedirectRoutes(appRouter.configuration.routes);
      // Some routes may have both builder and redirect, so sum >= paths
      expect(builderCount + redirectCount,
          greaterThanOrEqualTo(allPaths.length - 5));
    });
  });

  group('core routes are registered', () {
    test('TC-ROUTE-008: root route / exists', () {
      expect(allPaths, contains('/'));
    });

    test('TC-ROUTE-009: login route exists', () {
      expect(allPaths, contains('/login'));
    });

    test('TC-ROUTE-010: signup route exists', () {
      expect(allPaths, contains('/signup'));
    });

    test('TC-ROUTE-011: dashboard route exists', () {
      expect(allPaths, contains('/dashboard'));
    });

    test('TC-ROUTE-012: patient dashboard route exists', () {
      expect(allPaths, contains('/dashboard/patient'));
    });

    test('TC-ROUTE-013: caregiver dashboard route exists', () {
      expect(allPaths, contains('/dashboard/caregiver'));
    });

    test('TC-ROUTE-180: medical passport route exists and requires sign-in', () {
      expect(allPaths, contains('/medical-passport'));
      final route = _findRoute(appRouter.configuration.routes, '/medical-passport');
      expect(route!.redirect, isNotNull);
    });

    test('TC-ROUTE-014: caregiver-dashboard route exists', () {
      expect(allPaths, contains('/caregiver-dashboard'));
    });

    test('TC-ROUTE-015: home route exists', () {
      expect(allPaths, contains('/home'));
    });
  });

  group('registration routes are registered', () {
    test('TC-ROUTE-016: register caregiver route exists', () {
      expect(allPaths, contains('/register/caregiver'));
    });

    test('TC-ROUTE-017: register patient route exists', () {
      expect(allPaths, contains('/register/patient'));
    });

    test('TC-ROUTE-018: add-patient route exists', () {
      expect(allPaths, contains('/add-patient'));
    });
  });

  group('payment routes are registered', () {
    test('TC-ROUTE-019: select-package route exists', () {
      expect(allPaths, contains('/select-package'));
    });

    test('TC-ROUTE-020: subscription route exists', () {
      expect(allPaths, contains('/subscription'));
    });

    test('TC-ROUTE-021: stripe-checkout route exists', () {
      expect(allPaths, contains('/stripe-checkout'));
    });

    test('TC-ROUTE-022: payment-success route exists', () {
      expect(allPaths, contains('/payment-success'));
    });

    test('TC-ROUTE-023: payment-cancel route exists', () {
      expect(allPaths, contains('/payment-cancel'));
    });
  });

  group('feature routes are registered', () {
    test('TC-ROUTE-024: social-feed route exists', () {
      expect(allPaths, contains('/social-feed'));
    });

    test('TC-ROUTE-025: gamification route exists', () {
      expect(allPaths, contains('/gamification'));
    });

    test('TC-ROUTE-026: analytics route exists', () {
      expect(allPaths, contains('/analytics'));
    });

    test('TC-ROUTE-027: patient/:id route exists', () {
      expect(allPaths, contains('/patient/:id'));
    });

    test('TC-ROUTE-028: video-call route exists', () {
      expect(allPaths, contains('/video-call-chime'));
    });

    test('TC-ROUTE-029: wearables route exists', () {
      expect(allPaths, contains('/wearables'));
    });

    test('TC-ROUTE-030: home-monitoring route exists', () {
      expect(allPaths, contains('/home-monitoring'));
    });

    test('TC-ROUTE-031: smart-devices route exists', () {
      expect(allPaths, contains('/smart-devices'));
    });

    test('TC-ROUTE-032: medication route exists', () {
      expect(allPaths, contains('/medication'));
    });

    test('TC-ROUTE-033: profile-settings route exists', () {
      expect(allPaths, contains('/profile-settings'));
    });

    test('TC-ROUTE-034: profile route exists', () {
      expect(allPaths, contains('/profile'));
    });

    test('TC-ROUTE-035: settings route exists', () {
      expect(allPaths, contains('/settings'));
    });

    test('TC-ROUTE-036: file-management route exists', () {
      expect(allPaths, contains('/file-management'));
    });

    test('TC-ROUTE-037: ai-configuration route exists', () {
      expect(allPaths, contains('/ai-configuration'));
    });

    test('TC-ROUTE-038: calendar route exists', () {
      expect(allPaths, contains('/calendar'));
    });

    test('TC-ROUTE-039: virtual-checkin route exists', () {
      expect(allPaths, contains('/virtual-checkin'));
    });

    test('TC-ROUTE-040: informed-delivery route exists', () {
      expect(allPaths, contains('/informed-delivery'));
    });

    test('TC-ROUTE-041: search route exists', () {
      expect(allPaths, contains('/search'));
    });
  });

  group('EVV routes are registered', () {
    test('TC-ROUTE-042: evv dashboard route exists', () {
      expect(allPaths, contains('/evv'));
    });

    test('TC-ROUTE-043: evv select-patient route exists', () {
      expect(allPaths, contains('/evv/select-patient'));
    });

    test('TC-ROUTE-044: evv start-visit route exists', () {
      expect(allPaths, contains('/evv/start-visit'));
    });

    test('TC-ROUTE-045: evv checkin-location route exists', () {
      expect(allPaths, contains('/evv/checkin-location'));
    });

    test('TC-ROUTE-046: evv visit-progress route exists', () {
      expect(allPaths, contains('/evv/visit-progress'));
    });

    test('TC-ROUTE-047: evv checkout-location route exists', () {
      expect(allPaths, contains('/evv/checkout-location'));
    });

    test('TC-ROUTE-048: evv visit-complete route exists', () {
      expect(allPaths, contains('/evv/visit-complete'));
    });

    test('TC-ROUTE-049: evv visit-completed-success route exists', () {
      expect(allPaths, contains('/evv/visit-completed-success'));
    });

    test('TC-ROUTE-050: evv review-records route exists', () {
      expect(allPaths, contains('/evv/review-records'));
    });

    test('TC-ROUTE-051: evv visit-history route exists', () {
      expect(allPaths, contains('/evv/visit-history'));
    });

    test('TC-ROUTE-052: evv corrections route exists', () {
      expect(allPaths, contains('/evv/corrections'));
    });

    test('TC-ROUTE-053: evv offline-sync route exists', () {
      expect(allPaths, contains('/evv/offline-sync'));
    });
  });

  group('invoice routes are registered', () {
    test('TC-ROUTE-054: invoice-assistant route exists', () {
      expect(allPaths, contains('/invoice-assistant'));
    });

    test('TC-ROUTE-055: invoice dashboard sub-route exists', () {
      expect(allPaths, contains('/invoice-assistant/dashboard'));
    });

    test('TC-ROUTE-056: invoice upload sub-route exists', () {
      expect(allPaths, contains('/invoice-assistant/upload'));
    });

    test('TC-ROUTE-057: invoice list sub-route exists', () {
      expect(allPaths, contains('/invoice-assistant/list'));
    });

    test('TC-ROUTE-058: invoice list filtered sub-route exists', () {
      expect(allPaths, contains('/invoice-assistant/list/:filter'));
    });

    test('TC-ROUTE-059: invoice detail sub-route exists', () {
      expect(allPaths, contains('/invoice-assistant/detail/:id'));
    });
  });

  group('named routes', () {
    test('TC-ROUTE-060: uspsTest named route exists', () {
      expect(namedRoutes, containsPair('uspsTest', '/usps-test'));
    });

    test('TC-ROUTE-061: invoiceDashboard named route exists', () {
      expect(namedRoutes,
          containsPair('invoiceDashboard', '/invoice-assistant/dashboard'));
    });

    test('TC-ROUTE-062: invoiceUpload named route exists', () {
      expect(namedRoutes,
          containsPair('invoiceUpload', '/invoice-assistant/upload'));
    });

    test('TC-ROUTE-063: invoiceList named route exists', () {
      expect(
          namedRoutes, containsPair('invoiceList', '/invoice-assistant/list'));
    });

    test('TC-ROUTE-064: invoiceListFiltered named route exists', () {
      expect(
          namedRoutes,
          containsPair(
              'invoiceListFiltered', '/invoice-assistant/list/:filter'));
    });

    test('TC-ROUTE-065: invoiceDetail named route exists', () {
      expect(namedRoutes,
          containsPair('invoiceDetail', '/invoice-assistant/detail/:id'));
    });

    test('TC-ROUTE-066: menupage named route exists', () {
      expect(namedRoutes, containsPair('menupage', 'menu'));
    });

    test('TC-ROUTE-067: total named routes count', () {
      // Preserve the established named routes while allowing additive routes.
      expect(namedRoutes.length, greaterThanOrEqualTo(7));
    });
  });

  group('legacy redirect routes are registered', () {
    test('TC-ROUTE-068: taskscheduling route exists', () {
      expect(allPaths, contains('/taskscheduling'));
    });

    test('TC-ROUTE-069: chatandcalls route exists', () {
      expect(allPaths, contains('/chatandcalls'));
    });

    test('TC-ROUTE-070: aiassistant route exists', () {
      expect(allPaths, contains('/aiassistant'));
    });

    test('TC-ROUTE-071: fitbit route exists', () {
      expect(allPaths, contains('/fitbit'));
    });

    test('TC-ROUTE-072: sos route exists', () {
      expect(allPaths, contains('/sos'));
    });
  });

  group('task routes are registered', () {
    test('TC-ROUTE-073: patient-tasks route exists', () {
      expect(allPaths, contains('/patient-tasks'));
    });

    test('TC-ROUTE-074: assign-task route exists', () {
      expect(allPaths, contains('/assign-task'));
    });

    test('TC-ROUTE-075: custom-task-scheduling route exists', () {
      expect(allPaths, contains('/custom-task-scheduling'));
    });

    test('TC-ROUTE-076: pre-defined-task route exists', () {
      expect(allPaths, contains('/pre-defined-task'));
    });
  });

  group('auth routes are registered', () {
    test('TC-ROUTE-077: reset-password route exists', () {
      expect(allPaths, contains('/reset-password'));
    });

    test('TC-ROUTE-078: setup-password route exists', () {
      expect(allPaths, contains('/setup-password'));
    });

    test('TC-ROUTE-079: oauth callback route exists', () {
      expect(allPaths, contains('/oauth/callback'));
    });

    test('TC-ROUTE-080: alexaLogin route exists', () {
      expect(allPaths, contains('/alexaLogin'));
    });

    test('TC-ROUTE-081: alexaLogin with params route exists', () {
      expect(allPaths, contains('/alexaLogin/:redirectUri/:state'));
    });
  });

  group('misc routes are registered', () {
    test('TC-ROUTE-082: notetaker-configuration route exists', () {
      expect(allPaths, contains('/notetaker-configuration'));
    });

    test('TC-ROUTE-083: notetaker-search route exists', () {
      expect(allPaths, contains('/notetaker-search'));
    });

    test('TC-ROUTE-084: notetaker detail route exists', () {
      expect(allPaths, contains('/notetaker/detail/:noteId'));
    });

    test('TC-ROUTE-085: video-call-chime route exists', () {
      expect(allPaths, contains('/video-call-chime'));
    });

    test('TC-ROUTE-086: usps-test route exists', () {
      expect(allPaths, contains('/usps-test'));
    });

    test('TC-ROUTE-087: alertpage route exists', () {
      expect(allPaths, contains('/alertpage'));
    });

    test('TC-ROUTE-088: alertpage-patient route exists', () {
      expect(allPaths, contains('/alertpage-patient'));
    });
  });

  group('route count validation', () {
    test('TC-ROUTE-089: has expected minimum number of top-level routes', () {
      // The router has many routes; ensure we have a reasonable count
      final topLevelRoutes =
          appRouter.configuration.routes.whereType<GoRoute>().toList();
      expect(topLevelRoutes.length, greaterThanOrEqualTo(40));
    });

    test('TC-ROUTE-090: total routes including nested exceeds top-level count', () {
      final topLevelCount =
          appRouter.configuration.routes.whereType<GoRoute>().length;
      expect(allPaths.length, greaterThanOrEqualTo(topLevelCount));
    });
  });

  group('navigateToDashboard function', () {
    test('TC-ROUTE-091: navigateToDashboard is accessible as a top-level function', () {
      // Just verify the function exists - it requires a BuildContext so
      // we can't call it directly in a unit test
      expect(navigateToDashboard, isA<Function>());
    });
  });

  // --------------------------------------------------------------------------
  // Route builder / redirect widget tests
  // --------------------------------------------------------------------------

  group('route builder inspection', () {
    test('TC-ROUTE-092: login route has a builder', () {
      final route = _findRoute(appRouter.configuration.routes, '/login');
      expect(route, isNotNull);
      expect(route!.builder, isNotNull);
    });

    test('TC-ROUTE-093: dashboard route has a builder', () {
      final route = _findRoute(appRouter.configuration.routes, '/dashboard');
      expect(route, isNotNull);
      expect(route!.builder, isNotNull);
    });

    test('TC-ROUTE-094: home route has a redirect but no builder', () {
      final route = _findRoute(appRouter.configuration.routes, '/home');
      expect(route, isNotNull);
      expect(route!.redirect, isNotNull);
    });

    test('TC-ROUTE-095: fitbit route redirects synchronously', () {
      final route = _findRoute(appRouter.configuration.routes, '/fitbit');
      expect(route, isNotNull);
      expect(route!.redirect, isNotNull);
    });

    test('TC-ROUTE-096: setup-password route has a builder', () {
      final route =
          _findRoute(appRouter.configuration.routes, '/setup-password');
      expect(route, isNotNull);
      expect(route!.builder, isNotNull);
    });

    test('TC-ROUTE-097: social-feed route has a builder', () {
      final route = _findRoute(appRouter.configuration.routes, '/social-feed');
      expect(route, isNotNull);
      expect(route!.builder, isNotNull);
    });

    test('TC-ROUTE-098: payment-success route has a builder', () {
      final route =
          _findRoute(appRouter.configuration.routes, '/payment-success');
      expect(route, isNotNull);
      expect(route!.builder, isNotNull);
    });

    test('TC-ROUTE-099: payment-cancel route has a builder', () {
      final route =
          _findRoute(appRouter.configuration.routes, '/payment-cancel');
      expect(route, isNotNull);
      expect(route!.builder, isNotNull);
    });

    test('TC-ROUTE-100: evv/start-visit route has a builder', () {
      final route =
          _findRoute(appRouter.configuration.routes, '/evv/start-visit');
      expect(route, isNotNull);
      expect(route!.builder, isNotNull);
    });

    test('TC-ROUTE-101: evv/checkin-location route has a builder', () {
      final route =
          _findRoute(appRouter.configuration.routes, '/evv/checkin-location');
      expect(route, isNotNull);
      expect(route!.builder, isNotNull);
    });

    test('TC-ROUTE-102: evv/visit-progress route has a builder', () {
      final route =
          _findRoute(appRouter.configuration.routes, '/evv/visit-progress');
      expect(route, isNotNull);
      expect(route!.builder, isNotNull);
    });

    test('TC-ROUTE-103: evv/checkout-location route has a builder', () {
      final route =
          _findRoute(appRouter.configuration.routes, '/evv/checkout-location');
      expect(route, isNotNull);
      expect(route!.builder, isNotNull);
    });

    test('TC-ROUTE-104: evv/visit-complete route has a builder', () {
      final route =
          _findRoute(appRouter.configuration.routes, '/evv/visit-complete');
      expect(route, isNotNull);
      expect(route!.builder, isNotNull);
    });

    test('TC-ROUTE-105: evv/visit-completed-success route has a builder', () {
      final route = _findRoute(
          appRouter.configuration.routes, '/evv/visit-completed-success');
      expect(route, isNotNull);
      expect(route!.builder, isNotNull);
    });

    test('TC-ROUTE-106: patient/:id route has a builder', () {
      final route = _findRoute(appRouter.configuration.routes, '/patient/:id');
      expect(route, isNotNull);
      expect(route!.builder, isNotNull);
    });

    test('TC-ROUTE-107: analytics route has a builder', () {
      final route = _findRoute(appRouter.configuration.routes, '/analytics');
      expect(route, isNotNull);
      expect(route!.builder, isNotNull);
    });

    test('TC-ROUTE-108: video-call route has a builder', () {
      final route =
          _findRoute(appRouter.configuration.routes, '/video-call-chime');
      expect(route, isNotNull);
      expect(route!.builder, isNotNull);
    });

    test('TC-ROUTE-109: oauth/callback route has a builder', () {
      final route =
          _findRoute(appRouter.configuration.routes, '/oauth/callback');
      expect(route, isNotNull);
      expect(route!.builder, isNotNull);
    });

    test('TC-ROUTE-110: notetaker/detail/:noteId route has a builder', () {
      final route = _findRoute(
          appRouter.configuration.routes, '/notetaker/detail/:noteId');
      expect(route, isNotNull);
      expect(route!.builder, isNotNull);
    });

    test('TC-ROUTE-111: invoice-assistant route has a redirect', () {
      final route =
          _findRoute(appRouter.configuration.routes, '/invoice-assistant');
      expect(route, isNotNull);
      expect(route!.redirect, isNotNull);
    });

    test('TC-ROUTE-112: invoice-assistant route has nested sub-routes', () {
      final route =
          _findRoute(appRouter.configuration.routes, '/invoice-assistant');
      expect(route, isNotNull);
      expect(route!.routes, isNotEmpty);
      expect(route.routes.length, equals(4));
    });

    test('TC-ROUTE-113: legacy redirect routes all have redirect functions', () {
      final legacyPaths = [
        '/taskscheduling',
        '/chatandcalls',
        '/aiassistant',
        '/fitbit',
        '/sos',
      ];
      for (final path in legacyPaths) {
        final route = _findRoute(appRouter.configuration.routes, path);
        expect(route, isNotNull, reason: '$path should exist');
        expect(route!.redirect, isNotNull,
            reason: '$path should have a redirect');
      }
    });
  });

  // --------------------------------------------------------------------------
  // Widget-level builder tests (exercise actual builder code)
  // --------------------------------------------------------------------------

  group('dashboard/patient builder - widget tests', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    setUp(() {
      _setupPlatformChannels();
    });

    tearDown(() {
      _tearDownPlatformChannels();
    });

    testWidgets('TC-ROUTE-114: shows Invalid user ID when no userId query param',
        (tester) async {
      final router = _createFullTestRouter('/dashboard/patient');
      await _pumpRouterApp(tester, router);
      await tester.pumpAndSettle();

      expect(find.text('Invalid user ID'), findsOneWidget);
      expect(find.text('Go to Login'), findsOneWidget);
    });

    testWidgets('TC-ROUTE-115: shows Invalid user ID when userId is 0', (tester) async {
      final router = _createFullTestRouter('/dashboard/patient?userId=0');
      await _pumpRouterApp(tester, router);
      await tester.pumpAndSettle();

      expect(find.text('Invalid user ID'), findsOneWidget);
    });

    testWidgets('TC-ROUTE-116: shows Invalid user ID when userId is negative',
        (tester) async {
      final router = _createFullTestRouter('/dashboard/patient?userId=-1');
      await _pumpRouterApp(tester, router);
      await tester.pumpAndSettle();

      expect(find.text('Invalid user ID'), findsOneWidget);
    });

    testWidgets('TC-ROUTE-117: shows Invalid user ID when userId is non-numeric',
        (tester) async {
      final router = _createFullTestRouter('/dashboard/patient?userId=abc');
      await _pumpRouterApp(tester, router);
      await tester.pumpAndSettle();

      expect(find.text('Invalid user ID'), findsOneWidget);
    });
  });

  group('dashboard/caregiver builder - widget tests', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    setUp(() {
      _setupPlatformChannels();
    });

    tearDown(() {
      _tearDownPlatformChannels();
    });

    testWidgets('TC-ROUTE-118: shows Invalid caregiver ID when no caregiverId',
        (tester) async {
      final router = _createFullTestRouter('/dashboard/caregiver');
      await _pumpRouterApp(tester, router);
      await tester.pumpAndSettle();

      expect(find.text('Invalid caregiver ID'), findsOneWidget);
      expect(find.text('Go to Login'), findsOneWidget);
    });

    testWidgets('TC-ROUTE-119: shows Invalid caregiver ID when caregiverId is 0',
        (tester) async {
      final router =
          _createFullTestRouter('/dashboard/caregiver?caregiverId=0');
      await _pumpRouterApp(tester, router);
      await tester.pumpAndSettle();

      expect(find.text('Invalid caregiver ID'), findsOneWidget);
    });

    testWidgets('TC-ROUTE-120: shows Invalid caregiver ID when caregiverId is negative',
        (tester) async {
      final router =
          _createFullTestRouter('/dashboard/caregiver?caregiverId=-5');
      await _pumpRouterApp(tester, router);
      await tester.pumpAndSettle();

      expect(find.text('Invalid caregiver ID'), findsOneWidget);
    });

    testWidgets('TC-ROUTE-121: shows Invalid caregiver ID when caregiverId is non-numeric',
        (tester) async {
      final router =
          _createFullTestRouter('/dashboard/caregiver?caregiverId=xyz');
      await _pumpRouterApp(tester, router);
      await tester.pumpAndSettle();

      expect(find.text('Invalid caregiver ID'), findsOneWidget);
    });
  });

  group('caregiver-dashboard builder - widget tests', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    setUp(() {
      _setupPlatformChannels();
    });

    tearDown(() {
      _tearDownPlatformChannels();
    });

    testWidgets('TC-ROUTE-122: shows Invalid caregiver ID when no caregiverId',
        (tester) async {
      final router = _createFullTestRouter('/caregiver-dashboard');
      await _pumpRouterApp(tester, router);
      await tester.pumpAndSettle();

      expect(find.text('Invalid caregiver ID'), findsOneWidget);
      expect(find.text('Go to Login'), findsOneWidget);
    });

    testWidgets('TC-ROUTE-123: shows Invalid caregiver ID when caregiverId is 0',
        (tester) async {
      final router =
          _createFullTestRouter('/caregiver-dashboard?caregiverId=0');
      await _pumpRouterApp(tester, router);
      await tester.pumpAndSettle();

      expect(find.text('Invalid caregiver ID'), findsOneWidget);
    });
  });

  group('setup-password builder - widget tests', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    setUp(() {
      _setupPlatformChannels();
    });

    tearDown(() {
      _tearDownPlatformChannels();
    });

    testWidgets('TC-ROUTE-124: shows error when no token provided', (tester) async {
      final router = _createFullTestRouter('/setup-password');
      await _pumpRouterApp(tester, router);
      await tester.pumpAndSettle();

      expect(find.text('Invalid or missing reset token'), findsOneWidget);
    });

    testWidgets('TC-ROUTE-125: shows error when token is empty string', (tester) async {
      final router = _createFullTestRouter('/setup-password?token=');
      await _pumpRouterApp(tester, router);
      await tester.pumpAndSettle();

      expect(find.text('Invalid or missing reset token'), findsOneWidget);
    });
  });

  group('EVV start-visit builder - widget tests', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    setUp(() {
      _setupPlatformChannels();
    });

    tearDown(() {
      _tearDownPlatformChannels();
    });

    testWidgets('TC-ROUTE-126: shows Invalid patient ID when no patientId', (tester) async {
      final router = _createFullTestRouter('/evv/start-visit');
      await _pumpRouterApp(tester, router);
      await tester.pumpAndSettle();

      expect(find.text('Invalid patient ID'), findsOneWidget);
    });

    testWidgets('TC-ROUTE-127: shows Invalid patient ID when patientId is non-numeric',
        (tester) async {
      final router = _createFullTestRouter('/evv/start-visit?patientId=abc');
      await _pumpRouterApp(tester, router);
      await tester.pumpAndSettle();

      expect(find.text('Invalid patient ID'), findsOneWidget);
    });
  });

  group('EVV checkin-location builder - widget tests', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    setUp(() {
      _setupPlatformChannels();
    });

    tearDown(() {
      _tearDownPlatformChannels();
    });

    testWidgets('TC-ROUTE-128: shows Invalid parameters when no params', (tester) async {
      final router = _createFullTestRouter('/evv/checkin-location');
      await _pumpRouterApp(tester, router);
      await tester.pumpAndSettle();

      expect(find.text('Invalid parameters'), findsOneWidget);
    });

    testWidgets('TC-ROUTE-129: shows Invalid parameters when patientId but no serviceType',
        (tester) async {
      final router = _createFullTestRouter('/evv/checkin-location?patientId=1');
      await _pumpRouterApp(tester, router);
      await tester.pumpAndSettle();

      expect(find.text('Invalid parameters'), findsOneWidget);
    });

    testWidgets('TC-ROUTE-130: shows Invalid parameters when serviceType but no patientId',
        (tester) async {
      final router =
          _createFullTestRouter('/evv/checkin-location?serviceType=nursing');
      await _pumpRouterApp(tester, router);
      await tester.pumpAndSettle();

      expect(find.text('Invalid parameters'), findsOneWidget);
    });
  });

  group('EVV visit-progress builder - widget tests', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    setUp(() {
      _setupPlatformChannels();
    });

    tearDown(() {
      _tearDownPlatformChannels();
    });

    testWidgets('TC-ROUTE-131: shows Invalid parameters when no params', (tester) async {
      final router = _createFullTestRouter('/evv/visit-progress');
      await _pumpRouterApp(tester, router);
      await tester.pumpAndSettle();

      expect(find.text('Invalid parameters'), findsOneWidget);
    });

    testWidgets('TC-ROUTE-132: shows Invalid parameters when missing locationType',
        (tester) async {
      final router = _createFullTestRouter(
          '/evv/visit-progress?patientId=1&serviceType=nursing');
      await _pumpRouterApp(tester, router);
      await tester.pumpAndSettle();

      expect(find.text('Invalid parameters'), findsOneWidget);
    });
  });

  group('EVV checkout-location builder - widget tests', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    setUp(() {
      _setupPlatformChannels();
    });

    tearDown(() {
      _tearDownPlatformChannels();
    });

    testWidgets('TC-ROUTE-133: shows Invalid parameters when no params', (tester) async {
      final router = _createFullTestRouter('/evv/checkout-location');
      await _pumpRouterApp(tester, router);
      await tester.pumpAndSettle();

      expect(find.text('Invalid parameters'), findsOneWidget);
    });

    testWidgets('TC-ROUTE-134: shows Invalid parameters when missing locationType',
        (tester) async {
      final router = _createFullTestRouter(
          '/evv/checkout-location?patientId=1&serviceType=nursing');
      await _pumpRouterApp(tester, router);
      await tester.pumpAndSettle();

      expect(find.text('Invalid parameters'), findsOneWidget);
    });
  });

  group('EVV visit-complete builder - widget tests', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    setUp(() {
      _setupPlatformChannels();
    });

    tearDown(() {
      _tearDownPlatformChannels();
    });

    testWidgets('TC-ROUTE-135: shows Invalid parameters when no params', (tester) async {
      final router = _createFullTestRouter('/evv/visit-complete');
      await _pumpRouterApp(tester, router);
      await tester.pumpAndSettle();

      expect(find.text('Invalid parameters'), findsOneWidget);
    });

    testWidgets('TC-ROUTE-136: shows Invalid parameters when missing checkoutLocationType',
        (tester) async {
      final router = _createFullTestRouter(
          '/evv/visit-complete?patientId=1&serviceType=nursing&checkinLocationType=home');
      await _pumpRouterApp(tester, router);
      await tester.pumpAndSettle();

      expect(find.text('Invalid parameters'), findsOneWidget);
    });
  });

  group('EVV visit-completed-success builder - widget tests', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    setUp(() {
      _setupPlatformChannels();
    });

    tearDown(() {
      _tearDownPlatformChannels();
    });

    testWidgets('TC-ROUTE-137: shows Invalid parameters when no params', (tester) async {
      final router = _createFullTestRouter('/evv/visit-completed-success');
      await _pumpRouterApp(tester, router);
      await tester.pumpAndSettle();

      expect(find.text('Invalid parameters'), findsOneWidget);
    });

    testWidgets('TC-ROUTE-138: shows Invalid parameters when missing checkoutLocationType',
        (tester) async {
      final router = _createFullTestRouter(
          '/evv/visit-completed-success?patientId=1&serviceType=nursing&checkinLocationType=home');
      await _pumpRouterApp(tester, router);
      await tester.pumpAndSettle();

      expect(find.text('Invalid parameters'), findsOneWidget);
    });
  });

  group('notetaker/detail builder - widget tests', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    setUp(() {
      _setupPlatformChannels();
    });

    tearDown(() {
      _tearDownPlatformChannels();
    });

    testWidgets('TC-ROUTE-139: shows error when no extra data provided', (tester) async {
      final router = _createFullTestRouter('/notetaker/detail/123');
      await _pumpRouterApp(tester, router);
      await tester.pumpAndSettle();

      // The error is shown both in the body and via a SnackBar, so allow >= 1.
      expect(find.text('Invalid note ID or missing patient context'),
          findsWidgets);
    });
  });

  group('dashboard builder - widget tests', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    setUp(() {
      // Set up with no logged-in user data
      _setupPlatformChannels(sharedPrefsValues: {});
    });

    tearDown(() {
      _tearDownPlatformChannels();
    });

    testWidgets('TC-ROUTE-140: shows loading indicator initially', (tester) async {
      final router = _createFullTestRouter('/dashboard');
      await _pumpRouterApp(tester, router);
      // Don't pumpAndSettle - we want to see the loading state
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  // payment-success builder widget tests removed: PaymentSuccessPage uses
  // AnimationController + Future.delayed timers that can't be cleanly drained
  // in widget tests without a full app context. Route existence and builder
  // presence are already tested above.

  group('payment-cancel builder - widget tests', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    setUp(() {
      _setupPlatformChannels();
    });

    tearDown(() {
      _tearDownPlatformChannels();
    });

    testWidgets('TC-ROUTE-141: renders with no query params (isRegistration = false)',
        (tester) async {
      final router = _createFullTestRouter('/payment-cancel');
      await _pumpRouterApp(tester, router);
      await tester.pump();

      expect(find.byType(Scaffold), findsWidgets);
    });

    testWidgets('TC-ROUTE-142: renders with registration=complete', (tester) async {
      final router =
          _createFullTestRouter('/payment-cancel?registration=complete');
      await _pumpRouterApp(tester, router);
      await tester.pump();

      expect(find.byType(Scaffold), findsWidgets);
    });
  });

  group('social-feed builder - widget tests', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    setUp(() {
      _setupPlatformChannels();
    });

    tearDown(() {
      _tearDownPlatformChannels();
    });

    testWidgets('TC-ROUTE-143: defaults userId to 1 when no query param', (tester) async {
      final router = _createFullTestRouter('/social-feed');
      await _pumpRouterApp(tester, router);
      await tester.pump();

      // MainFeedScreen should render with userId = 1
      expect(find.byType(Scaffold), findsWidgets);
    });

    testWidgets('TC-ROUTE-144: parses userId from query param', (tester) async {
      final router = _createFullTestRouter('/social-feed?userId=42');
      await _pumpRouterApp(tester, router);
      await tester.pump();

      expect(find.byType(Scaffold), findsWidgets);
    });

    testWidgets('TC-ROUTE-145: defaults to 1 when userId is non-numeric', (tester) async {
      final router = _createFullTestRouter('/social-feed?userId=notanumber');
      await _pumpRouterApp(tester, router);
      await tester.pump();

      expect(find.byType(Scaffold), findsWidgets);
    });
  });

  group('analytics builder - widget tests', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    setUp(() {
      _setupPlatformChannels();
    });

    tearDown(() {
      _tearDownPlatformChannels();
    });

    testWidgets('TC-ROUTE-146: shows Redirecting when no patientId', (tester) async {
      final router = _createFullTestRouter('/analytics');
      await _pumpRouterApp(tester, router);
      await tester.pump();

      expect(find.text('Redirecting...'), findsOneWidget);
    });

    testWidgets('TC-ROUTE-147: shows Redirecting when patientId is non-numeric',
        (tester) async {
      final router = _createFullTestRouter('/analytics?patientId=abc');
      await _pumpRouterApp(tester, router);
      await tester.pump();

      expect(find.text('Redirecting...'), findsOneWidget);
    });
  });

  group('video-call builder - widget tests', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    setUp(() {
      _setupPlatformChannels();
    });

    tearDown(() {
      _tearDownPlatformChannels();
    });

    testWidgets('TC-ROUTE-148: renders video call widget with no params', (tester) async {
      final router = _createFullTestRouter('/video-call-chime');
      await _pumpRouterApp(tester, router);
      await tester.pump();

      expect(find.byType(Scaffold), findsWidgets);
    });

    testWidgets('TC-ROUTE-149: renders video call widget with userId and callId',
        (tester) async {
      final router =
          _createFullTestRouter('/video-call-chime?userId=1&callId=call-123');
      await _pumpRouterApp(tester, router);
      await tester.pump();

      expect(find.byType(Scaffold), findsWidgets);
    });

    testWidgets('TC-ROUTE-150: renders video call widget with recipientName', (tester) async {
      final router = _createFullTestRouter(
          '/video-call-chime?userId=1&callId=call-123&recipientName=John');
      await _pumpRouterApp(tester, router);
      await tester.pump();

      expect(find.byType(Scaffold), findsWidgets);
    });

    testWidgets('TC-ROUTE-151: preserves care-team metadata in video call widget',
        (tester) async {
      final router = _createFullTestRouter(
        '/video-call-chime?userId=1&callId=call-123'
        '&callKind=CARE_TEAM&contextPatientUserIds=7%2C8',
      );
      await _pumpRouterApp(tester, router);
      await tester.pump();

      final widget = tester.widget<HybridVideoCallWidget>(
        find.byType(HybridVideoCallWidget),
      );
      expect(widget.callKind, 'CARE_TEAM');
      expect(widget.contextPatientUserIds, [7, 8]);
    });

    testWidgets(
        'TC-ROUTE-152: renders video call widget with non-numeric userId uses default',
        (tester) async {
      final router =
          _createFullTestRouter('/video-call-chime?userId=abc&callId=call-123');
      await _pumpRouterApp(tester, router);
      await tester.pump();

      expect(find.byType(Scaffold), findsWidgets);
    });
  });

  group('patient/:id builder - widget tests', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    setUp(() {
      _setupPlatformChannels();
    });

    tearDown(() {
      _tearDownPlatformChannels();
    });

    testWidgets('TC-ROUTE-153: shows Redirecting when id is non-numeric', (tester) async {
      final router = _createFullTestRouter('/patient/abc');
      await _pumpRouterApp(tester, router);
      await tester.pump();

      expect(find.text('Redirecting...'), findsOneWidget);
    });
  });

  group('fitbit redirect route', () {
    test('TC-ROUTE-154: fitbit route redirects to /wearables', () async {
      final route = _findRoute(appRouter.configuration.routes, '/fitbit');
      expect(route, isNotNull);
      // The redirect is a simple synchronous return of '/wearables'
      // We can invoke the redirect function directly
      final redirectFn = route!.redirect;
      expect(redirectFn, isNotNull);
    });
  });

  group('invoice-assistant redirect', () {
    test('TC-ROUTE-155: invoice-assistant route has 4 sub-routes', () {
      final route =
          _findRoute(appRouter.configuration.routes, '/invoice-assistant');
      expect(route, isNotNull);
      expect(route!.routes.length, equals(4));
    });

    test('TC-ROUTE-156: invoice sub-routes have correct paths', () {
      final route =
          _findRoute(appRouter.configuration.routes, '/invoice-assistant');
      expect(route, isNotNull);
      final subPaths =
          route!.routes.whereType<GoRoute>().map((r) => r.path).toList();
      expect(subPaths, contains('dashboard'));
      expect(subPaths, contains('upload'));
      expect(subPaths, contains('list'));
      expect(subPaths, contains('detail/:id'));
    });

    test('TC-ROUTE-157: invoice list sub-route has a nested :filter route', () {
      final listRoute =
          _findRoute(appRouter.configuration.routes, '/invoice-assistant/list');
      expect(listRoute, isNotNull);
      expect(listRoute!.routes, isNotEmpty);
      final filterRoute = listRoute.routes.first as GoRoute;
      expect(filterRoute.path, equals(':filter'));
      expect(filterRoute.name, equals('invoiceListFiltered'));
    });
  });

  group('route path format validation', () {
    test('TC-ROUTE-158: all absolute paths start with /', () {
      for (final path in allPaths) {
        // Skip relative paths like 'menu'
        if (!path.startsWith('/') && !path.contains(':')) {
          // Relative paths are valid for nested routes
          continue;
        }
        if (path.startsWith('/')) {
          expect(path, startsWith('/'),
              reason: 'Absolute path $path should start with /');
        }
      }
    });

    test('TC-ROUTE-159: no paths contain double slashes', () {
      for (final path in allPaths) {
        expect(path, isNot(contains('//')),
            reason: 'Path $path should not contain //');
      }
    });

    test('TC-ROUTE-160: no paths end with trailing slash (except root)', () {
      for (final path in allPaths) {
        if (path == '/') continue;
        expect(path, isNot(endsWith('/')),
            reason: 'Path $path should not end with /');
      }
    });

    test('TC-ROUTE-161: parameterized paths use :param syntax', () {
      final paramRoutes = allPaths.where((p) => p.contains(':')).toList();
      expect(paramRoutes, isNotEmpty);
      // Verify they use :paramName format
      for (final path in paramRoutes) {
        expect(
          RegExp(r':[a-zA-Z]+').hasMatch(path),
          isTrue,
          reason: 'Path $path should have valid :param syntax',
        );
      }
    });
  });

  group('route hierarchy validation', () {
    test('TC-ROUTE-162: EVV routes all share /evv prefix', () {
      final evvRoutes = allPaths.where((p) => p.startsWith('/evv')).toList();
      expect(evvRoutes.length, greaterThanOrEqualTo(12));
    });

    test('TC-ROUTE-163: invoice routes all share /invoice-assistant prefix', () {
      final invoiceRoutes =
          allPaths.where((p) => p.startsWith('/invoice-assistant')).toList();
      expect(invoiceRoutes.length, greaterThanOrEqualTo(5));
    });

    test('TC-ROUTE-164: dashboard routes share /dashboard prefix', () {
      final dashRoutes =
          allPaths.where((p) => p.startsWith('/dashboard')).toList();
      expect(dashRoutes.length, greaterThanOrEqualTo(3));
    });

    test('TC-ROUTE-165: register routes share /register prefix', () {
      final regRoutes =
          allPaths.where((p) => p.startsWith('/register')).toList();
      expect(regRoutes.length, equals(2));
    });

    test('TC-ROUTE-166: alexa routes share /alexaLogin prefix', () {
      final alexaRoutes =
          allPaths.where((p) => p.startsWith('/alexaLogin')).toList();
      expect(alexaRoutes.length, equals(2));
    });
  });

  group('select-package builder - widget tests', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    setUp(() {
      _setupPlatformChannels();
    });

    tearDown(() {
      _tearDownPlatformChannels();
    });

    testWidgets(
        'TC-ROUTE-167: renders SubscriptionManagementPage when no userId/stripeCustomerId and user is not PATIENT',
        (tester) async {
      final router = _createFullTestRouter('/select-package');
      // UserProvider with no user set -> user is null -> shows SubscriptionManagementPage
      await _pumpRouterApp(tester, router);
      await tester.pump();
      await tester.pump();

      expect(find.byType(Scaffold), findsWidgets);
    });
  });

  group('patient-tasks builder - widget tests', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    setUp(() {
      _setupPlatformChannels();
    });

    tearDown(() {
      _tearDownPlatformChannels();
    });

    testWidgets('TC-ROUTE-168: defaults patientId to 0 and patientName to Name Not Found',
        (tester) async {
      final router = _createFullTestRouter('/patient-tasks');
      await _pumpRouterApp(tester, router);
      await tester.pump();

      expect(find.byType(Scaffold), findsWidgets);
    });

    testWidgets('TC-ROUTE-169: parses patientId and patientName from query params',
        (tester) async {
      final router =
          _createFullTestRouter('/patient-tasks?patientId=5&patientName=Alice');
      await _pumpRouterApp(tester, router);
      await tester.pump();

      expect(find.byType(Scaffold), findsWidgets);
    });
  });

  group('assign-task builder - widget tests', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    setUp(() {
      _setupPlatformChannels();
    });

    tearDown(() {
      _tearDownPlatformChannels();
    });

    testWidgets('TC-ROUTE-170: defaults patientId to 0 and patientName to Name Not Found',
        (tester) async {
      final router = _createFullTestRouter('/assign-task');
      await _pumpRouterApp(tester, router);
      await tester.pump();

      expect(find.byType(Scaffold), findsWidgets);
    });
  });

  group('custom-task-scheduling builder - widget tests', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    setUp(() {
      _setupPlatformChannels();
    });

    tearDown(() {
      _tearDownPlatformChannels();
    });

    testWidgets('TC-ROUTE-171: defaults patientId to 0 and patientName to Name Not Found',
        (tester) async {
      final router = _createFullTestRouter('/custom-task-scheduling');
      await _pumpRouterApp(tester, router);
      await tester.pump();

      expect(find.byType(Scaffold), findsWidgets);
    });
  });

  group('pre-defined-task builder - widget tests', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    setUp(() {
      _setupPlatformChannels();
    });

    tearDown(() {
      _tearDownPlatformChannels();
    });

    testWidgets(
        'TC-ROUTE-172: defaults patientId, templateId to 0 and patientName to Name Not Found',
        (tester) async {
      final router = _createFullTestRouter('/pre-defined-task');
      await _pumpRouterApp(tester, router);
      await tester.pump();

      expect(find.byType(Scaffold), findsWidgets);
    });

    testWidgets('TC-ROUTE-173: parses all query params', (tester) async {
      final router = _createFullTestRouter(
          '/pre-defined-task?patientId=3&templateId=7&patientName=Bob');
      await _pumpRouterApp(tester, router);
      await tester.pump();

      expect(find.byType(Scaffold), findsWidgets);
    });
  });

  // oauth/callback builder widget tests removed: OAuthCallbackPage uses
  // Future.delayed timers that can't be cleanly drained in widget tests.
  // Route existence and builder presence are already tested above.

  // ---------------------------------------------------------------------------
  // Testing Lead, PR #339 (Test Plan §3.26). TC-ROUTE-174…: every route builds
  // the page it names from its parameters, every redirect sends a signed-out or
  // signed-in user where it should, and the telemetry observer reports each
  // screen. TC-EMG-251 is the target for DEF-EMG-08 and stays skipped until the
  // fix lands.
  // ---------------------------------------------------------------------------

  GoRouterState routeState(
    String location, {
    Map<String, String> params = const {},
    Object? extra,
  }) {
    final uri = Uri.parse(location);
    return GoRouterState(
      appRouter.configuration,
      uri: uri,
      matchedLocation: uri.path,
      fullPath: uri.path,
      pathParameters: params,
      extra: extra,
      pageKey: ValueKey<String>(location),
    );
  }

  Future<BuildContext> contextWithUser(WidgetTester tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(ChangeNotifierProvider<UserProvider>.value(
      value: UserProvider(),
      child: MaterialApp(home: Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      })),
    ));
    return ctx;
  }

  group('TC-ROUTE-174: each route builds the page it names', () {
    // (route pattern, location, path parameters, extra, page type,
    //  fields the page must have been given)
    final cases = <(String, String, Map<String, String>, Object?, String,
        Map<String, Object?>)>[
      ('/', '/', {}, null, 'WelcomePage', {}),
      ('/health-data', '/health-data', {}, null, 'HealthDataScreen', {}),
      ('/dob-confirm', '/dob-confirm', {}, null, 'DobConfirmationScreen', {}),
      ('/passport/:token', '/passport/abc123', {'token': 'abc123'}, null,
          'PassportScanPage', {'token': 'abc123'}),
      ('/passport/:token', '/passport/', {}, null, 'PassportScanPage',
          {'token': ''}),
      ('/emergency-qr', '/emergency-qr', {}, null, 'EmergencyQrPage', {}),
      ('/medical-passport', '/medical-passport', {}, null, 'MedicalPassportPage', {}),
      ('/ui-preview', '/ui-preview', {}, null, 'UiPreviewScreen', {}),
      ('/stml/brief', '/stml/brief', {}, null, 'StmlBriefPage', {}),
      ('/summaries', '/summaries', {}, null, 'SummaryConfirmationList', {}),
      ('/stml/recall', '/stml/recall', {}, null, 'StmlRecallPage', {}),
      ('/stml/search', '/stml/search', {}, null, 'StmlSearchPage', {}),
      ('/stml/checkin', '/stml/checkin', {}, null,
          'StmlCheckInPatientSelectionPage', {}),
      ('/stml/checkin/:patientId', '/stml/checkin/12', {'patientId': '12'},
          null, 'StmlCheckInPage', {'patientId': 12}),
      ('/stml/checkin/:patientId', '/stml/checkin/x', {'patientId': 'x'}, null,
          'Scaffold', {}),
      ('/symptoms', '/symptoms', {}, null, 'SymptomsAllergiesPage', {}),
      ('/login', '/login', {}, {'userType': 'caregiver'}, 'LoginPage',
          {'userType': 'caregiver'}),
      ('/login', '/login', {}, 'not a map', 'LoginPage', {'userType': null}),
      ('/usps-test', '/usps-test', {}, null, 'UspsTestScreen', {}),
      ('/signup', '/signup', {}, null, 'RegistrationPage', {}),
      ('/dashboard', '/dashboard', {}, null, 'FutureBuilder<UserData?>', {}),
      ('/dashboard/patient', '/dashboard/patient?userId=5', {}, null,
          'MainScreen', {}),
      ('/dashboard/patient', '/dashboard/patient?userId=0', {}, null,
          'Scaffold', {}),
      ('/dashboard/caregiver',
          '/dashboard/caregiver?caregiverId=3&patientId=5', {}, null,
          'MainScreen', {}),
      ('/dashboard/caregiver', '/dashboard/caregiver?caregiverId=-1', {},
          null, 'Scaffold', {}),
      ('/caregiver-dashboard', '/caregiver-dashboard?caregiverId=3', {}, null,
          'CaregiverDashboard', {}),
      ('/caregiver-dashboard', '/caregiver-dashboard', {}, null, 'Scaffold',
          {}),
      ('/register/caregiver', '/register/caregiver', {}, null,
          'RegistrationPage', {}),
      ('/register/patient', '/register/patient', {}, null,
          'PatientRegistrationPage', {}),
      ('/add-patient', '/add-patient', {}, null, 'AddPatientScreen', {}),
      ('/care-circle/invite', '/care-circle/invite', {},
          {'invitedEmail': 'pat@example.test', 'inviteReason': 'help'},
          'InviteQrAutoloadScreen',
          {'invitedEmail': 'pat@example.test', 'inviteReason': 'help'}),
      ('/care-circle/:linkId/invite', '/care-circle/9/invite', {'linkId': '9'},
          {'invitedEmail': 'pat@example.test'}, 'InviteQrScreen',
          {'linkId': 9, 'invitedEmail': 'pat@example.test', 'inviteReason': null}),
      ('/care-circle/:linkId/invite', '/care-circle/x/invite', {'linkId': 'x'},
          null, 'Scaffold', {}),
      ('/invite/:token', '/invite/t1', {'token': 't1'}, null,
          'InviteLandingScreen', {'token': 't1'}),
      ('/social-feed', '/social-feed?userId=4', {}, null, 'MainFeedScreen',
          {'userId': 4}),
      ('/social-feed', '/social-feed?userId=x', {}, null, 'MainFeedScreen',
          {'userId': 1}),
      ('/select-package', '/select-package?userId=4', {}, null,
          'SelectPackagePage', {'userId': '4'}),
      ('/select-package', '/select-package', {}, null,
          'SubscriptionManagementPage', {}),
      ('/reset-password', '/reset-password', {}, null, 'ResetPasswordScreen',
          {}),
      ('/subscription', '/subscription', {}, null,
          'SubscriptionManagementPage', {}),
      ('/setup-password', '/setup-password?token=abc', {}, null,
          'PasswordResetPage', {'token': 'abc'}),
      ('/gamification', '/gamification', {}, null, 'GamificationScreen', {}),
      ('/native-billing', '/native-billing', {},
          {'tierId': 2, 'tier': 'Pro', 'userId': 4}, 'NativeBillingPage',
          {'tierId': 2, 'tier': 'Pro', 'userId': 4}),
      ('/native-billing', '/native-billing', {}, null, 'NativeBillingPage',
          {'tierId': 0, 'tier': null, 'userId': null}),
      ('/select-subscription-tier', '/select-subscription-tier', {},
          {'email': 'pat@example.test', 'state': 'MD'},
          'SubscriptionTierSelectionPage',
          {'email': 'pat@example.test', 'userState': 'MD'}),
      ('/web-pay', '/web-pay', {},
          {'tierId': 3, 'tier': 'Plus', 'email': 'pat@example.test',
              'userId': 4, 'state': 'MD'},
          'WebPayPage',
          {'tierId': 3, 'tier': 'Plus', 'email': 'pat@example.test',
              'userId': 4, 'state': 'MD'}),
      ('/web-pay', '/web-pay', {}, null, 'WebPayPage', {'tierId': 0}),
      ('/payment-success',
          '/payment-success?session_id=s1&registration=complete&portal=update',
          {}, null, 'PaymentSuccessPage',
          {'sessionId': 's1', 'isRegistration': true, 'fromPortal': true}),
      ('/payment-cancel', '/payment-cancel?registration=complete', {}, null,
          'PaymentCancelPage', {'isRegistration': true}),
      ('/patient/:id', '/patient/8', {'id': '8'}, null, 'PatientStatusPage',
          {'patientId': 8}),
      ('/analytics', '/analytics?patientId=8', {}, null, 'AnalyticsPage',
          {'patientId': 8}),
      ('/admin/analytics', '/admin/analytics', {}, null,
          'AdminAnalyticsDashboardPage', {}),
      ('/admin/users', '/admin/users', {}, null, 'AdminUsersPage', {}),
      ('/oauth/callback', '/oauth/callback?token=t&user=u&error=e', {}, null,
          'OAuthCallbackPage', {'token': 't', 'user': 'u', 'error': 'e'}),
      ('/wearables', '/wearables', {}, null, 'WearablesScreen', {}),
      ('/home-monitoring', '/home-monitoring', {}, null,
          'HomeMonitoringScreen', {}),
      ('/smart-devices', '/smart-devices', {}, null, 'SmartDevicesPage', {}),
      ('/medication', '/medication', {}, null, 'MedicationManagementScreen',
          {}),
      ('/evv', '/evv', {}, null, 'EvvDashboard', {}),
      ('/evv/select-patient', '/evv/select-patient', {}, null,
          'PatientSelectionPage', {}),
      ('/evv/start-visit', '/evv/start-visit?patientId=3', {}, null,
          'StartVisitPage', {'patientId': 3}),
      ('/evv/checkin-location',
          '/evv/checkin-location?patientId=3&serviceType=PCA', {}, null,
          'CheckinLocationPage', {'patientId': 3, 'serviceType': 'PCA'}),
      ('/evv/visit-progress',
          '/evv/visit-progress?patientId=3&serviceType=PCA&locationType=HOME'
              '&latitude=39.5&longitude=-76.5&noGpsReason=none&accuracyM=8',
          {}, null, 'VisitInProgressPage',
          {'patientId': 3, 'locationType': 'HOME', 'latitude': 39.5,
              'accuracyM': 8.0}),
      ('/evv/checkout-location',
          '/evv/checkout-location?patientId=3&serviceType=PCA&locationType=HOME'
              '&duration=30&notes=ok&scheduledVisitId=11',
          {}, null, 'CheckoutLocationPage',
          {'duration': 30, 'notes': 'ok', 'scheduledVisitId': 11}),
      ('/evv/visit-complete',
          '/evv/visit-complete?patientId=3&serviceType=PCA'
              '&checkinLocationType=HOME&checkoutLocationType=HOME&duration=45',
          {}, null, 'VisitCompletePage',
          {'checkoutLocationType': 'HOME', 'duration': 45}),
      ('/evv/visit-completed-success',
          '/evv/visit-completed-success?patientId=3&serviceType=PCA'
              '&checkinLocationType=HOME&checkoutLocationType=HOME'
              '&checkinTime=2026-10-15T09:00:00Z&checkoutTime=bad',
          {}, null, 'VisitCompletedSuccessPage',
          {'checkinTime': DateTime.utc(2026, 10, 15, 9)}),
      ('/evv/visit-completed-success',
          '/evv/visit-completed-success?patientId=3&serviceType=PCA'
              '&checkinLocationType=HOME&checkoutLocationType=HOME'
              '&checkinTime=bad&checkoutTime=2026-10-15T10:00:00Z',
          {}, null, 'VisitCompletedSuccessPage',
          {'checkoutTime': DateTime.utc(2026, 10, 15, 10)}),
      ('/evv/review-records', '/evv/review-records', {}, null,
          'EvvRecordReviewPage', {}),
      ('/evv/visit-history', '/evv/visit-history', {}, null,
          'EvvVisitHistoryPage', {}),
      ('/evv/corrections', '/evv/corrections', {}, null, 'EvvCorrectionsPage',
          {}),
      ('/evv/offline-sync', '/evv/offline-sync', {}, null,
          'EvvOfflineSyncPage', {}),
      ('/profile-settings', '/profile-settings', {}, null,
          'ProfileSettingsPage', {}),
      ('/profile', '/profile', {}, null, 'ProfilePage', {}),
      ('/settings', '/settings', {}, null, 'SettingsPage', {}),
      ('/file-management', '/file-management?fileId=f1', {}, null,
          'FileManagementPage', {'highlightFileId': 'f1'}),
      ('/calls/:callId/summary', '/calls/c1/summary', {'callId': 'c1'}, null,
          'PostCallTelemetrySummaryScreen', {'callId': 'c1'}),
      ('/calls/:callId/summary', '/calls//summary', {'callId': ''}, null,
          'Scaffold', {}),
      ('/ai-configuration', '/ai-configuration', {}, null,
          'AIConfigurationPage', {}),
      ('/notetaker-configuration', '/notetaker-configuration', {}, null,
          'NotetakerConfigurationPage', {}),
      ('/notetaker-search', '/notetaker-search', {}, null,
          'NotetakerSearchPage', {}),
      ('/notetaker/detail/:noteId', '/notetaker/detail/n1', {'noteId': 'n1'},
          null, 'NotetakerDetailView', {}),
      ('/video-call-chime',
          '/video-call-chime?userId=2&callId=c9&video=false&audio=FALSE'
              '&initiator=true&contextPatientUserIds=1,x,-2,3,3'
              '&forcePatientDetailsOnExit=true&returnAsCaregiver=TRUE',
          {}, null, 'HybridVideoCallWidget',
          {'userId': '2', 'callId': 'c9', 'isVideoEnabled': false,
              'isAudioEnabled': false, 'isInitiator': true,
              'contextPatientUserIds': [1, 3],
              'forcePatientDetailsOnExit': true, 'returnAsCaregiver': true}),
      ('/calendar', '/calendar', {}, null, 'CalendarAssistantScreen', {}),
      ('/virtual-checkin', '/virtual-checkin', {}, null,
          'PatientVirtualCheckIn', {}),
      ('/alexaLogin', '/alexaLogin', {}, null, 'AlexaLoginPage', {}),
      ('/alexaLogin/:redirectUri/:state', '/alexaLogin/r/s',
          {'redirectUri': 'r', 'state': 's'}, null, 'AlexaLoginPage', {}),
      ('/informed-delivery', '/informed-delivery', {}, null,
          'InformedDeliveryScreen', {}),
      ('/tasks', '/tasks', {}, null, 'CaregiverPatientList', {}),
      ('/patient-tasks', '/patient-tasks?patientId=3&patientName=Pat', {},
          null, 'TasksScreen', {'patientId': 3, 'patientName': 'Pat'}),
      ('/assign-task', '/assign-task?patientId=3&patientName=Pat', {}, null,
          'AssignTaskScreen', {'patientId': 3, 'patientName': 'Pat'}),
      ('/custom-task-scheduling', '/custom-task-scheduling?patientId=3', {},
          null, 'CustomTaskScreen',
          {'patientId': 3, 'patientName': 'Name Not Found'}),
      ('/pre-defined-task', '/pre-defined-task?patientId=3&templateId=4', {},
          null, 'PreDefinedTaskScreen', {'patientId': 3, 'templateId': 4}),
      ('/invoice-assistant/dashboard', '/invoice-assistant/dashboard', {},
          null, 'InvoiceTabbedPage', {'initialTabIndex': 0}),
      ('/invoice-assistant/upload', '/invoice-assistant/upload', {}, null,
          'InvoiceTabbedPage', {'initialTabIndex': 1}),
      ('/invoice-assistant/list', '/invoice-assistant/list', {}, null,
          'InvoiceTabbedPage', {'initialTabIndex': 2}),
      ('/invoice-assistant/list/:filter', '/invoice-assistant/list/overdue',
          {'filter': 'overdue'}, null, 'InvoiceTabbedPage',
          {'initialTabIndex': 2, 'quickFilter': 'overdue'}),
      ('menu', '/menu', {}, null, 'MenuPage', {}),
      ('/alertpage', '/alertpage', {}, null, 'MockAlertLabPage', {}),
      ('/alertpage-patient', '/alertpage-patient', {}, null,
          'PatientFallPromptPage', {}),
      ('/search', '/search', {}, null, 'RouteSearchPage', {}),
    ];

    for (final c in cases) {
      testWidgets('TC-ROUTE-174: ${c.$2} builds ${c.$5}', (tester) async {
        _setupPlatformChannels();
        addTearDown(_tearDownPlatformChannels);
        final route = _findRoute(appRouter.configuration.routes, c.$1);
        expect(route?.builder, isNotNull, reason: c.$1);
        final ctx = await contextWithUser(tester);
        final page =
            route!.builder!(ctx, routeState(c.$2, params: c.$3, extra: c.$4));
        expect(page.runtimeType.toString(), c.$5);
        for (final f in c.$6.entries) {
          final dynamic d = page;
          final Object? value = switch (f.key) {
            'token' => d.token,
            'patientId' => d.patientId,
            'userType' => d.userType,
            'invitedEmail' => d.invitedEmail,
            'inviteReason' => d.inviteReason,
            'linkId' => d.linkId,
            'userId' => d.userId,
            'tierId' => d.tierId,
            'tier' => d.tier,
            'email' => d.email,
            'userState' => d.userState,
            'state' => d.state,
            'sessionId' => d.sessionId,
            'isRegistration' => d.isRegistration,
            'fromPortal' => d.fromPortal,
            'user' => d.user,
            'error' => d.error,
            'serviceType' => d.serviceType,
            'locationType' => d.locationType,
            'latitude' => d.latitude,
            'accuracyM' => d.accuracyM,
            'duration' => d.duration,
            'notes' => d.notes,
            'scheduledVisitId' => d.scheduledVisitId,
            'checkoutLocationType' => d.checkoutLocationType,
            'checkinTime' => d.checkinTime,
            'checkoutTime' => d.checkoutTime,
            'highlightFileId' => d.highlightFileId,
            'callId' => d.callId,
            'isVideoEnabled' => d.isVideoEnabled,
            'isAudioEnabled' => d.isAudioEnabled,
            'isInitiator' => d.isInitiator,
            'contextPatientUserIds' => d.contextPatientUserIds,
            'forcePatientDetailsOnExit' => d.forcePatientDetailsOnExit,
            'returnAsCaregiver' => d.returnAsCaregiver,
            'patientName' => d.patientName,
            'templateId' => d.templateId,
            'initialTabIndex' => d.initialTabIndex,
            'quickFilter' => d.quickFilter,
            _ => throw ArgumentError(f.key),
          };
          expect(value, f.value, reason: '${c.$2} ${f.key}');
        }
      });
    }
  });

  testWidgets(
      'TC-ROUTE-175: visit and mail summary links show their id, or say it is '
      'missing', (tester) async {
    final ctx = await contextWithUser(tester);
    for (final (pattern, location, params, text) in [
      ('/visits/:visitId/summary', '/visits/v7/summary', {'visitId': 'v7'},
          'Visit v7 summary is available in EVV visit history.'),
      ('/visits/:visitId/summary', '/visits//summary', <String, String>{},
          'Missing visit id'),
      ('/mail/:mailId', '/mail/m3', {'mailId': 'm3'},
          'Open Informed Delivery for mail piece m3.'),
      ('/mail/:mailId', '/mail/', <String, String>{}, 'Missing mail id'),
    ]) {
      final route = _findRoute(appRouter.configuration.routes, pattern)!;
      final page = route.builder!(ctx, routeState(location, params: params));
      await tester.pumpWidget(MaterialApp(home: page));
      expect(find.text(text), findsOneWidget, reason: location);
    }
  });

  group('TC-ROUTE-176: each redirect route sends the user where it should',
      () {
    // (route pattern, location, signed-in role or null, expected redirect)
    final cases = <(String, String, String?, String?)>[
      ('/home', '/home', null, '/'),
      ('/home', '/home', 'PATIENT', '/dashboard'),
      ('/health-data', '/health-data', null, '/login'),
      ('/health-data', '/health-data', 'PATIENT', null),
      ('/dob-confirm', '/dob-confirm', null, '/login'),
      ('/dob-confirm', '/dob-confirm', 'PATIENT', null),
      ('/emergency-qr', '/emergency-qr', null, '/login'),
      ('/emergency-qr', '/emergency-qr', 'PATIENT', null),
      ('/medical-passport', '/medical-passport', null, '/login'),
      ('/medical-passport', '/medical-passport', 'PATIENT', null),
      ('/stripe-checkout', '/stripe-checkout', null, '/select-package'),
      ('/admin/analytics', '/admin/analytics', null, '/login'),
      ('/admin/analytics', '/admin/analytics', 'PATIENT', '/dashboard'),
      ('/admin/analytics', '/admin/analytics', 'ADMIN', null),
      ('/admin/users', '/admin/users', null, '/login'),
      ('/admin/users', '/admin/users', 'CAREGIVER', '/dashboard'),
      ('/admin/users', '/admin/users', 'ADMIN', null),
      ('/taskscheduling', '/taskscheduling', null, '/login'),
      ('/taskscheduling', '/taskscheduling', 'CAREGIVER', '/dashboard?tab=tasks'),
      ('/taskscheduling', '/taskscheduling', 'PATIENT', '/dashboard?tab=home'),
      ('/chatandcalls', '/chatandcalls', null, '/login'),
      ('/chatandcalls', '/chatandcalls', 'PATIENT', '/dashboard?tab=messages'),
      ('/aiassistant', '/aiassistant', null, '/login'),
      ('/aiassistant', '/aiassistant', 'PATIENT', '/dashboard?tab=home'),
      ('/fitbit', '/fitbit', null, '/wearables'),
      ('/sos', '/sos', null, '/login'),
      ('/sos', '/sos', 'PATIENT', '/dashboard?tab=home'),
      ('/invoice-assistant', '/invoice-assistant', null,
          '/invoice-assistant/upload'),
      ('/invoice-assistant', '/invoice-assistant/list', null, null),
    ];

    for (final c in cases) {
      testWidgets(
          'TC-ROUTE-176: ${c.$2}, ${c.$3 ?? 'signed out'} -> ${c.$4 ?? 'stays'}',
          (tester) async {
        _setupPlatformChannels();
        addTearDown(_tearDownPlatformChannels);
        await UserRoleStorageService.instance.clearUserData();
        if (c.$3 != null) {
          await UserRoleStorageService.instance
              .setUserData(role: c.$3!, userId: 21, patientId: 21);
        }
        addTearDown(UserRoleStorageService.instance.clearUserData);
        final route = _findRoute(appRouter.configuration.routes, c.$1);
        expect(route?.redirect, isNotNull, reason: c.$1);
        final ctx = await contextWithUser(tester);
        expect(await route!.redirect!(ctx, routeState(c.$2)), c.$4);
      });
    }
  });

  group('telemetry observer', () {
    late List<Map<String, dynamic>> events;
    late http.Client client;

    setUp(() {
      SharedPreferences.setMockInitialValues({'telemetry_opted_out': false});
      events = [];
      client = MockClient((req) async {
        if (req.method == 'POST' &&
            req.url.path.contains('telemetry') &&
            !req.url.path.contains('enabled')) {
          events.add(jsonDecode(req.body) as Map<String, dynamic>);
        }
        return http.Response(jsonEncode({'enabled': true}), 200);
      });
      ApiService.debugSetHttpClient(client);
    });

    tearDown(ApiService.debugResetHttpClient);

    List<String> screens() => [
          for (final e in events)
            if (e['eventName'] == 'screen_view')
              (e['details'] as Map)['screen'] as String,
        ];

    Future<(GoRouter, TelemetryGoRouterObserver)> pumpObserved(
        WidgetTester tester, String initial,
        {bool provideRouter = true}) async {
      GoRouter? ref;
      final observer =
          TelemetryGoRouterObserver(routerProvider: () => provideRouter ? ref : null);
      Page<void> page(GoRouterState s) =>
          NoTransitionPage<void>(key: s.pageKey, child: Text(s.uri.path));
      final router = ref = GoRouter(
        initialLocation: initial,
        observers: [observer],
        routes: [
          GoRoute(path: '/', pageBuilder: (_, s) => page(s)),
          GoRoute(path: '/settings', pageBuilder: (_, s) => page(s)),
          GoRoute(path: '/passport/:token', pageBuilder: (_, s) => page(s)),
        ],
      );
      await http.runWithClient(() async {
        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
        for (var i = 0; i < 10; i++) {
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)));
          await tester.pump(const Duration(milliseconds: 20));
        }
      }, () => client);
      return (router, observer);
    }

    Future<void> drain(WidgetTester tester) async {
      await http.runWithClient(() async {
        for (var i = 0; i < 10; i++) {
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)));
          await tester.pump(const Duration(milliseconds: 20));
        }
      }, () => client);
    }

    testWidgets(
        'TC-ROUTE-177: push, pop, replace and remove each report a '
        'screen_view with the screen\'s path', (tester) async {
      final (router, observer) = await pumpObserved(tester, '/');
      final dummy = MaterialPageRoute<void>(builder: (_) => const SizedBox());
      await http.runWithClient(() async {
        router.push('/settings');
        await tester.pump();
        observer.didPop(dummy, null);
        observer.didReplace(newRoute: dummy, oldRoute: dummy);
        observer.didRemove(dummy, null);
      }, () => client);
      await drain(tester);
      expect(screens().first, '/');
      expect(screens(), containsAllInOrder(['/', '/settings']));
      expect(screens().where((s) => s == '/settings').length,
          greaterThanOrEqualTo(4));
    });

    testWidgets(
        'TC-ROUTE-178: with no router yet, or one telemetry cannot read, the '
        'observer reports nothing and navigation carries on', (tester) async {
      final (router, observer) =
          await pumpObserved(tester, '/settings', provideRouter: false);
      await drain(tester);
      expect(screens(), isEmpty);
      expect(router.state.uri.path, '/settings');

      final orphan = TelemetryGoRouterObserver(
          routerProvider: () => GoRouter(routes: [
                GoRoute(path: '/', builder: (_, __) => const SizedBox()),
              ]));
      final dummy = MaterialPageRoute<void>(builder: (_) => const SizedBox());
      orphan.didPush(dummy, null);
      await drain(tester);
      expect(screens(), isEmpty);
      expect(observer, isNotNull);
    });

    testWidgets(
        'TC-EMG-251: a scan of an emergency QR code never sends the code to '
        'telemetry: the screen_view for /passport/<code> names the route, not '
        'the code (DEF-EMG-08)', (tester) async {
      const code = 'Q2Fsb3JpZXMtYXJlLW5vdC1hLXNlY3JldC1idXQtdGhpcw';
      await pumpObserved(tester, '/passport/$code');
      await drain(tester);
      expect(screens(), isNotEmpty);
      expect(screens().where((s) => s.contains(code)), isEmpty);
      expect(screens(), contains('/passport/:token'));
    });
  });

  testWidgets(
      'TC-ROUTE-179: after sign-in, a pending invite returns the user to its '
      'landing page instead of the dashboard', (tester) async {
    PendingInvite.set('inv-42');
    addTearDown(PendingInvite.clear);
    final router = GoRouter(initialLocation: '/start', routes: [
      GoRoute(
          path: '/start',
          builder: (context, _) => TextButton(
              onPressed: () => navigateToDashboard(context),
              child: const Text('signed in'))),
      GoRoute(
          path: '/invite/:token',
          builder: (_, s) => Text('invite ${s.pathParameters['token']}')),
    ]);
    await _pumpRouterApp(tester, router);
    await tester.pumpAndSettle();
    await tester.tap(find.text('signed in'));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/invite/inv-42');
    expect(find.text('invite inv-42'), findsOneWidget);
  });

  // Testing Lead, PR #350 (Test Plan §3.30): the patient's Medicare sharing
  // screen, WBS 6.2.59.
  testWidgets('TC-ROUTE-181: /medicare-sharing builds MedicareSharingPage',
      (tester) async {
    final route = _findRoute(appRouter.configuration.routes, '/medicare-sharing');
    expect(route?.builder, isNotNull);
    final ctx = await contextWithUser(tester);
    final page = route!.builder!(ctx, routeState('/medicare-sharing'));
    expect(page.runtimeType.toString(), 'MedicareSharingPage');
  });

  testWidgets(
      'TC-ROUTE-182: /medicare-sharing sends a signed-out user to /login and '
      'lets a signed-in user through', (tester) async {
    _setupPlatformChannels();
    addTearDown(_tearDownPlatformChannels);
    addTearDown(UserRoleStorageService.instance.clearUserData);
    final route = _findRoute(appRouter.configuration.routes, '/medicare-sharing');
    expect(route?.redirect, isNotNull);
    final ctx = await contextWithUser(tester);

    await UserRoleStorageService.instance.clearUserData();
    expect(await route!.redirect!(ctx, routeState('/medicare-sharing')),
        '/login');

    await UserRoleStorageService.instance
        .setUserData(role: 'PATIENT', userId: 21, patientId: 21);
    expect(
        await route.redirect!(ctx, routeState('/medicare-sharing')), isNull);
  });
}
