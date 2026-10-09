// MedicareConnectPage (/medicare-connect): hosts the connect tile, keeps the
// ?medicare= result for exactly one showing, and always offers a way back,
// even when the patient arrived by a full-page redirect from Medicare.
// Test IDs TC-MCR-CONN-037..040 are permanent. Never renumber, never reuse.

import 'package:care_connect_app/features/health/health_data/pages/medicare_connect_page.dart';
import 'package:care_connect_app/features/health/health_data/services/medicare_connect_service.dart';
import 'package:care_connect_app/features/health/health_data/widgets/medicare_connect_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _NotConnected extends MedicareConnectService {
  @override
  Future<MedicareStatus?> status() async => const MedicareStatus(connected: false);
}

GoRouter _router(String initial) => GoRouter(
      initialLocation: initial,
      routes: [
        GoRoute(
          path: '/health-data',
          builder: (context, _) => Scaffold(
            body: TextButton(
              onPressed: () => context.push('/medicare-connect'),
              child: const Text('health data home'),
            ),
          ),
        ),
        GoRoute(
          path: '/medicare-connect',
          builder: (_, __) => const MedicareConnectPage(result: MedicareConnectResult.cancelled),
        ),
      ],
    );

String _path(GoRouter r) => r.routerDelegate.currentConfiguration.uri.path;

void main() {
  late MedicareConnectService original;

  setUp(() {
    original = MedicareConnectService.instance;
    MedicareConnectService.instance = _NotConnected();
    MedicareConnectPage.pendingResult = null;
  });

  tearDown(() {
    MedicareConnectService.instance = original;
    MedicareConnectPage.pendingResult = null;
  });

  test('TC-MCR-CONN-037: a pending ?medicare= result is handed out once, then forgotten', () {
    MedicareConnectPage.pendingResult = MedicareConnectResult.connected;

    expect(MedicareConnectPage.takePendingResult(), MedicareConnectResult.connected);
    expect(MedicareConnectPage.takePendingResult(), isNull);
  });

  testWidgets('TC-MCR-CONN-038: shows the title, the explanation and the tile, passing the result to the tile', (t) async {
    await t.pumpWidget(MaterialApp.router(routerConfig: _router('/medicare-connect')));
    await t.pumpAndSettle();

    expect(find.text('Connect Medicare'), findsOneWidget);
    expect(find.textContaining('Connect your Medicare account'), findsOneWidget);
    final tile = t.widget<MedicareConnectTile>(find.byType(MedicareConnectTile));
    expect(tile.result, MedicareConnectResult.cancelled);
  });

  testWidgets('TC-MCR-CONN-039: arriving by redirect (nothing to go back to), Back goes to Health Data', (t) async {
    final router = _router('/medicare-connect');
    await t.pumpWidget(MaterialApp.router(routerConfig: router));
    await t.pumpAndSettle();

    await t.tap(find.byTooltip('Back to Health Data'));
    await t.pumpAndSettle();

    expect(_path(router), '/health-data');
  });

  testWidgets('TC-MCR-CONN-040: arriving from Health Data, Back returns there', (t) async {
    final router = _router('/health-data');
    await t.pumpWidget(MaterialApp.router(routerConfig: router));
    await t.pumpAndSettle();
    await t.tap(find.text('health data home'));
    await t.pumpAndSettle();
    // A push keeps the base location in the router's uri, so check the screen.
    expect(find.text('Connect Medicare'), findsOneWidget);

    await t.tap(find.byTooltip('Back to Health Data'));
    await t.pumpAndSettle();

    expect(find.text('Connect Medicare'), findsNothing);
    expect(find.text('health data home'), findsOneWidget);
    expect(_path(router), '/health-data');
  });
}
