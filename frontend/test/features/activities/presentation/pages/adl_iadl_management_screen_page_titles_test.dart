// Page-title tests for AdlIadlManagementScreen
// (lib/features/activities/presentation/pages/adl_iadl_management_screen.dart):
// each card opens its page with a title (WCAG 2.4.2).
import 'package:care_connect_app/features/activities/presentation/pages/adl_iadl_management_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/titled_route_probe.dart';

void main() {
  for (final (card, title) in [
    ('ADL Activities', 'Daily Living Activities'),
    ('IADL Activities', 'Daily Living Activities'),
    ('Activity log history', 'Activity Log History'),
  ]) {
    testWidgets('$card opens a page titled "$title"', (tester) async {
      final probe = TitledRouteProbe();
      await tester.pumpWidget(MaterialApp(
        navigatorObservers: [probe],
        home: const AdlIadlManagementScreen(
            clientId: 1, clientName: 'Alice Smith'),
      ));
      expect(await probe.tapAndReadTitle(tester, find.text(card)), title);
    });
  }
}
