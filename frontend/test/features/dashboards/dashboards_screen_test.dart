// Tests for DashboardsScreen (lib/features/dashboards/dashboards_screen.dart).
//
// Each tile opens its trend page in a TitledMaterialPageRoute, so the browser
// tab names the page (WCAG 2.4.2). The probe reads the pushed route's title
// without building the trend pages, which load data from the backend.
import 'package:care_connect_app/features/dashboards/dashboards_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/titled_route_probe.dart';

void main() {
  late TitledRouteProbe probe;

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    probe = TitledRouteProbe();
    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [probe],
      home: const DashboardsScreen(clientId: 7, clientName: 'Mary Johnson'),
    ));
  }

  testWidgets('shows the hub with the client name', (tester) async {
    await pumpScreen(tester);
    expect(find.text('Dashboards'), findsOneWidget);
    expect(find.textContaining('Mary Johnson'), findsWidgets);
  });

  const tiles = {
    'Competency Trends': 'Competency Trend',
    'Behavioral Frequency': 'Behavioral Trend',
    'Participation': 'Participation',
  };

  for (final entry in tiles.entries) {
    testWidgets('"${entry.key}" opens a page titled "${entry.value}"',
        (tester) async {
      await pumpScreen(tester);
      expect(await probe.tapAndReadTitle(tester, find.text(entry.key).first),
          entry.value);
    });
  }
}
