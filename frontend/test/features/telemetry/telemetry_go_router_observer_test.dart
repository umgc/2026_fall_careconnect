// Tests for TelemetryGoRouterObserver (lib/config/router/app_router.dart).
//
// Coverage strategy:
//   Uses a minimal GoRouter with placeholder Scaffold pages so no real CareConnect
//   routes, providers, or platform setup are required. The observer is wired to
//   the test router via [TelemetryGoRouterObserver.routerProvider].
//   HTTP is intercepted with ApiService.debugSetHttpClient and http.runWithClient
//   + MockClient. SharedPreferences is mocked via setMockInitialValues.

import 'dart:convert';

import 'package:care_connect_app/config/router/app_router.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _settleTimeout = Duration(seconds: 1);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  GoRouter? testRouterRef;
  late TelemetryGoRouterObserver observer;
  late GoRouter testRouter;

  setUp(() {
    SharedPreferences.setMockInitialValues({'telemetry_opted_out': false});

    testRouterRef = null;
    observer = TelemetryGoRouterObserver(routerProvider: () => testRouterRef);
    testRouter = testRouterRef = GoRouter(
      initialLocation: '/',
      observers: [observer],
      routes: [
        GoRoute(
          path: '/',
          pageBuilder: (context, state) => NoTransitionPage<void>(
            key: state.pageKey,
            child: const Scaffold(body: Text('home')),
          ),
        ),
        GoRoute(
          path: '/login',
          pageBuilder: (context, state) => NoTransitionPage<void>(
            key: state.pageKey,
            child: const Scaffold(body: Text('login')),
          ),
        ),
      ],
    );
  });

  tearDown(() {
    ApiService.debugResetHttpClient();
  });

  MockClient telemetryMockClient({
    required List<Map<String, dynamic>> capturedEvents,
    bool throwOnEventPost = false,
  }) {
    return MockClient((req) async {
      if (req.method == 'GET' && req.url.path.contains('enabled')) {
        return http.Response(jsonEncode({'enabled': true}), 200);
      }

      if (req.method == 'PUT' && req.url.path.contains('enabled')) {
        return http.Response(jsonEncode({'enabled': false}), 200);
      }

      if (req.method == 'POST' &&
          req.url.path.contains('telemetry') &&
          !req.url.path.contains('enabled')) {
        if (throwOnEventPost) {
          throw Exception('telemetry post failed');
        }
        capturedEvents.add(jsonDecode(req.body) as Map<String, dynamic>);
      }

      return http.Response(jsonEncode({'enabled': true}), 200);
    });
  }

  Future<void> waitForPendingTelemetry(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> pumpUntilSettled(WidgetTester tester) async {
    try {
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        _settleTimeout,
      );
    } on FlutterError {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpRouterUntilReady(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: testRouter));
    await pumpUntilSettled(tester);
  }

  Future<void> disposeRouterWidget(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  Map<String, dynamic>? latestScreenViewEvent(
    List<Map<String, dynamic>> capturedEvents,
  ) {
    for (var i = capturedEvents.length - 1; i >= 0; i--) {
      if (capturedEvents[i]['eventName'] == 'screen_view') {
        return capturedEvents[i];
      }
    }
    return null;
  }

  group('TelemetryGoRouterObserver', () {
    testWidgets('didPush logs screen_view for the current router location', (
      tester,
    ) async {
      final capturedEvents = <Map<String, dynamic>>[];
      final client = telemetryMockClient(capturedEvents: capturedEvents);
      ApiService.debugSetHttpClient(client);

      await http.runWithClient(() async {
        await pumpRouterUntilReady(tester);
        capturedEvents.clear();

        testRouter.go('/login');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        observer.didPush(_testRoute(), null);
        await waitForPendingTelemetry(tester);

        final event = latestScreenViewEvent(capturedEvents);
        expect(event, isNotNull);
        expect(event!['eventName'], 'screen_view');
        expect(event['details'], isA<Map>());
        expect((event['details'] as Map)['screen'], '/login');
      }, () => client);

      await disposeRouterWidget(tester);
    });

    testWidgets('logs screen_view when navigating to a new route', (
      tester,
    ) async {
      final capturedEvents = <Map<String, dynamic>>[];
      final client = telemetryMockClient(capturedEvents: capturedEvents);
      ApiService.debugSetHttpClient(client);

      await http.runWithClient(() async {
        await pumpRouterUntilReady(tester);
        capturedEvents.clear();

        testRouter.go('/login');
        await pumpUntilSettled(tester);
        await waitForPendingTelemetry(tester);

        final event = latestScreenViewEvent(capturedEvents);
        expect(event, isNotNull);
        expect(event!['eventName'], 'screen_view');
        expect((event['details'] as Map)['screen'], '/login');
        expect(find.text('login'), findsOneWidget);
      }, () => client);

      await disposeRouterWidget(tester);
    });

    testWidgets('does not POST telemetry events when opted out locally', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'telemetry_opted_out': true});
      final capturedEvents = <Map<String, dynamic>>[];
      final client = telemetryMockClient(capturedEvents: capturedEvents);
      ApiService.debugSetHttpClient(client);

      await http.runWithClient(() async {
        await pumpRouterUntilReady(tester);
        capturedEvents.clear();

        testRouter.go('/login');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        observer.didPush(_testRoute(), null);
        await waitForPendingTelemetry(tester);

        expect(capturedEvents, isEmpty);
      }, () => client);

      await disposeRouterWidget(tester);
    });

    testWidgets('continues navigation when telemetry POST fails', (
      tester,
    ) async {
      final capturedEvents = <Map<String, dynamic>>[];
      final client = telemetryMockClient(
        capturedEvents: capturedEvents,
        throwOnEventPost: true,
      );
      ApiService.debugSetHttpClient(client);

      await http.runWithClient(() async {
        await pumpRouterUntilReady(tester);

        testRouter.go('/login');
        await pumpUntilSettled(tester);
        await waitForPendingTelemetry(tester);

        expect(testRouter.state.uri.toString(), '/login');
        expect(find.text('login'), findsOneWidget);
        expect(find.byType(MaterialApp), findsOneWidget);
      }, () => client);

      await disposeRouterWidget(tester);
    });
  });
}

PageRoute<void> _testRoute() {
  return PageRouteBuilder<void>(
    pageBuilder: (_, __, ___) => const SizedBox.shrink(),
  );
}
