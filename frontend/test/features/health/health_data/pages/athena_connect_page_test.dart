// AthenaConnectPage (/athena-connect): the intro text, the full athenahealth
// tile, and Back with and without a page to go back to.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:care_connect_app/features/health/health_data/pages/athena_connect_page.dart';
import 'package:care_connect_app/features/health/health_data/services/athena_connect_service.dart';
import 'package:care_connect_app/features/health/health_data/widgets/athena_connect_tile.dart';

class _NotConnected extends AthenaConnectService {
  @override
  Future<AthenaStatus?> status() async => const AthenaStatus(
      connected: false, reason: AthenaNotConnectedReason.notConsented);
}

GoRouter _router(String initial) => GoRouter(
      initialLocation: initial,
      routes: [
        GoRoute(
            path: '/health-data',
            builder: (context, _) => Scaffold(
                  body: TextButton(
                      onPressed: () => context.push('/athena-connect'),
                      child: const Text('Health Data stub')),
                )),
        GoRoute(
            path: '/athena-connect',
            builder: (_, __) => const AthenaConnectPage()),
      ],
    );

String _path(GoRouter r) => r.routerDelegate.currentConfiguration.uri.path;

void main() {
  late AthenaConnectService original;
  setUp(() {
    original = AthenaConnectService.instance;
    AthenaConnectService.instance = _NotConnected();
  });
  tearDown(() => AthenaConnectService.instance = original);

  Future<GoRouter> open(WidgetTester t, String initial) async {
    await t.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final r = _router(initial);
    await t.pumpWidget(MaterialApp.router(routerConfig: r));
    await t.pumpAndSettle();
    return r;
  }

  testWidgets('shows the title, the intro and the full tile with its consent',
      (t) async {
    await open(t, '/athena-connect');
    expect(find.text('Connect athenahealth'), findsWidgets);
    expect(find.textContaining('Connect your athenahealth provider'),
        findsOneWidget);
    final tile = t.widget<AthenaConnectTile>(find.byType(AthenaConnectTile));
    expect(tile.compact, isFalse);
    expect(tile.buttonOnly, isFalse);
    expect(find.text(AthenaConnectTile.consentText), findsOneWidget);
    expect(find.text('Not connected'), findsOneWidget);
  });

  testWidgets('Back with nothing to go back to opens Health Data', (t) async {
    final r = await open(t, '/athena-connect');
    await t.tap(find.byTooltip('Back to Health Data'));
    await t.pumpAndSettle();
    expect(_path(r), '/health-data');
  });

  testWidgets('Back after opening it from Health Data goes back there',
      (t) async {
    final r = await open(t, '/health-data');
    await t.tap(find.text('Health Data stub'));
    await t.pumpAndSettle();
    expect(find.byType(AthenaConnectPage), findsOneWidget);
    await t.tap(find.byTooltip('Back to Health Data'));
    await t.pumpAndSettle();
    expect(find.byType(AthenaConnectPage), findsNothing);
    expect(_path(r), '/health-data');
  });

  // R381-D01: live, /athena-connect with athena turned off showed only
  // "Couldn't check the connection" and a Try again that looped.
  testWidgets('a status that cannot be read still offers consent and Connect',
      (t) async {
    AthenaConnectService.instance = _Unreadable();
    await open(t, '/athena-connect');
    expect(find.text('Couldn\'t check the connection'), findsNothing);
    expect(find.text('Try again'), findsNothing);
    expect(find.text(AthenaConnectTile.consentText), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Connect athenahealth'),
        findsOneWidget);
  });
}

class _Unreadable extends AthenaConnectService {
  @override
  Future<AthenaStatus?> status() async => null;
}
